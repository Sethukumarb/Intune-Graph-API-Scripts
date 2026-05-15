#Requires -Version 5.1
# ==============================================================================
# Script Name  : Import-AutopilotDevicesWithPreflightCheck.ps1
# Description  : Imports Windows Autopilot devices from one or more hardware
#                hash CSV files located in the Import folder inside the script
#                root directory.
#
#                PRE-IMPORT STAGING CHECK (built-in):
#                  Before submitting any device, the script queries both:
#                    1. windowsAutopilotDeviceIdentities   - actual Autopilot registry
#                    2. importedWindowsAutopilotDeviceIdentities - staging queue
#                  Devices are classified per serial number:
#
#                  DECISION MATRIX:
#                  ┌──────────────────────────────────────────────┬──────────────────────────┐
#                  │ Condition                                     │ Action                   │
#                  ├──────────────────────────────────────────────┼──────────────────────────┤
#                  │ Present in windowsAutopilotDeviceIdentities  │ SKIP  (already enrolled) │
#                  │ Present in staging with status = complete    │ SKIP  (recently imported)│
#                  │ Present in staging with status = error       │ RE-IMPORT                │
#                  │ Not found anywhere                           │ FRESH IMPORT             │
#                  └──────────────────────────────────────────────┴──────────────────────────┘
#
#                HOW IT WORKS:
#                  1. Scans Import\ subfolder for all .csv files
#                  2. Validates each CSV has required columns (case-insensitive)
#                  3. Runs pre-import staging + Autopilot registry check
#                  4. Classifies each device: SKIP / RE-IMPORT / FRESH IMPORT
#                  5. Batches eligible devices (up to 500 per API call) and POSTs
#                     to importedWindowsAutopilotDeviceIdentities/import
#                  6. Resolves import IDs by querying staging filtered by serial
#                     and submit time (prevents stale record collision)
#                  7. Polls import status until terminal state or timeout
#                  8. Exports full status CSV and log to script root folder
#
#                CSV INPUT FORMAT:
#                  MANDATORY columns (case-insensitive, any column order):
#                    Device Serial Number  - device serial number
#                    Hardware Hash         - base64 hardware hash string
#                  OPTIONAL columns (taken if present, ignored if absent):
#                    Windows Product ID    - can be empty
#                    Group Tag             - applied during import
#                  Any other columns are silently ignored.
#
#                IMPORT STATUS VALUES (per device in output CSV):
#                  skipped-enrolled   - already present in Autopilot registry
#                  skipped-complete   - staging record exists with status complete
#                  reimport-submitted - was in staging error state, resubmitted
#                  complete           - successfully imported this run
#                  error              - import failed (detail in StatusDetail)
#                  pending            - still processing at poll timeout
#                  SUBMIT FAILED      - API call failed for this device's batch
#
#                OUTPUT CSV COLUMNS:
#                  SourceFile, SerialNumber, WindowsProductID, GroupTag,
#                  Decision, ImportedDeviceID, ImportStatus, StatusDetail,
#                  BatchNumber, SubmittedAt, StatusCheckedAt
#
# Author       : Sethu Kumar B
# Version      : 2.2
# Created Date : 2026-05-04
#
# Requirements :
#   - Azure AD App Registration
#   - Graph API Application Permissions (admin consent granted):
#       DeviceManagementServiceConfig.ReadWrite.All  - Autopilot import + staging read
#       DeviceManagementManagedDevices.Read.All      - Autopilot registry read
#   - PowerShell 5.1 or later
#   - TLS 1.2 enabled
#
# Change Log   :
#   v2.2 - 2026-05-04 - Sethu Kumar B - Full CSV encoding fix. Auto-detects UTF-16
#                        LE/BE and UTF-8 BOM via byte inspection. Handles HP tool
#                        format where each row (header + data) is wrapped as a
#                        single quoted string "col1,col2,col3". Unwraps outer
#                        quotes per-line before ConvertFrom-Csv parsing.
#   v2.1 - 2026-05-04 - Sethu Kumar B - Fixed stray leading quote on header.
#                        quote character before header row. Replaced Import-Csv
#                        with raw ReadAllLines + ConvertFrom-Csv approach. Strips
#                        leading/trailing quotes and whitespace from header line
#                        only before parsing. Fixes "missing required column" error
#                        on CSVs exported by certain HP tools.
#   v2.0 - 2026-05-04 - Sethu Kumar B - Major revision. Merged Check-AutopilotStaging.ps1
#                        into pre-import phase. Added windowsAutopilotDeviceIdentities
#                        registry check. Per-device decision engine: SKIP/RE-IMPORT/FRESH
#                        IMPORT. Column validation now case-insensitive with flexible order.
#                        Optional columns (Group Tag, Windows Product ID) taken if present.
#                        Decision column added to output CSV.
# ==============================================================================


#region --- CONFIGURATION -------------------------------------------------------

$TenantID     = ""
$ClientID     = ""
$ClientSecret = ""

# -- IMPORT FOLDER -------------------------------------------------------------
$ImportFolder = Join-Path $PSScriptRoot "Import"

# -- BATCH SIZE ----------------------------------------------------------------
# Graph API limit is 500 per call.
$BatchSize = 500

# -- POLL SETTINGS -------------------------------------------------------------
$PollIntervalSeconds = 30
$PollTimeoutMinutes  = 30

# -- THROTTLE ------------------------------------------------------------------
$MaxRetries = 5

#endregion ----------------------------------------------------------------------


