#Requires -Version 5.1
<#
.SYNOPSIS
    Extracts full Intune application inventory (Overview + Win32 Program/Detection details) via Graph API.

.DESCRIPTION
    - Authenticates to Microsoft Graph using app registration client credentials.
    - Pulls all mobileApps (paged), filters by platform (All/Windows/Android/iOS/macOS/Web).
    - For each app: pulls full type-cast details + assignments, and for Win32LobApp additionally
      pulls relationships (dependencies/supersedence).
    - Resolves assignment target group IDs to display names via batched directoryObjects/getByIds.
    - Produces two CSV reports:
        1. AppInventory_Overview_<platform>_<timestamp>.csv
        2. AppInventory_ProgramDetails_<platform>_<timestamp>.csv  (Win32/LOB-type properties only -
           other app types will show "N/A" for these columns since Graph has no equivalent data)
    - Writes a full PowerShell transcript alongside the reports.

    KNOWN LIMITATIONS (read before relying on this for compliance reporting):
    - Install command / Uninstall command / Detection rules / Requirement rules are Win32LobApp-only
      properties in Graph. Non-Windows apps (and non-Win32 Windows apps like Store/WinGet apps) will
      not have this data because Graph does not expose it for those types.
    - "App identifier" is populated from whatever identifier field the app type actually exposes
      (bundleId for iOS/macOS, packageId for Android, productCode for MSI). Many app types expose none.
    - Supersedence/Dependency "direction" (this app supersedes X vs is superseded by X) is inferred
      from the relationship's targetType field per Graph's documented behavior at time of writing.
      Spot-check a few known supersedence chains against the Intune portal before trusting this at scale.

.NOTES
    Author  : Sethu Kumar B
    Requires: Azure AD app registration with Application permissions:
              DeviceManagementApps.Read.All, Directory.Read.All (or Group.Read.All)
              Grant admin consent before running.
#>

# ======================================================================================
# CONFIG BLOCK - edit these before running
# ======================================================================================

$TenantID     = ""
$ClientID     = ""
$ClientSecret = ""

# Platform filter: "All", "Windows", "Android", "iOS", "macOS", "Web"
$PlatformFilter = "All"

# Output locations (script-root relative, do not change unless you know why)
$ReportsFolder = Join-Path -Path $PSScriptRoot -ChildPath "Reports"
$LogsFolder    = Join-Path -Path $PSScriptRoot -ChildPath "Logs"

# Graph throttling behavior
$MaxRetryCount   = 5
$RetryDelaySecs  = 5
# ======================================================================================

$ErrorActionPreference = "Stop"
$TimeStamp = Get-Date -Format "yyyyMMdd_HHmmss"

if (-not (Test-Path -Path $ReportsFolder)) { New-Item -Path $ReportsFolder -ItemType Directory -Force | Out-Null }
if (-not (Test-Path -Path $LogsFolder))    { New-Item -Path $LogsFolder -ItemType Directory -Force | Out-Null }

$TranscriptPath = Join-Path -Path $LogsFolder -ChildPath "Transcript_$TimeStamp.log"
Start-Transcript -Path $TranscriptPath -Force | Out-Null

# ======================================================================================
# CONSOLE HELPERS
# ======================================================================================
function Write-Banner {
    param([string]$Text, [string]$Color = "Cyan")
    $line = "=" * 90
    Write-Host ""
    Write-Host $line -ForegroundColor $Color
    Write-Host ("  {0}" -f $Text) -ForegroundColor $Color
    Write-Host $line -ForegroundColor $Color
}

function Write-Step {
    param([string]$Text)
    Write-Host ""
    Write-Host ">> $Text" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Text)
    Write-Host "   $Text" -ForegroundColor Gray
}

function Write-Success {
    param([string]$Text)
    Write-Host "   [OK] $Text" -ForegroundColor Green
}

function Write-WarnMsg {
    param([string]$Text)
    Write-Host "   [WARN] $Text" -ForegroundColor DarkYellow
}

function Write-ErrMsg {
    param([string]$Text)
    Write-Host "   [ERROR] $Text" -ForegroundColor Red
}

