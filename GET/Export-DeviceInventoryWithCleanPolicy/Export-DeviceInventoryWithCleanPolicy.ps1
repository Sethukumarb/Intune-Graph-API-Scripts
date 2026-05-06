# ============================================================
# Script  : Export-DeviceInventoryWithCleanPolicy.ps1
# Version : 1.2
# Author  : Sethu Kumar B
# Purpose : Export Windows-only Intune, Azure AD, and Autopilot
#           devices to a multi-sheet Excel workbook with sync
#           verdict and clean policy recommendation based on
#           inactivity thresholds (90/120/180 days).
# Output  : AllDeviceInventory_<timestamp>.xlsx in $PSScriptRoot
# ============================================================

#region ── CONFIG ──────────────────────────────────────────────

$TenantID     = ""
$ClientID     = ""
$ClientSecret = ""

# Sync thresholds (days)
$WarnDays     = 14   # Amber : stale but not critical
$CriticalDays = 30   # Red   : critically stale

# Clean Policy thresholds (days since last sync/contact)
$CleanWarn1   = 90   # Yellow : Review Required
$CleanWarn2   = 120  # Orange : Pending Deletion
$CleanDelete  = 180  # Red    : Can Be Deleted (Clean Policy)

# Output
$Timestamp  = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile = Join-Path $PSScriptRoot "AllDeviceInventory_$Timestamp.xlsx"
$LogFile    = Join-Path $PSScriptRoot "AllDeviceInventory_$Timestamp.log"
#endregion

#region ── PROGRESS + LOGGING ──────────────────────────────────
$Script:StepIndex  = 0
$Script:TotalSteps = 10   # Auth + 3 fetches + 3 builds + module check + Excel write + done

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $Entry = "[{0}] [{1}] {2}" -f (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), $Level, $Message
    Add-Content -Path $LogFile -Value $Entry
    switch ($Level) {
        "ERROR"   { Write-Host $Entry -ForegroundColor Red }
        "WARN"    { Write-Host $Entry -ForegroundColor Yellow }
        "SUCCESS" { Write-Host $Entry -ForegroundColor Green }
        default   { Write-Host $Entry -ForegroundColor Cyan }
    }
}

function Write-Step {
    param([string]$StepName, [string]$Detail = "")
    $Script:StepIndex++
    $Pct = [int](($Script:StepIndex / $Script:TotalSteps) * 100)
    Write-Progress -Id 1 -Activity "Get-AllDeviceInventory v1.2" `
        -Status "Step $($Script:StepIndex)/$($Script:TotalSteps) — $StepName" `
        -PercentComplete $Pct
    $Sep = "─" * 62
    Write-Host ""
    Write-Host $Sep -ForegroundColor DarkGray
    Write-Host ("  [{0}/{1}]  {2}" -f $Script:StepIndex, $Script:TotalSteps, $StepName) -ForegroundColor White
    if ($Detail) { Write-Host "         $Detail" -ForegroundColor DarkGray }
    Write-Host $Sep -ForegroundColor DarkGray
    Write-Log ("STEP {0}/{1} — {2}{3}" -f $Script:StepIndex, $Script:TotalSteps, $StepName, $(if ($Detail) { " | $Detail" } else { "" }))
}

function Write-SubProgress {
    param([string]$Label, [int]$Current, [int]$Total)
    $Pct = if ($Total -gt 0) { [int](($Current / $Total) * 100) } else { 50 }
    Write-Progress -Id 2 -ParentId 1 -Activity " " -Status "  $Label" -PercentComplete $Pct
    Write-Host "    >> $Label" -ForegroundColor DarkGray
}

function Complete-SubProgress {
    Write-Progress -Id 2 -Activity " " -Completed
}
#endregion