#region --- INIT ----------------------------------------------------------------

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile     = Join-Path $PSScriptRoot "AutopilotImport_$Timestamp.csv"
$script:LogFile = Join-Path $PSScriptRoot "AutopilotImport_$Timestamp.log"
$TranscriptFile = Join-Path $PSScriptRoot "AutopilotImport_Transcript_$Timestamp.log"

try { Start-Transcript -Path $TranscriptFile -Force | Out-Null } catch { }

try {
    [System.IO.File]::WriteAllText($script:LogFile,
        "Import-AutopilotDevices v2.0`r`nStarted: $(Get-Date)`r`n`r`n",
        [System.Text.Encoding]::UTF8)
} catch { $script:LogFile = $null }

#endregion ----------------------------------------------------------------------


#region --- FUNCTIONS -----------------------------------------------------------

function Write-Log {
    param (
        [Parameter(Mandatory)][AllowEmptyString()][string]$Message,
        [ValidateSet("INFO","SUCCESS","WARN","ERROR","SECTION","BLANK")]
        [string]$Level = "INFO"
    )
    $ColourMap = @{ INFO="Gray"; SUCCESS="Green"; WARN="Yellow"; ERROR="Red"; SECTION="Cyan"; BLANK="Gray" }
    $PrefixMap = @{ INFO="[INFO]   "; SUCCESS="[OK]     "; WARN="[WARN]   "; ERROR="[ERROR]  "; SECTION=""; BLANK="         " }
    $t = Get-Date -Format "HH:mm:ss"
    if     ($Level -eq "BLANK")   { Write-Host "" }
    elseif ($Level -eq "SECTION") { Write-Host "`n$Message" -ForegroundColor Cyan }
    else   { Write-Host "[$t] $($PrefixMap[$Level]) $Message" -ForegroundColor $ColourMap[$Level] }
    if ($script:LogFile) {
        try {
            Add-Content -Path $script:LogFile `
                -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $($PrefixMap[$Level]) $Message" `
                -Encoding UTF8
        } catch { }
    }
}