# ======================================================================================
# GRAPH AUTH
# ======================================================================================
function Get-GraphAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    $TokenUri = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $Body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
        grant_type    = "client_credentials"
    }
    $Response = Invoke-RestMethod -Uri $TokenUri -Method Post -Body $Body -ContentType "application/x-www-form-urlencoded"
    return $Response.access_token
}

# ======================================================================================
# GRAPH REQUEST WRAPPER (with paging + throttling retry)
# ======================================================================================
function Invoke-GraphGet {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [switch]$SinglePage
    )

    $Results = New-Object System.Collections.Generic.List[object]
    $NextUri = $Uri

    while ($NextUri) {
        $Attempt = 0
        $Success = $false
        $Response = $null

        while (-not $Success -and $Attempt -lt $MaxRetryCount) {
            $Attempt++
            try {
                $Response = Invoke-RestMethod -Uri $NextUri -Headers $Headers -Method Get
                $Success = $true
            }
            catch {
                $StatusCode = $null
                if ($_.Exception.Response) {
                    $StatusCode = [int]$_.Exception.Response.StatusCode
                }
                if ($StatusCode -eq 429 -or $StatusCode -eq 503) {
                    Write-WarnMsg "Throttled (HTTP $StatusCode). Retry $Attempt/$MaxRetryCount after $RetryDelaySecs sec..."
                    Start-Sleep -Seconds $RetryDelaySecs
                }
                else {
                    Write-ErrMsg "Graph request failed: $($_.Exception.Message)"
                    if ($Attempt -ge $MaxRetryCount) { throw }
                    Start-Sleep -Seconds $RetryDelaySecs
                }
            }
        }

        if (-not $Success) {
            throw "Graph request to $NextUri failed after $MaxRetryCount attempts."
        }

        if ($Response.value) {
            foreach ($item in $Response.value) { $Results.Add($item) }
        }
        elseif ($Response) {
            # single object response (not a collection)
            $Results.Add($Response)
        }

        if ($SinglePage) {
            $NextUri = $null
        }
        else {
            $NextUri = $Response.'@odata.nextLink'
        }
    }

    return $Results
}

function Invoke-GraphPost {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [object]$Body
    )
    $JsonBody = $Body | ConvertTo-Json -Depth 10
    return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Post -Body $JsonBody -ContentType "application/json"
}

# ======================================================================================
# APP TYPE / PLATFORM MAPPING
# ======================================================================================
$AppTypeMap = @{
    "#microsoft.graph.win32LobApp"              = @{ Platform = "Windows"; Type = "Win32 app" }
    "#microsoft.graph.windowsMobileMSI"         = @{ Platform = "Windows"; Type = "MSI line-of-business app" }
    "#microsoft.graph.windowsUniversalAppX"     = @{ Platform = "Windows"; Type = "Microsoft Store app (legacy)" }
    "#microsoft.graph.windowsStoreApp"          = @{ Platform = "Windows"; Type = "Microsoft Store app (deprecated)" }
    "#microsoft.graph.winGetApp"                = @{ Platform = "Windows"; Type = "Microsoft Store app (new) / WinGet" }
    "#microsoft.graph.officeSuiteApp"           = @{ Platform = "Windows"; Type = "Microsoft 365 Apps" }
    "#microsoft.graph.windowsAppX"              = @{ Platform = "Windows"; Type = "AppX line-of-business app" }
    "#microsoft.graph.androidStoreApp"          = @{ Platform = "Android"; Type = "Store app" }
    "#microsoft.graph.androidLobApp"            = @{ Platform = "Android"; Type = "Line-of-business app" }
    "#microsoft.graph.androidManagedStoreApp"   = @{ Platform = "Android"; Type = "Managed Google Play app" }
    "#microsoft.graph.androidForWorkApp"        = @{ Platform = "Android"; Type = "Android for Work app" }
    "#microsoft.graph.managedAndroidStoreApp"   = @{ Platform = "Android"; Type = "Managed store app" }
    "#microsoft.graph.iosStoreApp"              = @{ Platform = "iOS/iPadOS"; Type = "Store app" }
    "#microsoft.graph.iosLobApp"                = @{ Platform = "iOS/iPadOS"; Type = "Line-of-business app" }
    "#microsoft.graph.iosVppApp"                = @{ Platform = "iOS/iPadOS"; Type = "VPP app" }
    "#microsoft.graph.managedIOSStoreApp"       = @{ Platform = "iOS/iPadOS"; Type = "Managed store app" }
    "#microsoft.graph.managedIOSLobApp"         = @{ Platform = "iOS/iPadOS"; Type = "Managed line-of-business app" }
    "#microsoft.graph.iosiPadOSWebClip"         = @{ Platform = "iOS/iPadOS"; Type = "Web clip" }
    "#microsoft.graph.macOSLobApp"              = @{ Platform = "macOS"; Type = "Line-of-business app" }
    "#microsoft.graph.macOSDmgApp"              = @{ Platform = "macOS"; Type = "DMG app" }
    "#microsoft.graph.macOSPkgApp"              = @{ Platform = "macOS"; Type = "PKG app" }
    "#microsoft.graph.macOSOfficeSuiteApp"      = @{ Platform = "macOS"; Type = "Microsoft 365 Apps" }
    "#microsoft.graph.macOSMicrosoftDefenderApp" = @{ Platform = "macOS"; Type = "Microsoft Defender" }
    "#microsoft.graph.macOSMicrosoftEdgeApp"    = @{ Platform = "macOS"; Type = "Microsoft Edge" }
    "#microsoft.graph.macOSWebClip"             = @{ Platform = "macOS"; Type = "Web clip" }
    "#microsoft.graph.webApp"                   = @{ Platform = "Web"; Type = "Web link" }
}