#region ── AUTH ────────────────────────────────────────────────
function Get-GraphToken {
    Write-Step "Authenticating to Microsoft Graph API" "Tenant: $TenantId"
    $Body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }
    try {
        $Response = Invoke-RestMethod -Method POST `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Body $Body -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        Write-Log "Token acquired successfully." -Level "SUCCESS"
        return $Response.access_token
    } catch {
        Write-Log "Token acquisition failed: $_" -Level "ERROR"
        throw
    }
}
#endregion

#region ── GRAPH PAGED FETCH ───────────────────────────────────
function Get-GraphAllPages {
    param([string]$Uri, [string]$Token, [string]$SourceLabel)
    $Headers = @{ Authorization = "Bearer $Token"; ConsistencyLevel = "eventual" }
    $Results = [System.Collections.Generic.List[object]]::new()
    $NextUri = $Uri
    $Page    = 0
    do {
        $Page++
        Write-SubProgress -Label "[$SourceLabel] Page $Page — $($Results.Count) records so far..." `
            -Current $Results.Count -Total ($Results.Count + 100)
        try {
            $Response = Invoke-RestMethod -Uri $NextUri -Headers $Headers -Method GET -ErrorAction Stop
            if ($Response.value) { $Results.AddRange($Response.value) }
            $NextUri = $Response.'@odata.nextLink'
            Write-Host ("    >> Page {0} done — {1} records this page | Running total: {2}" -f `
                $Page, $Response.value.Count, $Results.Count) -ForegroundColor DarkGray
            Write-Log "[$SourceLabel] Page $Page — $($Response.value.Count) records | Total so far: $($Results.Count)"
        } catch {
            Write-Log "[$SourceLabel] Graph fetch error on page $Page [$NextUri]: $_" -Level "ERROR"
            break
        }
    } while ($NextUri)
    Complete-SubProgress
    return $Results
}
#endregion

#region ── SYNC VERDICT ────────────────────────────────────────
function Get-SyncVerdict {
    param([object]$LastSyncDate)
    if ($null -eq $LastSyncDate -or [string]::IsNullOrWhiteSpace([string]$LastSyncDate)) {
        return @{
            Days             = "N/A"
            Verdict          = "Never Synced"
            VerdictColor     = "Critical"
            CleanPolicy      = "Review Required — No sync date on record"
            CleanPolicyColor = "CleanWarn1"
        }
    }
    try {
        $Parsed = [datetime]::Parse([string]$LastSyncDate)
        $Days   = [int]([datetime]::UtcNow - $Parsed.ToUniversalTime()).TotalDays

        $Verdict      = if ($Days -le $WarnDays)         { "Healthy (${Days}d ago)" }
                        elseif ($Days -le $CriticalDays)  { "Stale (${Days}d ago)" }
                        else                              { "Critical (${Days}d ago)" }

        $VerdictColor = if ($Days -le $WarnDays)         { "Healthy" }
                        elseif ($Days -le $CriticalDays)  { "Warning" }
                        else                              { "Critical" }

        $CleanPolicy      = if ($Days -ge $CleanDelete)   { "Can Be Deleted — Not reported >180d (Clean Policy)" }
                            elseif ($Days -ge $CleanWarn2) { "Pending Deletion — Not reported >120d" }
                            elseif ($Days -ge $CleanWarn1) { "Review Required — Not reported >90d" }
                            else                           { "Active" }

        $CleanPolicyColor = if ($Days -ge $CleanDelete)   { "CleanDelete" }
                            elseif ($Days -ge $CleanWarn2) { "CleanWarn2" }
                            elseif ($Days -ge $CleanWarn1) { "CleanWarn1" }
                            else                           { "Active" }

        return @{
            Days             = $Days
            Verdict          = $Verdict
            VerdictColor     = $VerdictColor
            CleanPolicy      = $CleanPolicy
            CleanPolicyColor = $CleanPolicyColor
        }
    } catch {
        return @{
            Days             = "ERR"
            Verdict          = "Parse Error"
            VerdictColor     = "Warning"
            CleanPolicy      = "Parse Error"
            CleanPolicyColor = "CleanWarn1"
        }
    }
}
#endregion

#region ── DATA FETCH (Windows only) ───────────────────────────
function Get-IntuneDevices {
    param([string]$Token)
    Write-Step "Fetching Intune Managed Devices (Windows)" `
        "Filter: operatingSystem eq 'Windows' | /beta/deviceManagement/managedDevices"
    $Uri     = "https://graph.microsoft.com/beta/deviceManagement/managedDevices?`$filter=operatingSystem eq 'Windows'"
    $Devices = Get-GraphAllPages -Uri $Uri -Token $Token -SourceLabel "Intune"
    Write-Log "Intune fetch complete — $($Devices.Count) Windows devices." -Level "SUCCESS"
    return $Devices
}

function Get-AzureADDevices {
    param([string]$Token)
    Write-Step "Fetching Azure AD / Entra ID Devices (Windows)" `
        "Filter: operatingSystem eq 'Windows' | /beta/devices"
    $Uri     = "https://graph.microsoft.com/beta/devices?`$filter=operatingSystem eq 'Windows'&`$top=999"
    $Devices = Get-GraphAllPages -Uri $Uri -Token $Token -SourceLabel "Azure AD"
    Write-Log "Azure AD fetch complete — $($Devices.Count) Windows devices." -Level "SUCCESS"
    return $Devices
}

function Get-AutopilotDevices {
    param([string]$Token)
    Write-Step "Fetching Windows Autopilot Devices" `
        "No OS filter needed — Autopilot is Windows-only by design | /beta/windowsAutopilotDeviceIdentities"
    $Uri     = "https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities"
    $Devices = Get-GraphAllPages -Uri $Uri -Token $Token -SourceLabel "Autopilot"
    Write-Log "Autopilot fetch complete — $($Devices.Count) devices." -Level "SUCCESS"
    return $Devices
}
#endregion

#region ── TRANSFORM ───────────────────────────────────────────
function Build-IntuneRows {
    param($Devices)
    Write-Step "Building Intune dataset" "$($Devices.Count) Windows devices — calculating sync + clean policy verdicts"
    $Rows  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Total = $Devices.Count
    $i     = 0
    foreach ($D in $Devices) {
        $i++
        if ($i % 100 -eq 0 -or $i -eq $Total) {
            Write-SubProgress -Label "Intune — $i / $Total devices processed" -Current $i -Total $Total
        }
        $Sync = Get-SyncVerdict -LastSyncDate $D.lastSyncDateTime
        $Rows.Add([PSCustomObject]@{
            Source                    = "Intune"
            DeviceName                = [string]$D.deviceName
            IntuneDeviceId            = [string]$D.id
            AzureADDeviceId           = [string]$D.azureADDeviceId
            SerialNumber              = [string]$D.serialNumber
            OperatingSystem           = [string]$D.operatingSystem
            OSVersion                 = [string]$D.osVersion
            Model                     = [string]$D.model
            Manufacturer              = [string]$D.manufacturer
            UserPrincipalName         = [string]$D.userPrincipalName
            UserDisplayName           = [string]$D.userDisplayName
            EnrolledDateTime          = [string]$D.enrolledDateTime
            LastSyncDateTime          = [string]$D.lastSyncDateTime
            DaysSinceLastSync         = $Sync.Days
            SyncVerdict               = $Sync.Verdict
            SyncVerdictColor          = $Sync.VerdictColor
            CleanPolicyRecommendation = $Sync.CleanPolicy
            CleanPolicyColor          = $Sync.CleanPolicyColor
            ComplianceState           = [string]$D.complianceState
            ManagementState           = [string]$D.managementState
            JoinType                  = [string]$D.joinType
            DeviceRegistrationState   = [string]$D.deviceRegistrationState
            IsEncrypted               = [string]$D.isEncrypted
            IsSupervised              = [string]$D.isSupervised
            ManagedDeviceOwnerType    = [string]$D.managedDeviceOwnerType
        })
    }
    Complete-SubProgress
    Write-Log "Intune rows built: $($Rows.Count)" -Level "SUCCESS"
    return $Rows
}

function Build-AzureADRows {
    param($Devices)
    Write-Step "Building Azure AD dataset" "$($Devices.Count) Windows devices — calculating sync + clean policy verdicts"
    $Rows  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Total = $Devices.Count
    $i     = 0
    foreach ($D in $Devices) {
        $i++
        if ($i % 100 -eq 0 -or $i -eq $Total) {
            Write-SubProgress -Label "Azure AD — $i / $Total devices processed" -Current $i -Total $Total
        }
        $Sync = Get-SyncVerdict -LastSyncDate $D.approximateLastSignInDateTime
        $Rows.Add([PSCustomObject]@{
            Source                     = "Azure AD"
            DisplayName                = [string]$D.displayName
            AzureADObjectId            = [string]$D.id
            AzureADDeviceId            = [string]$D.deviceId
            OperatingSystem            = [string]$D.operatingSystem
            OSVersion                  = [string]$D.operatingSystemVersion
            TrustType                  = [string]$D.trustType
            JoinType                   = [string]$D.deviceCategory
            IsCompliant                = [string]$D.isCompliant
            IsManaged                  = [string]$D.isManaged
            ProfileType                = [string]$D.profileType
            RegisteredDateTime         = [string]$D.registrationDateTime
            ApproximateLastSignIn      = [string]$D.approximateLastSignInDateTime
            DaysSinceLastSignIn        = $Sync.Days
            SyncVerdict                = $Sync.Verdict
            SyncVerdictColor           = $Sync.VerdictColor
            CleanPolicyRecommendation  = $Sync.CleanPolicy
            CleanPolicyColor           = $Sync.CleanPolicyColor
            AccountEnabled             = [string]$D.accountEnabled
            MDMAppId                   = [string]$D.mdmAppId
            DeviceOwnership            = [string]$D.deviceOwnership
            EnrollmentType             = [string]$D.enrollmentType
            ManagementType             = [string]$D.managementType
            OnPremisesSyncEnabled      = [string]$D.onPremisesSyncEnabled
            OnPremisesLastSyncDateTime = [string]$D.onPremisesLastSyncDateTime
        })
    }
    Complete-SubProgress
    Write-Log "Azure AD rows built: $($Rows.Count)" -Level "SUCCESS"
    return $Rows
}

function Build-AutopilotRows {
    param($Devices)
    Write-Step "Building Autopilot dataset" "$($Devices.Count) devices — calculating sync + clean policy verdicts"
    $Rows  = [System.Collections.Generic.List[PSCustomObject]]::new()
    $Total = $Devices.Count
    $i     = 0
    foreach ($D in $Devices) {
        $i++
        if ($i % 100 -eq 0 -or $i -eq $Total) {
            Write-SubProgress -Label "Autopilot — $i / $Total devices processed" -Current $i -Total $Total
        }
        $Sync = Get-SyncVerdict -LastSyncDate $D.lastContactedDateTime
        $Rows.Add([PSCustomObject]@{
            Source                    = "Autopilot"
            SerialNumber              = [string]$D.serialNumber
            AutopilotDeviceId         = [string]$D.id
            ManagedDeviceId           = [string]$D.managedDeviceId
            AzureADDeviceId           = [string]$D.azureActiveDirectoryDeviceId
            Model                     = [string]$D.model
            Manufacturer              = [string]$D.manufacturer
            GroupTag                  = [string]$D.groupTag
            PurchaseOrderIdentifier   = [string]$D.purchaseOrderIdentifier
            ProductKey                = [string]$D.productKey
            AddressableUserName       = [string]$D.addressableUserName
            UserPrincipalName         = [string]$D.userPrincipalName
            EnrollmentState           = [string]$D.enrollmentState
            LastContactedDateTime     = [string]$D.lastContactedDateTime
            DaysSinceLastContact      = $Sync.Days
            SyncVerdict               = $Sync.Verdict
            SyncVerdictColor          = $Sync.VerdictColor
            CleanPolicyRecommendation = $Sync.CleanPolicy
            CleanPolicyColor          = $Sync.CleanPolicyColor
            ProfileAssignmentStatus   = [string]$D.deploymentProfileAssignmentStatus
            ProfileAssignedDateTime   = [string]$D.deploymentProfileAssignedDateTime
            RemediationState          = [string]$D.remediationState
        })
    }
    Complete-SubProgress
    Write-Log "Autopilot rows built: $($Rows.Count)" -Level "SUCCESS"
    return $Rows
}
#endregion

#region ── EXCEL EXPORT ────────────────────────────────────────
function Export-ToExcel {
    param(
        [System.Collections.Generic.List[PSCustomObject]]$IntuneRows,
        [System.Collections.Generic.List[PSCustomObject]]$AzureRows,
        [System.Collections.Generic.List[PSCustomObject]]$AutopilotRows
    )

    Write-Step "Checking / Installing ImportExcel module"
    if (-not (Get-Module -ListAvailable -Name ImportExcel)) {
        Write-Log "ImportExcel not found — installing..." -Level "WARN"
        try {
            Install-Module -Name ImportExcel -Scope CurrentUser -Force -ErrorAction Stop
            Write-Log "ImportExcel installed successfully." -Level "SUCCESS"
        } catch {
            Write-Log "ImportExcel install failed: $_" -Level "ERROR"
            Write-Log "Falling back to CSV export..." -Level "WARN"
            Export-ToCsv -IntuneRows $IntuneRows -AzureRows $AzureRows -AutopilotRows $AutopilotRows
            return
        }
    } else {
        Write-Log "ImportExcel module available." -Level "SUCCESS"
    }
    Import-Module ImportExcel -ErrorAction Stop

    $ColorMap = @{
        Healthy     = "92D050"   # Green
        Warning     = "FFD966"   # Amber
        Critical    = "FF6B6B"   # Soft red
        Header      = "1F3864"   # Dark navy
        CleanWarn1  = "FFF2CC"   # Light yellow  >90d
        CleanWarn2  = "F4B942"   # Orange        >120d
        CleanDelete = "C00000"   # Dark red       >180d
    }

    function Write-Sheet {
        param($SheetName, $Rows)
        if ($Rows.Count -eq 0) {
            Write-Log "[$SheetName] No data — sheet skipped." -Level "WARN"
            return
        }
        Write-SubProgress -Label "Writing: $SheetName ($($Rows.Count) rows)..." -Current 1 -Total 1

        $WB = $Rows | Export-Excel -Path $OutputFile -WorksheetName $SheetName `
            -AutoSize -AutoFilter -BoldTopRow -FreezeTopRow -PassThru

        $WS   = $WB.Workbook.Worksheets[$SheetName]
        $Fill = [OfficeOpenXml.Style.ExcelFillStyle]::Solid

        # Header row
        for ($Col = 1; $Col -le $WS.Dimension.Columns; $Col++) {
            $WS.Cells[1, $Col].Style.Fill.PatternType = $Fill
            $WS.Cells[1, $Col].Style.Fill.BackgroundColor.SetColor(
                [System.Drawing.ColorTranslator]::FromHtml("#$($ColorMap.Header)"))
            $WS.Cells[1, $Col].Style.Font.Color.SetColor([System.Drawing.Color]::White)
            $WS.Cells[1, $Col].Style.Font.Bold = $true
            $WS.Cells[1, $Col].Style.HorizontalAlignment = [OfficeOpenXml.Style.ExcelHorizontalAlignment]::Center
        }

        # Locate hidden driver columns
        $SyncColorCol = $null; $CleanColorCol = $null
        for ($Col = 1; $Col -le $WS.Dimension.Columns; $Col++) {
            switch ($WS.Cells[1, $Col].Text) {
                "SyncVerdictColor" { $SyncColorCol  = $Col }
                "CleanPolicyColor" { $CleanColorCol = $Col }
            }
        }

        # Row colouring — CleanPolicy takes priority over SyncVerdict
        for ($Row = 2; $Row -le $WS.Dimension.Rows; $Row++) {
            $SyncColor  = if ($SyncColorCol)  { $WS.Cells[$Row, $SyncColorCol].Text  } else { "Healthy" }
            $CleanColor = if ($CleanColorCol) { $WS.Cells[$Row, $CleanColorCol].Text } else { "Active" }

            $BgHex = switch ($CleanColor) {
                "CleanDelete" { $ColorMap.CleanDelete }
                "CleanWarn2"  { $ColorMap.CleanWarn2 }
                "CleanWarn1"  { $ColorMap.CleanWarn1 }
                default {
                    switch ($SyncColor) {
                        "Critical" { $ColorMap.Critical }
                        "Warning"  { $ColorMap.Warning }
                        default    { "FFFFFF" }
                    }
                }
            }
            $FontWhite = ($CleanColor -eq "CleanDelete")

            for ($Col = 1; $Col -le $WS.Dimension.Columns; $Col++) {
                if ($Col -ne $SyncColorCol -and $Col -ne $CleanColorCol) {
                    $WS.Cells[$Row, $Col].Style.Fill.PatternType = $Fill
                    $WS.Cells[$Row, $Col].Style.Fill.BackgroundColor.SetColor(
                        [System.Drawing.ColorTranslator]::FromHtml("#$BgHex"))
                    if ($FontWhite) {
                        $WS.Cells[$Row, $Col].Style.Font.Color.SetColor([System.Drawing.Color]::White)
                    }
                }
            }
        }

        if ($SyncColorCol)  { $WS.Column($SyncColorCol).Hidden  = $true }
        if ($CleanColorCol) { $WS.Column($CleanColorCol).Hidden = $true }

        Close-ExcelPackage $WB
        Write-Log "[$SheetName] Written — $($Rows.Count) rows." -Level "SUCCESS"
    }

    Write-Step "Writing Excel workbook" $OutputFile

    # ── Summary Sheet ──
    Write-SubProgress -Label "Writing Summary sheet..." -Current 0 -Total 4
    $SummaryData = @(
        [PSCustomObject]@{
            Source             = "Intune (Windows)"
            TotalDevices       = $IntuneRows.Count
            Healthy            = ($IntuneRows    | Where-Object SyncVerdictColor -eq "Healthy").Count
            Stale              = ($IntuneRows    | Where-Object SyncVerdictColor -eq "Warning").Count
            Critical           = ($IntuneRows    | Where-Object SyncVerdictColor -eq "Critical").Count
            "Review >90d"      = ($IntuneRows    | Where-Object CleanPolicyColor -eq "CleanWarn1").Count
            "Pending >120d"    = ($IntuneRows    | Where-Object CleanPolicyColor -eq "CleanWarn2").Count
            "Can Delete >180d" = ($IntuneRows    | Where-Object CleanPolicyColor -eq "CleanDelete").Count
        }
        [PSCustomObject]@{
            Source             = "Azure AD (Windows)"
            TotalDevices       = $AzureRows.Count
            Healthy            = ($AzureRows     | Where-Object SyncVerdictColor -eq "Healthy").Count
            Stale              = ($AzureRows     | Where-Object SyncVerdictColor -eq "Warning").Count
            Critical           = ($AzureRows     | Where-Object SyncVerdictColor -eq "Critical").Count
            "Review >90d"      = ($AzureRows     | Where-Object CleanPolicyColor -eq "CleanWarn1").Count
            "Pending >120d"    = ($AzureRows     | Where-Object CleanPolicyColor -eq "CleanWarn2").Count
            "Can Delete >180d" = ($AzureRows     | Where-Object CleanPolicyColor -eq "CleanDelete").Count
        }
        [PSCustomObject]@{
            Source             = "Autopilot (Windows)"
            TotalDevices       = $AutopilotRows.Count
            Healthy            = ($AutopilotRows | Where-Object SyncVerdictColor -eq "Healthy").Count
            Stale              = ($AutopilotRows | Where-Object SyncVerdictColor -eq "Warning").Count
            Critical           = ($AutopilotRows | Where-Object SyncVerdictColor -eq "Critical").Count
            "Review >90d"      = ($AutopilotRows | Where-Object CleanPolicyColor -eq "CleanWarn1").Count
            "Pending >120d"    = ($AutopilotRows | Where-Object CleanPolicyColor -eq "CleanWarn2").Count
            "Can Delete >180d" = ($AutopilotRows | Where-Object CleanPolicyColor -eq "CleanDelete").Count
        }
    )

    $WB2   = $SummaryData | Export-Excel -Path $OutputFile -WorksheetName "Summary" `
        -AutoSize -BoldTopRow -FreezeTopRow -MoveToStart -PassThru
    $WS2   = $WB2.Workbook.Worksheets["Summary"]
    $Fill2 = [OfficeOpenXml.Style.ExcelFillStyle]::Solid

    for ($C = 1; $C -le $WS2.Dimension.Columns; $C++) {
        $WS2.Cells[1, $C].Style.Fill.PatternType = $Fill2
        $WS2.Cells[1, $C].Style.Fill.BackgroundColor.SetColor(
            [System.Drawing.ColorTranslator]::FromHtml("#$($ColorMap.Header)"))
        $WS2.Cells[1, $C].Style.Font.Color.SetColor([System.Drawing.Color]::White)
        $WS2.Cells[1, $C].Style.Font.Bold = $true
    }

    # Cols: 1=Source 2=Total 3=Healthy 4=Stale 5=Critical 6=>90d 7=>120d 8=>180d
    $ColColorMap = @{
        3 = $ColorMap.Healthy
        4 = $ColorMap.Warning
        5 = $ColorMap.Critical
        6 = $ColorMap.CleanWarn1
        7 = $ColorMap.CleanWarn2
        8 = $ColorMap.CleanDelete
    }
    for ($R = 2; $R -le $WS2.Dimension.Rows; $R++) {
        foreach ($C in $ColColorMap.Keys) {
            $Num  = 0
            $Cell = $WS2.Cells.Item($R, $C)
            if ([int]::TryParse($Cell.Text, [ref]$Num) -and $Num -gt 0) {
                $Cell.Style.Fill.PatternType = $Fill2
                $Cell.Style.Fill.BackgroundColor.SetColor(
                    [System.Drawing.ColorTranslator]::FromHtml("#$($ColColorMap[$C])"))
                if ($C -eq 8) {
                    $Cell.Style.Font.Color.SetColor([System.Drawing.Color]::White)
                }
            }
        }
    }
    Close-ExcelPackage $WB2
    Write-Log "Summary sheet written." -Level "SUCCESS"

    Write-SubProgress -Label "Writing Intune Devices sheet..." -Current 1 -Total 4
    Write-Sheet -SheetName "Intune Devices"    -Rows $IntuneRows
    Write-SubProgress -Label "Writing Azure AD Devices sheet..." -Current 2 -Total 4
    Write-Sheet -SheetName "Azure AD Devices"  -Rows $AzureRows
    Write-SubProgress -Label "Writing Autopilot Devices sheet..." -Current 3 -Total 4
    Write-Sheet -SheetName "Autopilot Devices" -Rows $AutopilotRows
    Complete-SubProgress
}

function Export-ToCsv {
    param($IntuneRows, $AzureRows, $AutopilotRows)
    $IntuneRows    | Export-Csv -Path (Join-Path $PSScriptRoot "Intune_$Timestamp.csv")    -NoTypeInformation -Encoding UTF8
    $AzureRows     | Export-Csv -Path (Join-Path $PSScriptRoot "AzureAD_$Timestamp.csv")   -NoTypeInformation -Encoding UTF8
    $AutopilotRows | Export-Csv -Path (Join-Path $PSScriptRoot "Autopilot_$Timestamp.csv") -NoTypeInformation -Encoding UTF8
    Write-Log "CSV fallback export complete." -Level "SUCCESS"
}
#endregion

#region ── MAIN ────────────────────────────────────────────────
try {
    $RunStart = Get-Date

    # ── Opening banner ──
    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor DarkCyan
    Write-Host "  ║   Get-AllDeviceInventory  v1.2       Sethu Kumar B         ║" -ForegroundColor DarkCyan
    Write-Host "  ║   Windows Device Inventory — Intune / Azure AD / Autopilot ║" -ForegroundColor DarkCyan
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor DarkCyan
    Write-Host ""
    Write-Host "  OS Filter    : Windows only" -ForegroundColor Gray
    Write-Host "  Sync         : Warn=${WarnDays}d  |  Critical=${CriticalDays}d" -ForegroundColor Gray
    Write-Host "  Clean Policy : Review=${CleanWarn1}d  |  Pending=${CleanWarn2}d  |  Delete=${CleanDelete}d" -ForegroundColor Gray
    Write-Host "  Output       : $OutputFile" -ForegroundColor Gray
    Write-Host ""

    Write-Log "=== Get-AllDeviceInventory v1.2 START ==="
    Write-Log "Output      : $OutputFile"
    Write-Log "Sync        : Warn=${WarnDays}d  |  Critical=${CriticalDays}d"
    Write-Log "Clean Policy: Review=${CleanWarn1}d  |  Pending=${CleanWarn2}d  |  Delete=${CleanDelete}d"
    Write-Log "OS Filter   : Windows only"

    $Token = Get-GraphToken

    $IntuneDevices    = Get-IntuneDevices    -Token $Token
    $AzureDevices     = Get-AzureADDevices   -Token $Token
    $AutopilotDevices = Get-AutopilotDevices -Token $Token

    $IntuneRows    = Build-IntuneRows    -Devices $IntuneDevices
    $AzureRows     = Build-AzureADRows   -Devices $AzureDevices
    $AutopilotRows = Build-AutopilotRows -Devices $AutopilotDevices

    Export-ToExcel -IntuneRows $IntuneRows -AzureRows $AzureRows -AutopilotRows $AutopilotRows

    # ── Completion summary ──
    Write-Progress -Id 1 -Activity "Get-AllDeviceInventory v1.2" -Completed
    $Elapsed = [int](New-TimeSpan -Start $RunStart -End (Get-Date)).TotalSeconds

    Write-Host ""
    Write-Host "  ╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "  ║                    COMPLETED SUCCESSFULLY                  ║" -ForegroundColor Green
    Write-Host "  ╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host ("  {0,-22} {1,6}  {2,8}  {3,6}  {4,9}  {5,6}  {6,7}  {7,7}" -f `
        "Source", "Total", "Healthy", "Stale", "Critical", ">90d", ">120d", ">180d") -ForegroundColor White
    Write-Host ("  {0}" -f ("─" * 78)) -ForegroundColor DarkGray

    foreach ($Entry in @(
        @{ Name = "Intune (Windows)   "; Data = $IntuneRows },
        @{ Name = "Azure AD (Windows) "; Data = $AzureRows },
        @{ Name = "Autopilot (Windows)"; Data = $AutopilotRows }
    )) {
        $D   = $Entry.Data
        $H   = ($D | Where-Object SyncVerdictColor -eq "Healthy").Count
        $S   = ($D | Where-Object SyncVerdictColor -eq "Warning").Count
        $Cr  = ($D | Where-Object SyncVerdictColor -eq "Critical").Count
        $W1  = ($D | Where-Object CleanPolicyColor -eq "CleanWarn1").Count
        $W2  = ($D | Where-Object CleanPolicyColor -eq "CleanWarn2").Count
        $Del = ($D | Where-Object CleanPolicyColor -eq "CleanDelete").Count
        Write-Host ("  {0,-22} {1,6}  {2,8}  {3,6}  {4,9}  {5,6}  {6,7}  {7,7}" -f `
            $Entry.Name, $D.Count, $H, $S, $Cr, $W1, $W2, $Del) -ForegroundColor Cyan
    }

    Write-Host ""
    Write-Host "  Output  : $OutputFile" -ForegroundColor White
    Write-Host "  Log     : $LogFile"    -ForegroundColor White
    Write-Host "  Runtime : ${Elapsed}s" -ForegroundColor White
    Write-Host ""

    Write-Log "=== COMPLETE in ${Elapsed}s ==="
    Write-Log "Intune    : $($IntuneRows.Count)  |  Can Delete: $(($IntuneRows    | Where-Object CleanPolicyColor -eq 'CleanDelete').Count)"
    Write-Log "Azure AD  : $($AzureRows.Count)  |  Can Delete: $(($AzureRows     | Where-Object CleanPolicyColor -eq 'CleanDelete').Count)"
    Write-Log "Autopilot : $($AutopilotRows.Count)  |  Can Delete: $(($AutopilotRows | Where-Object CleanPolicyColor -eq 'CleanDelete').Count)"
    Write-Log "File      : $OutputFile"
}
catch {
    Write-Progress -Id 1 -Activity "Get-AllDeviceInventory v1.2" -Completed
    Write-Host ""
    Write-Host "  FATAL ERROR: $_" -ForegroundColor Red
    Write-Log "FATAL: $_" -Level "ERROR"
    exit 1
}
finally {
    $ClientSecret = ""
    $TenantId     = ""
    $ClientId     = ""
}
#endregion