function Get-GraphToken {
    param ([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    $Body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }
    try {
        Write-Log "Requesting access token..." -Level INFO
        $r = Invoke-RestMethod -Method POST -ContentType "application/x-www-form-urlencoded" `
             -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
             -Body $Body -ErrorAction Stop
        Write-Log "Access token acquired." -Level SUCCESS
        return $r.access_token
    }
    catch { Write-Log "Authentication failed: $_" -Level ERROR; exit 1 }
}


# -----------------------------------------------------------------------------
# Resolve-ColumnName
# Finds a CSV column header by case-insensitive exact match.
# Returns the actual header string as it appears in the CSV, or $null.
# -----------------------------------------------------------------------------
function Resolve-ColumnName {
    param (
        [string[]]$Headers,
        [string]$TargetName
    )
    foreach ($h in $Headers) {
        if ($h.Trim() -ieq $TargetName) { return $h }
    }
    return $null
}


# -----------------------------------------------------------------------------
# Get-PagedGraphResults
# Generic paged GET helper. Returns List[PSObject] of all records across pages.
# -----------------------------------------------------------------------------
function Get-PagedGraphResults {
    param (
        [string]$Uri,
        [string]$AccessToken,
        [string]$ContextLabel = "records"
    )
    $Headers = @{ Authorization = "Bearer $AccessToken"; "Content-Type" = "application/json" }
    $All     = [System.Collections.Generic.List[PSObject]]::new()

    do {
        try {
            $r   = Invoke-RestMethod -Method GET -Uri $Uri -Headers $Headers -ErrorAction Stop
            $Arr = if ($r.PSObject.Properties["value"]) { @($r.value) } else { @($r) }
            foreach ($rec in $Arr) { if ($rec) { $All.Add($rec) } }
            $Uri = if ($r.PSObject.Properties["@odata.nextLink"]) { $r.'@odata.nextLink' } else { $null }
        }
        catch {
            Write-Log "  Page fetch failed ($ContextLabel): $_" -Level WARN
            $Uri = $null
        }
    } while ($Uri)

    return $All
}


# -----------------------------------------------------------------------------
# Get-AutopilotRegisteredDevices
# Queries windowsAutopilotDeviceIdentities (actual Autopilot registry).
# Returns hashtable: serialNumber (lowercase) -> record object.
# -----------------------------------------------------------------------------
function Get-AutopilotRegisteredDevices {
    param ([string]$AccessToken)

    Write-Log "  Querying Autopilot device registry (windowsAutopilotDeviceIdentities)..." -Level INFO
    $Uri     = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities?`$top=1000"
    $Records = Get-PagedGraphResults -Uri $Uri -AccessToken $AccessToken -ContextLabel "Autopilot registry"

    $Lookup = @{}
    foreach ($rec in $Records) {
        if (-not $rec.serialNumber) { continue }
        $Lookup[$rec.serialNumber.ToLower()] = $rec
    }
    Write-Log "  Autopilot registry: $($Lookup.Count) device(s) found." -Level INFO
    return $Lookup
}


# -----------------------------------------------------------------------------
# Get-StagingDevices
# Queries importedWindowsAutopilotDeviceIdentities (staging queue).
# Returns hashtable: serialNumber (lowercase) -> record with highest status priority.
# Priority: complete > error > pending > unknown
# When multiple records exist for same serial, picks by priority then recency.
# -----------------------------------------------------------------------------
function Get-StagingDevices {
    param ([string]$AccessToken)

    Write-Log "  Querying staging endpoint (importedWindowsAutopilotDeviceIdentities)..." -Level INFO
    $Uri     = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities?`$top=1000"
    $Records = Get-PagedGraphResults -Uri $Uri -AccessToken $AccessToken -ContextLabel "staging"

    # Priority map - lower number = higher priority kept
    $Priority = @{ "complete" = 0; "completedWithError" = 1; "error" = 2; "pending" = 3; "unknown" = 4 }

    $Lookup = @{}
    foreach ($rec in $Records) {
        if (-not $rec.serialNumber) { continue }
        $key = $rec.serialNumber.ToLower()

        $Status = "unknown"
        if ($rec.PSObject.Properties["state"] -and $rec.state -and
            $rec.state.PSObject.Properties["deviceImportStatus"]) {
            $Status = [string]$rec.state.deviceImportStatus
        }

        $RecPriority = if ($Priority.ContainsKey($Status)) { $Priority[$Status] } else { 4 }

        if (-not $Lookup.ContainsKey($key)) {
            $Lookup[$key] = @{ Record = $rec; Status = $Status; Priority = $RecPriority }
        }
        else {
            $Existing = $Lookup[$key]
            if ($RecPriority -lt $Existing.Priority) {
                $Lookup[$key] = @{ Record = $rec; Status = $Status; Priority = $RecPriority }
            }
            elseif ($RecPriority -eq $Existing.Priority) {
                # Same priority - keep most recent
                try {
                    $ExistTime = [datetime]::Parse($Existing.Record.createdDateTime)
                    $RecTime   = [datetime]::Parse($rec.createdDateTime)
                    if ($RecTime -gt $ExistTime) {
                        $Lookup[$key] = @{ Record = $rec; Status = $Status; Priority = $RecPriority }
                    }
                } catch { }
            }
        }
    }

    Write-Log "  Staging queue: $($Lookup.Count) unique serial(s) found." -Level INFO
    return $Lookup
}


# -----------------------------------------------------------------------------
# Submit-AutopilotBatch
# POSTs a batch of up to 500 devices to the /import endpoint.
# Returns $true on success. Throws on unrecoverable failure.
# -----------------------------------------------------------------------------
function Submit-AutopilotBatch {
    param (
        [array]$Devices,
        [string]$AccessToken
    )

    $Headers = @{ Authorization = "Bearer $AccessToken"; "Content-Type" = "application/json" }
    $Uri     = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities/import"

    $DeviceArray = [System.Collections.Generic.List[object]]::new()
    foreach ($d in $Devices) {
        $DevObj = [ordered]@{
            serialNumber              = [string]$d.SerialNumber
            hardwareIdentifier        = [string]$d.HardwareHash
            assignedUserPrincipalName = ""
        }
        if (-not [string]::IsNullOrWhiteSpace($d.GroupTag))         { $DevObj["groupTag"]   = [string]$d.GroupTag }
        if (-not [string]::IsNullOrWhiteSpace($d.WindowsProductID)) { $DevObj["productKey"] = [string]$d.WindowsProductID }
        $DeviceArray.Add($DevObj)
    }

    $BodyObject = @{ importedWindowsAutopilotDeviceIdentities = $DeviceArray }
    $Body       = $BodyObject | ConvertTo-Json -Depth 10

    $Attempt = 0
    do {
        $Attempt++
        try {
            $Resp = Invoke-WebRequest -Method POST -Uri $Uri -Headers $Headers `
                    -Body $Body -UseBasicParsing -ErrorAction Stop
            Write-Log "  HTTP $($Resp.StatusCode) - batch accepted by API." -Level INFO
            return $true
        }
        catch {
            $Code = $_.Exception.Response.StatusCode.value__
            $RespBody = ""
            try {
                $ErrStream = $_.Exception.Response.GetResponseStream()
                $Reader    = [System.IO.StreamReader]::new($ErrStream)
                $RespBody  = $Reader.ReadToEnd()
                $Reader.Close()
            } catch { }
            if ($RespBody) { Write-Log "  Response body: $RespBody" -Level ERROR }
            if ($Code -eq 429) {
                $Wait = 60
                try {
                    $HV = $_.Exception.Response.Headers.GetValues("Retry-After")
                    if ($HV -and $HV.Count -gt 0) { $Wait = [int]$HV[0] }
                } catch { }
                $Wait += Get-Random -Minimum 1 -Maximum 10
                if ($Attempt -lt $MaxRetries) {
                    Write-Log "  429 throttled - waiting ${Wait}s (retry $Attempt/$MaxRetries)..." -Level WARN
                    Start-Sleep -Seconds $Wait
                }
                else { throw $_ }
            }
            else { throw $_ }
        }
    } while ($Attempt -lt $MaxRetries)
}


# -----------------------------------------------------------------------------
# Get-ImportedDevicesBySerial
# Queries staging endpoint. Returns hashtable: serialNumber (lowercase) -> record.
# Only includes records created at or after BatchSubmitTime to exclude stale entries.
# When multiple records share same serial, most recently created wins.
# -----------------------------------------------------------------------------
function Get-ImportedDevicesBySerial {
    param (
        [string]$AccessToken,
        [datetime]$BatchSubmitTime
    )

    $Uri = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities?`$top=1000"
    $All = Get-PagedGraphResults -Uri $Uri -AccessToken $AccessToken -ContextLabel "serial lookup"

    $Lookup = @{}
    foreach ($item in $All) {
        if (-not $item.serialNumber) { continue }

        # Filter to records at or after submit time
        if ($item.PSObject.Properties["createdDateTime"] -and $item.createdDateTime) {
            try {
                $RecTime = [datetime]::Parse($item.createdDateTime)
                if ($RecTime -lt $BatchSubmitTime) { continue }
            } catch { }   # parse failure - include
        }

        $key = $item.serialNumber.ToLower()
        if (-not $Lookup.ContainsKey($key)) {
            $Lookup[$key] = $item
        }
        else {
            try {
                $existing = [datetime]::Parse($Lookup[$key].createdDateTime)
                $current  = [datetime]::Parse($item.createdDateTime)
                if ($current -gt $existing) { $Lookup[$key] = $item }
            } catch { }
        }
    }
    return $Lookup
}


# -----------------------------------------------------------------------------
# Get-ImportStatus
# Returns hashtable: id -> staging record. Used during polling.
# -----------------------------------------------------------------------------
function Get-ImportStatus {
    param ([string]$AccessToken)

    $Uri = "https://graph.microsoft.com/beta/deviceManagement/importedWindowsAutopilotDeviceIdentities?`$top=1000"
    $All = Get-PagedGraphResults -Uri $Uri -AccessToken $AccessToken -ContextLabel "status poll"

    $Lookup = @{}
    foreach ($item in $All) {
        if ($item.id) { $Lookup[[string]$item.id] = $item }
    }
    return $Lookup
}