function Get-AppPlatformInfo {
    param([string]$ODataType)
    if ($AppTypeMap.ContainsKey($ODataType)) {
        return $AppTypeMap[$ODataType]
    }
    # Unmapped/new type - surface the raw type instead of silently dropping data
    $RawType = $ODataType -replace "#microsoft\.graph\.", ""
    return @{ Platform = "Unknown"; Type = $RawType }
}

function Test-PlatformMatch {
    param([string]$AppPlatform, [string]$FilterValue)
    if ($FilterValue -eq "All") { return $true }
    if ($FilterValue -eq "iOS" -and $AppPlatform -eq "iOS/iPadOS") { return $true }
    return $AppPlatform -eq $FilterValue
}

# ======================================================================================
# FIELD EXTRACTION HELPERS (property names vary by app type)
# ======================================================================================
function Get-FirstNonNullProperty {
    param([object]$InputObject, [string[]]$CandidateNames)
    foreach ($Name in $CandidateNames) {
        if ($InputObject.PSObject.Properties.Name -contains $Name) {
            $Value = $InputObject.$Name
            if ($null -ne $Value -and $Value -ne "") { return $Value }
        }
    }
    return ""
}

function Get-AppVersionValue {
    param([object]$App)
    return Get-FirstNonNullProperty -InputObject $App -CandidateNames @(
        "displayVersion", "versionNumber", "primaryBundleVersion", "versionName",
        "buildNumber", "version", "currentVersion"
    )
}

function Get-AppIdentifierValue {
    param([object]$App)
    return Get-FirstNonNullProperty -InputObject $App -CandidateNames @(
        "bundleId", "packageId", "identityName", "identifier",
        "primaryBundleId", "productCode", "msiProductCode", "appStoreUrl"
    )
}

function Get-AppPublisherValue {
    param([object]$App)
    return Get-FirstNonNullProperty -InputObject $App -CandidateNames @("publisher", "developer")
}

# ======================================================================================
# DETECTION RULE / RELATIONSHIP / ASSIGNMENT FORMATTERS
# ======================================================================================
function Format-DetectionRules {
    param([object[]]$Rules)
    if (-not $Rules -or $Rules.Count -eq 0) { return "N/A" }

    $Parts = @()
    foreach ($Rule in $Rules) {
        $RuleType = $Rule.'@odata.type' -replace "#microsoft\.graph\.", ""
        switch ($RuleType) {
            "win32LobAppRegistryDetection" {
                $Parts += "Registry: $($Rule.keyPath)\$($Rule.valueName) [$($Rule.detectionType) $($Rule.operator) $($Rule.detectionValue)]"
            }
            "win32LobAppFileSystemDetection" {
                $Parts += "File/Folder: $($Rule.path)\$($Rule.fileOrFolderName) [$($Rule.detectionType)]"
            }
            "win32LobAppProductCodeDetection" {
                $Parts += "MSI Product Code: $($Rule.productCode) (version $($Rule.productVersionOperator) $($Rule.productVersion))"
            }
            "win32LobAppPowerShellScriptDetection" {
                $Parts += "PowerShell script detection (runAs32Bit=$($Rule.runAs32Bit), enforceSignatureCheck=$($Rule.enforceSignatureCheck))"
            }
            default {
                $Parts += "$RuleType (unparsed rule type)"
            }
        }
    }
    return ($Parts -join " | ")
}

function Format-Relationships {
    param([object[]]$Relationships, [string]$WantedType)
    # WantedType: "mobileAppDependency" or "mobileAppSupersedence"
    if (-not $Relationships -or $Relationships.Count -eq 0) { return "N/A" }

    $Filtered = $Relationships | Where-Object { $_.'@odata.type' -eq "#microsoft.graph.$WantedType" }
    if (-not $Filtered -or $Filtered.Count -eq 0) { return "N/A" }

    $Parts = @()
    foreach ($Rel in $Filtered) {
        $Direction = if ($Rel.targetType -eq "child") { "-> depends on / supersedes" } else { "<- is required by / superseded by" }
        $Parts += "$($Rel.targetDisplayName) [$Direction, id=$($Rel.targetId)]"
    }
    return ($Parts -join " | ")
}

function Format-Assignments {
    param([object[]]$Assignments, [hashtable]$GroupNameLookup)
    if (-not $Assignments -or $Assignments.Count -eq 0) { return "Not assigned" }

    $Parts = @()
    foreach ($Assignment in $Assignments) {
        $TargetType = $Assignment.target.'@odata.type'
        $Intent = $Assignment.intent

        $TargetLabel = switch ($TargetType) {
            "#microsoft.graph.allDevicesAssignmentTarget"       { "All Devices" }
            "#microsoft.graph.allLicensedUsersAssignmentTarget" { "All Users" }
            "#microsoft.graph.groupAssignmentTarget" {
                $GroupId = $Assignment.target.groupId
                if ($GroupNameLookup.ContainsKey($GroupId)) { $GroupNameLookup[$GroupId] } else { "Group ($GroupId)" }
            }
            "#microsoft.graph.exclusionGroupAssignmentTarget" {
                $GroupId = $Assignment.target.groupId
                $Name = if ($GroupNameLookup.ContainsKey($GroupId)) { $GroupNameLookup[$GroupId] } else { "Group ($GroupId)" }
                "$Name (EXCLUDED)"
            }
            default { "Unknown target ($TargetType)" }
        }

        $Parts += "- $TargetLabel [$Intent]"
    }
    # One entry per line (not comma/pipe joined) so multi-group assignments are readable in the cell.
    # Excel/CSV will preserve this as a wrapped multi-line cell since the field gets quoted.
    return ($Parts -join "`n")
}

function Test-IsAssigned {
    param([object[]]$Assignments)
    if (-not $Assignments -or $Assignments.Count -eq 0) { return "No" }
    return "Yes"
}

# ======================================================================================
# GROUP NAME RESOLUTION (batched)
# ======================================================================================
function Resolve-GroupNames {
    param([string[]]$GroupIds, [hashtable]$Headers)

    $Lookup = @{}
    $UniqueIds = $GroupIds | Where-Object { $_ } | Select-Object -Unique
    if ($UniqueIds.Count -eq 0) { return $Lookup }

    $BatchSize = 900
    $BatchCount = [Math]::Ceiling($UniqueIds.Count / $BatchSize)

    for ($i = 0; $i -lt $BatchCount; $i++) {
        $Batch = $UniqueIds | Select-Object -Skip ($i * $BatchSize) -First $BatchSize
        $Body = @{
            ids   = @($Batch)
            types = @("group")
        }
        try {
            $Response = Invoke-GraphPost -Uri "https://graph.microsoft.com/v1.0/directoryObjects/getByIds" -Headers $Headers -Body $Body
            foreach ($Obj in $Response.value) {
                $Lookup[$Obj.id] = $Obj.displayName
            }
        }
        catch {
            Write-WarnMsg "Group name batch resolution failed for batch $($i + 1): $($_.Exception.Message)"
        }
    }

    return $Lookup
}