# -----------------------------------------------------------------------------
# Wait-ForImportCompletion
# Polls until all tracked IDs reach terminal state or timeout.
# Returns final status hashtable.
# -----------------------------------------------------------------------------
function Wait-ForImportCompletion {
    param (
        [string[]]$DeviceIDs,
        [string]$AccessToken,
        [int]$PollIntervalSeconds,
        [int]$PollTimeoutMinutes
    )

    $TerminalStates = @("complete", "error", "completedWithError")
    $Deadline       = (Get-Date).AddMinutes($PollTimeoutMinutes)
    $PollCount      = 0

    Write-Log "  Polling for import completion (interval: ${PollIntervalSeconds}s, timeout: ${PollTimeoutMinutes}min)..." -Level INFO

    do {
        $PollCount++
        Start-Sleep -Seconds $PollIntervalSeconds

        $StatusMap = Get-ImportStatus -AccessToken $AccessToken
        $Pending   = 0
        $Complete  = 0
        $Errors    = 0

        foreach ($Id in $DeviceIDs) {
            if ($StatusMap.ContainsKey($Id)) {
                $State = [string]$StatusMap[$Id].state.deviceImportStatus
                if ($TerminalStates -contains $State) {
                    if ($State -eq "complete") { $Complete++ } else { $Errors++ }
                } else { $Pending++ }
            } else { $Pending++ }
        }

        $Elapsed = [math]::Round(((Get-Date) - ($Deadline.AddMinutes(-$PollTimeoutMinutes))).TotalMinutes, 1)
        Write-Log ("  Poll $PollCount | Complete: $Complete  Errors: $Errors  Pending: $Pending | Elapsed: ${Elapsed}min") -Level INFO

        if ($Pending -eq 0) {
            Write-Log "  All devices reached terminal state." -Level SUCCESS
            return $StatusMap
        }

        if ((Get-Date) -ge $Deadline) {
            Write-Log "  Poll timeout reached ($PollTimeoutMinutes min). $Pending device(s) still pending." -Level WARN
            return $StatusMap
        }

    } while ($true)
}

#endregion ----------------------------------------------------------------------


#region --- MAIN ----------------------------------------------------------------

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Import-AutopilotDevices  v2.2  |  Sethu Kumar B              " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Log "" -Level BLANK
Write-Log "Import folder    : $ImportFolder"            -Level INFO
Write-Log "Output CSV       : $OutputFile"              -Level INFO
Write-Log "Log file         : $($script:LogFile)"       -Level INFO
Write-Log "Transcript       : $TranscriptFile"          -Level INFO
Write-Log "Batch size       : $BatchSize"               -Level INFO
Write-Log "Poll interval    : ${PollIntervalSeconds}s"  -Level INFO
Write-Log "Poll timeout     : ${PollTimeoutMinutes}min" -Level INFO
Write-Log "" -Level BLANK


# -- Step 1: Scan Import folder ------------------------------------------------
Write-Log "==========================================================" -Level SECTION
Write-Log "STEP 1 - Scanning Import Folder" -Level INFO
Write-Log "==========================================================" -Level SECTION