# ======================================================================================
# MAIN
# ======================================================================================
Write-Banner "INTUNE APPLICATION INVENTORY REPORT" "Cyan"
Write-Info "Author  : Sethu Kumar B"
Write-Info "Platform filter : $PlatformFilter"
Write-Info "Started : $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"

try {
    # --- Auth ---
    Write-Step "Authenticating to Microsoft Graph"
    $AccessToken = Get-GraphAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    $Headers = @{ Authorization = "Bearer $AccessToken" }
    Write-Success "Token acquired"

    # --- Lightweight app list (id, displayName, odata.type only) ---
    Write-Step "Pulling app list from Graph"
    $ListUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps?`$select=id,displayName"
    $AppStubs = Invoke-GraphGet -Uri $ListUri -Headers $Headers
    Write-Success "Retrieved $($AppStubs.Count) apps (all types, before platform filter)"

    # --- Filter by platform using odata.type ---
    Write-Step "Applying platform filter: $PlatformFilter"
    $FilteredStubs = New-Object System.Collections.Generic.List[object]
    foreach ($Stub in $AppStubs) {
        $Info = Get-AppPlatformInfo -ODataType $Stub.'@odata.type'
        if (Test-PlatformMatch -AppPlatform $Info.Platform -FilterValue $PlatformFilter) {
            $FilteredStubs.Add($Stub)
        }
    }
    Write-Success "$($FilteredStubs.Count) apps match filter '$PlatformFilter'"

    if ($FilteredStubs.Count -eq 0) {
        Write-WarnMsg "No apps matched the platform filter. Exiting."
        Stop-Transcript | Out-Null
        return
    }

    # --- Pull full details per app ---
    Write-Step "Pulling full app details, assignments, and relationships"
    $FullApps = New-Object System.Collections.Generic.List[object]
    $Counter = 0
    foreach ($Stub in $FilteredStubs) {
        $Counter++
        Write-Progress -Activity "Pulling app details" -Status "$Counter / $($FilteredStubs.Count) : $($Stub.displayName)" `
            -PercentComplete (($Counter / $FilteredStubs.Count) * 100)

        $DetailUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$($Stub.id)')?`$expand=assignments,categories"
        $Detail = (Invoke-GraphGet -Uri $DetailUri -Headers $Headers -SinglePage)[0]

        $Info = Get-AppPlatformInfo -ODataType $Detail.'@odata.type'

        $Relationships = $null
        if ($Info.Type -eq "Win32 app") {
            $RelUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps('$($Stub.id)')/relationships"
            try {
                $Relationships = Invoke-GraphGet -Uri $RelUri -Headers $Headers
            }
            catch {
                Write-WarnMsg "Could not pull relationships for '$($Stub.displayName)': $($_.Exception.Message)"
            }
        }

        $FullApps.Add([pscustomobject]@{
            Detail        = $Detail
            Platform      = $Info.Platform
            TypeLabel     = $Info.Type
            Relationships = $Relationships
        })
    }
    Write-Progress -Activity "Pulling app details" -Completed
    Write-Success "Pulled full details for $($FullApps.Count) apps"

    # --- Collect group IDs across all assignments ---
    Write-Step "Collecting assignment group IDs for name resolution"
    $AllGroupIds = New-Object System.Collections.Generic.List[string]
    foreach ($AppWrap in $FullApps) {
        foreach ($Assignment in $AppWrap.Detail.assignments) {
            if ($Assignment.target.groupId) { $AllGroupIds.Add($Assignment.target.groupId) }
        }
    }
    Write-Info "$($AllGroupIds.Count) group references found ($(($AllGroupIds | Select-Object -Unique).Count) unique)"

    Write-Step "Resolving group display names"
    $GroupNameLookup = Resolve-GroupNames -GroupIds $AllGroupIds -Headers $Headers
    Write-Success "Resolved $($GroupNameLookup.Count) group names"

    # --- Build single merged row per app (no duplicate columns) ---
    Write-Step "Building merged report rows"
    $Rows = New-Object System.Collections.Generic.List[object]
    foreach ($AppWrap in $FullApps) {
        $App = $AppWrap.Detail
        $IsWin32 = $AppWrap.TypeLabel -eq "Win32 app"
        $AssignmentsFormatted = Format-Assignments -Assignments $App.assignments -GroupNameLookup $GroupNameLookup
        $NA = "N/A - not applicable to this app type"

        $Rows.Add([pscustomobject]@{
            Name                         = $App.displayName
            Platform                     = $AppWrap.Platform
            Type                         = $AppWrap.TypeLabel
            Publisher                    = Get-AppPublisherValue -App $App
            Version                      = Get-AppVersionValue -App $App
            "App identifier"             = Get-AppIdentifierValue -App $App
            Assigned                     = Test-IsAssigned -Assignments $App.assignments
            Assignments                  = $AssignmentsFormatted
            "Date added"                 = $App.createdDateTime
            "Last edited"                = $App.lastModifiedDateTime
            Description                  = $App.description
            "Featured in Company Portal" = $App.isFeatured
            "More information url"       = $App.informationUrl
            Notes                        = $App.notes
            "Install command"            = if ($IsWin32) { $App.installCommandLine } else { $NA }
            "Uninstall command"          = if ($IsWin32) { $App.uninstallCommandLine } else { $NA }
            "Detection rules"            = if ($IsWin32) { Format-DetectionRules -Rules $App.detectionRules } else { $NA }
            Dependencies                 = if ($IsWin32) { Format-Relationships -Relationships $AppWrap.Relationships -WantedType "mobileAppDependency" } else { $NA }
            Supersedence                 = if ($IsWin32) { Format-Relationships -Relationships $AppWrap.Relationships -WantedType "mobileAppSupersedence" } else { $NA }
            "Content version"            = if ($IsWin32) { $App.committedContentVersion } else { $NA }
            "Install file name"          = if ($IsWin32) { $App.fileName } else { $NA }
            "Install file size (MB)"     = if ($IsWin32 -and $App.size) { [Math]::Round($App.size / 1MB, 2) } else { $NA }
            "Setup file path"            = if ($IsWin32) { $App.setupFilePath } else { $NA }
            "Minimum Windows release"    = if ($IsWin32) { $App.minimumSupportedWindowsRelease } else { $NA }
            "Allow available uninstall"  = if ($IsWin32) { $App.allowAvailableUninstall } else { $NA }
        })
    }

    # --- Export ---
    Write-Step "Exporting report"
    $ReportPath = Join-Path -Path $ReportsFolder -ChildPath "AppInventory_$($PlatformFilter)_$TimeStamp.csv"
    $Rows | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
    Write-Success "Report : $ReportPath"

    Write-Banner "RUN SUMMARY" "Green"
    Write-Host ("   Apps processed  : {0}" -f $FullApps.Count) -ForegroundColor White
    Write-Host ("   Platform filter : {0}" -f $PlatformFilter) -ForegroundColor White
    Write-Host ("   Groups resolved : {0}" -f $GroupNameLookup.Count) -ForegroundColor White
    Write-Host ("   Report CSV      : {0}" -f $ReportPath) -ForegroundColor White
    Write-Host ("   Transcript log  : {0}" -f $TranscriptPath) -ForegroundColor White
    Write-Host ("   Completed       : {0}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')) -ForegroundColor White
    Write-Host ""
}
catch {
    Write-ErrMsg "Script failed: $($_.Exception.Message)"
    Write-ErrMsg $_.ScriptStackTrace
}
finally {
    Stop-Transcript | Out-Null
}