if (-not (Test-Path $ImportFolder)) {
    Write-Log "Import folder not found: $ImportFolder" -Level ERROR
    Write-Log "Create an 'Import' subfolder in the script root and place CSV files there." -Level ERROR
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

$CsvFiles = @(Get-ChildItem -Path $ImportFolder -Filter "*.csv" -File | Sort-Object Name)
Write-Log "CSV files found: $($CsvFiles.Count)" -Level $(if ($CsvFiles.Count -gt 0) {"SUCCESS"} else {"WARN"})

if ($CsvFiles.Count -eq 0) {
    Write-Log "No CSV files found in: $ImportFolder" -Level WARN
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}

foreach ($f in $CsvFiles) {
    Write-Log "  -> $($f.Name)  ($([math]::Round($f.Length/1KB, 1)) KB)" -Level INFO
}
Write-Log "" -Level BLANK


# -- Step 2: Validate and load CSVs --------------------------------------------
Write-Log "==========================================================" -Level SECTION
Write-Log "STEP 2 - Validating and Loading CSV Files" -Level INFO
Write-Log "==========================================================" -Level SECTION

$AllDevices  = [System.Collections.Generic.List[PSObject]]::new()
$SkippedFiles = 0

foreach ($File in $CsvFiles) {
    Write-Log "Loading: $($File.Name)" -Level INFO
    try {
        # Robust CSV loader:
        #   - Auto-detects UTF-16 LE/BE BOM and UTF-8 BOM
        #   - Strips whole-row quoting (HP tool wraps each line in "...")
        #   - Handles stray leading quote/whitespace on header row
        #   - Falls back to UTF-8 when no BOM present

        $RawBytes = [System.IO.File]::ReadAllBytes($File.FullName)

        # Detect encoding from BOM
        $Encoding = [System.Text.Encoding]::UTF8  # default
        $BomSkip  = 0
        if ($RawBytes.Count -ge 2 -and $RawBytes[0] -eq 0xFF -and $RawBytes[1] -eq 0xFE) {
            $Encoding = [System.Text.Encoding]::Unicode   # UTF-16 LE
            $BomSkip  = 2
            Write-Log "  Detected encoding: UTF-16 LE" -Level INFO
        }
        elseif ($RawBytes.Count -ge 2 -and $RawBytes[0] -eq 0xFE -and $RawBytes[1] -eq 0xFF) {
            $Encoding = [System.Text.Encoding]::BigEndianUnicode  # UTF-16 BE
            $BomSkip  = 2
            Write-Log "  Detected encoding: UTF-16 BE" -Level INFO
        }
        elseif ($RawBytes.Count -ge 3 -and $RawBytes[0] -eq 0xEF -and $RawBytes[1] -eq 0xBB -and $RawBytes[2] -eq 0xBF) {
            $Encoding = [System.Text.Encoding]::UTF8  # UTF-8 BOM
            $BomSkip  = 3
            Write-Log "  Detected encoding: UTF-8 BOM" -Level INFO
        }

        # Decode full content (skip BOM bytes)
        $Content  = $Encoding.GetString($RawBytes, $BomSkip, $RawBytes.Count - $BomSkip)

        # Split into lines, remove blank lines
        $RawLines = @($Content -split "`r`n|`r|`n" | Where-Object { $_.Trim() -ne "" })

        if ($RawLines.Count -eq 0) {
            Write-Log "  SKIPPED - file is empty." -Level WARN
            $SkippedFiles++
            continue
        }

        # Sanitise each line: if entire line is wrapped in quotes "...", unwrap it.
        # This handles HP export format where each row is quoted as a single string.
        $CleanLines = for ($li = 0; $li -lt $RawLines.Count; $li++) {
            $line = $RawLines[$li].Trim()
            if ($line.StartsWith('"') -and $line.EndsWith('"') -and $line.Length -gt 1) {
                # Unwrap outer quotes - but only if this is a whole-row wrap
                # (i.e. the content itself contains commas, meaning it's not a single quoted field)
                $inner = $line.Substring(1, $line.Length - 2)
                if ($inner -match ',') { $line = $inner }
            }
            $line
        }

        # Rejoin and parse via ConvertFrom-Csv
        $CleanCsv = $CleanLines -join "`n"
        $Data     = @($CleanCsv | ConvertFrom-Csv -ErrorAction Stop)

        if ($Data.Count -eq 0) {
            Write-Log "  SKIPPED - file is empty." -Level WARN
            $SkippedFiles++
            continue
        }

        $Headers = $Data[0].PSObject.Properties.Name

        # Case-insensitive column resolution - mandatory
        $ColSerial = Resolve-ColumnName -Headers $Headers -TargetName "Device Serial Number"
        $ColHash   = Resolve-ColumnName -Headers $Headers -TargetName "Hardware Hash"

        $MissingCols = @()
        if (-not $ColSerial) { $MissingCols += "Device Serial Number" }
        if (-not $ColHash)   { $MissingCols += "Hardware Hash" }

        if ($MissingCols.Count -gt 0) {
            Write-Log "  SKIPPED - missing required column(s): $($MissingCols -join ', ')" -Level ERROR
            Write-Log "  Columns found in file: $($Headers -join ', ')" -Level INFO
            $SkippedFiles++
            continue
        }

        # Optional columns - resolve if present
        $ColProductID = Resolve-ColumnName -Headers $Headers -TargetName "Windows Product ID"
        $ColGroupTag  = Resolve-ColumnName -Headers $Headers -TargetName "Group Tag"

        Write-Log "  Mandatory columns mapped  : Serial='$ColSerial' | Hash='$ColHash'" -Level INFO
        if ($ColProductID) { Write-Log "  Optional column found     : ProductID='$ColProductID'" -Level INFO }
        if ($ColGroupTag)  { Write-Log "  Optional column found     : GroupTag='$ColGroupTag'" -Level INFO }

        $InvalidRows = @($Data | Where-Object {
            [string]::IsNullOrWhiteSpace($_.$ColSerial) -or
            [string]::IsNullOrWhiteSpace($_.$ColHash)
        })
        if ($InvalidRows.Count -gt 0) {
            Write-Log "  WARNING - $($InvalidRows.Count) row(s) have blank serial or hash - skipping those rows." -Level WARN
        }

        $ValidRows = @($Data | Where-Object {
            -not [string]::IsNullOrWhiteSpace($_.$ColSerial) -and
            -not [string]::IsNullOrWhiteSpace($_.$ColHash)
        })

        foreach ($row in $ValidRows) {
            $AllDevices.Add([PSCustomObject]@{
                SourceFile       = $File.Name
                SerialNumber     = ([string]$row.$ColSerial).Trim()
                WindowsProductID = if ($ColProductID) { ([string]$row.$ColProductID).Trim() } else { "" }
                HardwareHash     = ([string]$row.$ColHash).Trim()
                GroupTag         = if ($ColGroupTag)  { ([string]$row.$ColGroupTag).Trim()  } else { "" }
            })
        }

        Write-Log "  Loaded: $($ValidRows.Count) valid device(s)." -Level SUCCESS
    }
    catch {
        Write-Log "  FAILED to load file: $_" -Level ERROR
        $SkippedFiles++
    }
}

Write-Log "" -Level BLANK
Write-Log "Total devices loaded    : $($AllDevices.Count)" -Level $(if ($AllDevices.Count -gt 0) {"SUCCESS"} else {"WARN"})
Write-Log "Files skipped           : $SkippedFiles"        -Level $(if ($SkippedFiles -gt 0) {"WARN"} else {"INFO"})

if ($AllDevices.Count -eq 0) {
    Write-Log "No valid devices to process. Exiting." -Level WARN
    try { Stop-Transcript | Out-Null } catch { }
    exit 0
}
Write-Log "" -Level BLANK


# -- Step 3: Authenticate ------------------------------------------------------
Write-Log "==========================================================" -Level SECTION
Write-Log "STEP 3 - Authenticating" -Level INFO
Write-Log "==========================================================" -Level SECTION
$Token = Get-GraphToken -TenantId $TenantID -ClientId $ClientID -ClientSecret $ClientSecret
Write-Log "" -Level BLANK


# -- Step 4: Pre-import check (staging + Autopilot registry) -------------------
Write-Log "==========================================================" -Level SECTION
Write-Log "STEP 4 - Pre-Import Check (Staging + Autopilot Registry)" -Level INFO
Write-Log "==========================================================" -Level SECTION
Write-Log "Checking both endpoints to classify devices before import..." -Level INFO
Write-Log "" -Level BLANK

$RegisteredDevices = Get-AutopilotRegisteredDevices -AccessToken $Token
Write-Log "" -Level BLANK
$StagingDevices    = Get-StagingDevices -AccessToken $Token
Write-Log "" -Level BLANK

# Classify each device
# Decision values: SKIP-ENROLLED / SKIP-COMPLETE / REIMPORT / IMPORT
$DeviceDecisions = @{}

$CountSkipEnrolled = 0
$CountSkipComplete = 0
$CountReImport     = 0
$CountFreshImport  = 0

Write-Log "--- Device Classification ---" -Level SECTION

foreach ($d in $AllDevices) {
    $snKey   = $d.SerialNumber.ToLower()
    $Decision = ""

    if ($RegisteredDevices.ContainsKey($snKey)) {
        $Decision = "SKIP-ENROLLED"
        $CountSkipEnrolled++
        Write-Log ("  [{0,-12}] {1}  ->  Already present in Autopilot registry. SKIPPED." -f $Decision, $d.SerialNumber) -Level WARN
    }
    elseif ($StagingDevices.ContainsKey($snKey)) {
        $StagingStatus = $StagingDevices[$snKey].Status

        if ($StagingStatus -eq "complete" -or $StagingStatus -eq "completedWithError") {
            $Decision = "SKIP-COMPLETE"
            $CountSkipComplete++
            Write-Log ("  [{0,-12}] {1}  ->  Staging status '{2}'. Already successfully imported. SKIPPED." -f $Decision, $d.SerialNumber, $StagingStatus) -Level WARN
        }
        elseif ($StagingStatus -eq "error") {
            $Decision = "REIMPORT"
            $CountReImport++
            Write-Log ("  [{0,-12}] {1}  ->  Staging status 'error'. Will be RE-IMPORTED." -f $Decision, $d.SerialNumber) -Level INFO
        }
        else {
            # pending / unknown - treat as needs import
            $Decision = "IMPORT"
            $CountFreshImport++
            Write-Log ("  [{0,-12}] {1}  ->  Staging status '{2}'. Will be IMPORTED." -f $Decision, $d.SerialNumber, $StagingStatus) -Level INFO
        }
    }
    else {
        $Decision = "IMPORT"
        $CountFreshImport++
        Write-Log ("  [{0,-12}] {1}  ->  Not found anywhere. FRESH IMPORT." -f $Decision, $d.SerialNumber) -Level SUCCESS
    }

    $DeviceDecisions[$snKey] = $Decision
}

Write-Log "" -Level BLANK
Write-Log "--- Pre-Import Classification Summary ---" -Level SECTION
Write-Log "  Skip (enrolled in Autopilot) : $CountSkipEnrolled" -Level $(if ($CountSkipEnrolled -gt 0) {"WARN"} else {"INFO"})
Write-Log "  Skip (staging complete)      : $CountSkipComplete"  -Level $(if ($CountSkipComplete -gt 0) {"WARN"} else {"INFO"})
Write-Log "  Re-import (staging error)    : $CountReImport"      -Level $(if ($CountReImport     -gt 0) {"INFO"} else {"INFO"})
Write-Log "  Fresh import                 : $CountFreshImport"   -Level $(if ($CountFreshImport  -gt 0) {"SUCCESS"} else {"INFO"})
Write-Log "" -Level BLANK

$EligibleDevices = @($AllDevices | Where-Object {
    $snKey = $_.SerialNumber.ToLower()
    $DeviceDecisions[$snKey] -eq "IMPORT" -or $DeviceDecisions[$snKey] -eq "REIMPORT"
})

if ($EligibleDevices.Count -eq 0) {
    Write-Log "All devices already imported or enrolled. Nothing to submit." -Level SUCCESS

    # Build results for skipped devices and export
    $Results = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($d in $AllDevices) {
        $snKey    = $d.SerialNumber.ToLower()
        $Decision = $DeviceDecisions[$snKey]
        $Results.Add([PSCustomObject]@{
            SourceFile       = $d.SourceFile
            SerialNumber     = $d.SerialNumber
            WindowsProductID = $d.WindowsProductID
            GroupTag         = $d.GroupTag
            Decision         = $Decision
            ImportedDeviceID = "N/A"
            ImportStatus     = $Decision.ToLower()
            StatusDetail     = ""
            BatchNumber      = "N/A"
            SubmittedAt      = "N/A"
            StatusCheckedAt  = "N/A"
        })
    }
    $Results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
    Write-Log "Results exported to: $OutputFile" -Level INFO
    try { Stop-Transcript | Out-Null } catch { }

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  COMPLETE - No devices required import  |  Sethu Kumar B      " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
    exit 0
}

Write-Log "Devices eligible for import/re-import: $($EligibleDevices.Count)" -Level INFO
Write-Log "" -Level BLANK


# -- Step 5: Submit in batches -------------------------------------------------
Write-Log "==========================================================" -Level SECTION
Write-Log "STEP 5 - Submitting Import Batches" -Level INFO
Write-Log "==========================================================" -Level SECTION

$Results        = [System.Collections.Generic.List[PSObject]]::new()
$EligibleList   = $EligibleDevices
$TotalDevices   = $EligibleList.Count
$TotalBatches   = [math]::Ceiling($TotalDevices / $BatchSize)
$BatchNum       = 0
$AllImportedIDs = [System.Collections.Generic.List[string]]::new()

for ($i = 0; $i -lt $TotalDevices; $i += $BatchSize) {
    $BatchNum        = $BatchNum + 1
    $BatchEnd        = [math]::Min($i + $BatchSize - 1, $TotalDevices - 1)
    $Batch           = $EligibleList[$i..$BatchEnd]
    $SubmittedAt     = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $BatchSubmitTime = Get-Date

    Write-Log "Batch $BatchNum of $TotalBatches - submitting $($Batch.Count) device(s)..." -Level INFO

    try {
        $null = Submit-AutopilotBatch -Devices $Batch -AccessToken $Token

        Write-Log "  Waiting 10s for staging records to appear..." -Level INFO
        Start-Sleep -Seconds 10

        $SerialMap = Get-ImportedDevicesBySerial -AccessToken $Token -BatchSubmitTime $BatchSubmitTime

        foreach ($d in $Batch) {
            $snKey    = $d.SerialNumber.ToLower()
            $Decision = $DeviceDecisions[$snKey]
            $RetObj   = if ($SerialMap.ContainsKey($snKey)) { $SerialMap[$snKey] } else { $null }
            $ImportId = if ($RetObj -and $RetObj.id) { [string]$RetObj.id } else { "N/A" }

            if ($ImportId -ne "N/A") { [void]$AllImportedIDs.Add($ImportId) }

            $Results.Add([PSCustomObject]@{
                SourceFile       = $d.SourceFile
                SerialNumber     = $d.SerialNumber
                WindowsProductID = $d.WindowsProductID
                GroupTag         = $d.GroupTag
                Decision         = $Decision
                ImportedDeviceID = $ImportId
                ImportStatus     = if ($ImportId -ne "N/A") { "submitted" } else { "submitted - id not resolved" }
                StatusDetail     = ""
                BatchNumber      = $BatchNum
                SubmittedAt      = $SubmittedAt
                StatusCheckedAt  = "pending"
            })

            Write-Log ("  -> [{0,-8}] {1,-20} | ImportID: {2}" -f $Decision, $d.SerialNumber, $ImportId) -Level INFO
        }
    }
    catch {
        $ErrMsg = [string]$_.Exception.Message
        Write-Log "  Batch $BatchNum FAILED: $ErrMsg" -Level ERROR
        foreach ($d in $Batch) {
            $snKey    = $d.SerialNumber.ToLower()
            $Decision = $DeviceDecisions[$snKey]
            $Results.Add([PSCustomObject]@{
                SourceFile       = $d.SourceFile
                SerialNumber     = $d.SerialNumber
                WindowsProductID = $d.WindowsProductID
                GroupTag         = $d.GroupTag
                Decision         = $Decision
                ImportedDeviceID = "N/A"
                ImportStatus     = "SUBMIT FAILED"
                StatusDetail     = $ErrMsg
                BatchNumber      = $BatchNum
                SubmittedAt      = $SubmittedAt
                StatusCheckedAt  = "N/A"
            })
        }
    }

    if ($BatchNum -lt $TotalBatches) { Start-Sleep -Seconds 3 }
}

# Add skipped devices to results
foreach ($d in $AllDevices) {
    $snKey    = $d.SerialNumber.ToLower()
    $Decision = $DeviceDecisions[$snKey]
    if ($Decision -eq "SKIP-ENROLLED" -or $Decision -eq "SKIP-COMPLETE") {
        $Results.Add([PSCustomObject]@{
            SourceFile       = $d.SourceFile
            SerialNumber     = $d.SerialNumber
            WindowsProductID = $d.WindowsProductID
            GroupTag         = $d.GroupTag
            Decision         = $Decision
            ImportedDeviceID = "N/A"
            ImportStatus     = $Decision.ToLower()
            StatusDetail     = ""
            BatchNumber      = "N/A"
            SubmittedAt      = "N/A"
            StatusCheckedAt  = "N/A"
        })
    }
}

Write-Log "" -Level BLANK
Write-Log "All batches submitted. Total import IDs tracked: $($AllImportedIDs.Count)" -Level INFO


# -- Step 6: Poll for completion status ----------------------------------------
Write-Log "==========================================================" -Level SECTION
Write-Log "STEP 6 - Polling Import Status" -Level INFO
Write-Log "==========================================================" -Level SECTION

if ($AllImportedIDs.Count -eq 0) {
    Write-Log "No import IDs to poll. Skipping." -Level WARN
}
else {
    $FinalStatusMap  = Wait-ForImportCompletion `
        -DeviceIDs $AllImportedIDs.ToArray() `
        -AccessToken $Token `
        -PollIntervalSeconds $PollIntervalSeconds `
        -PollTimeoutMinutes $PollTimeoutMinutes

    $StatusCheckedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    for ($r = 0; $r -lt $Results.Count; $r++) {
        $Row      = $Results[$r]
        $ImportId = $Row.ImportedDeviceID
        if ($ImportId -eq "N/A") { continue }

        if ($FinalStatusMap.ContainsKey($ImportId)) {
            $StatusObj = $FinalStatusMap[$ImportId]
            $DevState  = if ($StatusObj.state -and $StatusObj.state.deviceImportStatus) {
                             [string]$StatusObj.state.deviceImportStatus
                         } else { "unknown" }
            $RegState  = if ($StatusObj.state -and $StatusObj.state.deviceRegistrationId) {
                             [string]$StatusObj.state.deviceRegistrationId
                         } else { "" }
            $ErrorCode = if ($StatusObj.state -and $StatusObj.state.deviceErrorCode) {
                             [string]$StatusObj.state.deviceErrorCode
                         } else { "" }
            $ErrorName = if ($StatusObj.state -and $StatusObj.state.deviceErrorName) {
                             [string]$StatusObj.state.deviceErrorName
                         } else { "" }

            $Detail = ""
            if ($ErrorCode -and $ErrorCode -ne "0") { $Detail  = "ErrorCode: $ErrorCode" }
            if ($ErrorName) { $Detail += if ($Detail) { " | $ErrorName" } else { $ErrorName } }
            if ($RegState)  { $Detail += if ($Detail) { " | RegID: $RegState" } else { "RegID: $RegState" } }

            $Row.ImportStatus    = $DevState
            $Row.StatusDetail    = $Detail
            $Row.StatusCheckedAt = $StatusCheckedAt

            $Level = if ($DevState -eq "complete") { "SUCCESS" } elseif ($DevState -eq "error") { "ERROR" } else { "WARN" }
            Write-Log ("  [{0,-8}] {1,-20} | {2,-20} | {3}" -f $Row.Decision, $Row.SerialNumber, $DevState, $Detail) -Level $Level
        }
        else {
            $Row.ImportStatus    = "pending - not found in status"
            $Row.StatusCheckedAt = $StatusCheckedAt
        }
    }
}
Write-Log "" -Level BLANK


# -- Step 7: Export CSV --------------------------------------------------------
Write-Log "==========================================================" -Level SECTION
Write-Log "STEP 7 - Exporting Results" -Level INFO
Write-Log "==========================================================" -Level SECTION

try {
    $Results | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
    $SizeMB = (((Get-Item $OutputFile).Length) / 1MB).ToString("0.00")
    Write-Log "CSV exported." -Level SUCCESS
    Write-Log "  Path : $OutputFile" -Level INFO
    Write-Log "  Rows : $($Results.Count)  |  Size: $SizeMB MB" -Level INFO
}
catch { Write-Log "CSV export failed: $_" -Level ERROR }


# -- Summary -------------------------------------------------------------------
$CompleteCount      = @($Results | Where-Object { $_.ImportStatus -eq "complete" }).Count
$ErrorCount         = @($Results | Where-Object { $_.ImportStatus -eq "error" -or $_.ImportStatus -like "*FAILED*" }).Count
$PendingCount       = @($Results | Where-Object { $_.ImportStatus -like "pending*" -or $_.ImportStatus -like "submitted*" }).Count
$SkipEnrolledCount  = @($Results | Where-Object { $_.ImportStatus -eq "skip-enrolled" }).Count
$SkipCompleteCount  = @($Results | Where-Object { $_.ImportStatus -eq "skip-complete" }).Count

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  IMPORT COMPLETE  |  Sethu Kumar B                            " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Log "  Files processed            : $($CsvFiles.Count - $SkippedFiles) of $($CsvFiles.Count)" -Level INFO
Write-Log "  Total devices in CSV       : $($AllDevices.Count)"  -Level INFO
Write-Log "  Eligible for import        : $TotalDevices"         -Level INFO
Write-Log "  Batches submitted          : $TotalBatches"         -Level INFO
Write-Log "" -Level BLANK
Write-Log "  SKIP - enrolled in Autopilot : $SkipEnrolledCount" -Level $(if ($SkipEnrolledCount -gt 0) {"WARN"} else {"INFO"})
Write-Log "  SKIP - staging complete      : $SkipCompleteCount" -Level $(if ($SkipCompleteCount -gt 0) {"WARN"} else {"INFO"})
Write-Log "" -Level BLANK
Write-Log "  COMPLETE                     : $CompleteCount"      -Level $(if ($CompleteCount -gt 0) {"SUCCESS"} else {"INFO"})
Write-Log "  ERRORS                       : $ErrorCount"         -Level $(if ($ErrorCount    -gt 0) {"ERROR"}   else {"INFO"})
Write-Log "  PENDING / UNKNOWN            : $PendingCount"       -Level $(if ($PendingCount  -gt 0) {"WARN"}    else {"INFO"})
Write-Log "" -Level BLANK
Write-Log "  Output CSV   : $OutputFile"        -Level INFO
Write-Log "  Log file     : $($script:LogFile)" -Level INFO
Write-Log "  Transcript   : $TranscriptFile"    -Level INFO
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

try { Stop-Transcript | Out-Null } catch { }

#endregion ----------------------------------------------------------------------