#Requires -Version 5.1
# ==============================================================================
# Script Name  : Get-WindowsDeviceInventoryByHostname-Full.ps1
# Description  : Retrieves full cross-source device inventory for a list of
#                Windows hostnames from a plain-text input file (one per line).
#
#                For each hostname, three data sources are queried:
#                  1. Intune (managedDevices) - base record via deviceName filter
#                  2. Azure AD (devices) - direct GET via azureADDeviceId from Intune
#                  3. Autopilot (windowsAutopilotDeviceIdentities) - filter by
#                     serialNumber from Intune record
#
#                If a device exists in Intune but NOT in Autopilot, all Autopilot
#                columns are populated with N/A and the row is still exported.
#                If a device is not found in Intune at all, a NotFound placeholder
#                row is written to preserve full traceability of the input list.
#
#                API call count: ~3 per hostname (Intune + AAD + Autopilot).
#
#                Columns exported:
#                --- INTUNE ---
#                  DeviceName, IntuneDeviceID, SerialNumber,
#                  OperatingSystem, FriendlyOSName, OSVersion, OSBuildNumber,
#                  Manufacturer, DeviceModel,
#                  PrimaryUser_UPN, PrimaryUser_DisplayName,
#                  ComplianceState, ManagementState, ManagementAgent,
#                  EnrollmentType, OwnerType, IsEncrypted,
#                  EnrolledDateTime, LastSyncDateTime, DaysSinceLastSync,
#                  JailBroken, EASActivated, EASDeviceId,
#                  SupervisedMode, PartnerReportedThreatState,
#                --- AZURE AD ---
#                  AzureAD_DeviceID, AzureAD_ObjectID,
#                  AzureAD_TrustType, AzureAD_JoinType,
#                  AzureAD_IsCompliant, AzureAD_IsManaged,
#                  AzureAD_AccountEnabled, AzureAD_RegisteredOwner,
#                  AzureAD_ApproximateLastSignIn,
#                  AzureAD_MDMAppId, AzureAD_ProfileType,
#                --- AUTOPILOT ---
#                  AP_AutopilotDeviceId, AP_GroupTag,
#                  AP_PurchaseOrderId, AP_DeploymentProfileName,
#                  AP_LastContactedDateTime, AP_EnrollmentState,
#                  AP_AddressableUserName,
#                --- LOOKUP METADATA ---
#                  DuplicateFlag, LookupStatus
#
#                Key behaviours:
#                  - v1.0 endpoint (stable - no beta dependency)
#                  - $filter + $select never combined on managedDevices (HTTP 400)
#                  - $select + $expand never combined on Autopilot filter (HTTP 500)
#                  - Azure AD lookup uses azureADDeviceId from Intune (no extra filter)
#                  - Autopilot lookup uses $filter on serialNumber (no $select)
#                  - All output saved to $PSScriptRoot
#
# Author       : Sethu Kumar B
# Version      : 1.0
# Created Date : 2026-05-27
# Last Modified: 2026-05-27
#
# Requirements :
#   - Azure AD App Registration
#   - Graph API Application Permissions (admin consent granted):
#       DeviceManagementManagedDevices.Read.All
#       DeviceManagementServiceConfig.Read.All
#       Device.Read.All
#   - PowerShell 5.1 or later
#   - Input file: plain text, one hostname per line, UTF-8 or ANSI
#   - Network access to:
#       https://login.microsoftonline.com
#       https://graph.microsoft.com
#
# Change Log   :
#   v1.0 - 2026-05-27 - Sethu Kumar B - Initial release
# ==============================================================================


#region --- CONFIGURATION --- Edit these values before running ----------------

$TenantID     = ""
$ClientID     = ""
$ClientSecret = ""

# Input file must be placed in the same folder as this script.
# Lines beginning with # and blank lines are ignored.
$InputFile    = Join-Path $PSScriptRoot "hostnames.txt"

#endregion --------------------------------------------------------------------


#region --- FUNCTIONS ---------------------------------------------------------

# ------------------------------------------------------------------------------
# FUNCTION : Write-Log
# ------------------------------------------------------------------------------
function Write-Log {
    param (
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Message,

        [ValidateSet("INFO","SUCCESS","WARN","ERROR","SECTION","PROGRESS","BLANK")]
        [string]$Level = "INFO"
    )

    $ColourMap = @{
        INFO     = "White"
        SUCCESS  = "Green"
        WARN     = "Yellow"
        ERROR    = "Red"
        SECTION  = "Cyan"
        PROGRESS = "Gray"
        BLANK    = "Gray"
    }

    $PrefixMap = @{
        INFO     = "[INFO]    "
        SUCCESS  = "[SUCCESS] "
        WARN     = "[WARN]    "
        ERROR    = "[ERROR]   "
        SECTION  = "[SECTION] "
        PROGRESS = "[PROGRESS]"
        BLANK    = "          "
    }

    Write-Host $Message -ForegroundColor $ColourMap[$Level]

    if ($script:LogFile) {
        try {
            $Ts      = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            $LogLine = "$Ts  $($PrefixMap[$Level]) $Message"
            Add-Content -Path $script:LogFile -Value $LogLine -Encoding UTF8
        }
        catch { }
    }
}


# ------------------------------------------------------------------------------
# FUNCTION : Get-GraphAccessToken
# ------------------------------------------------------------------------------
function Get-GraphAccessToken {
    param (
        [Parameter(Mandatory)][string]$TenantId,
        [Parameter(Mandatory)][string]$ClientId,
        [Parameter(Mandatory)][string]$ClientSecret
    )

    $TokenUrl = "https://login.microsoftonline.com/" + $TenantId + "/oauth2/v2.0/token"

    $Body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://graph.microsoft.com/.default"
    }

    try {
        Write-Log "[AUTH] Requesting access token from Microsoft Identity Platform..." -Level SECTION
        $Response = Invoke-RestMethod -Method POST -Uri $TokenUrl -Body $Body `
                    -ContentType "application/x-www-form-urlencoded" -ErrorAction Stop
        Write-Log "[AUTH] Access token acquired successfully." -Level SUCCESS
        Write-Log "" -Level BLANK
        return $Response.access_token
    }
    catch {
        Write-Log "[AUTH] Authentication failed: $_" -Level ERROR
        exit 1
    }
}


# ------------------------------------------------------------------------------
# FUNCTION : Invoke-GraphGet
# Purpose  : Single GET to a Graph URI. Returns parsed response object.
#            Returns $null on failure and logs the error.
# ------------------------------------------------------------------------------
function Invoke-GraphGet {
    param (
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$AccessToken,
        [string]$Label = ""
    )

    $Headers = @{
        Authorization  = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }

    try {
        return Invoke-RestMethod -Method GET -Uri $Uri -Headers $Headers -ErrorAction Stop
    }
    catch {
        if ($Label) {
            Write-Log "  [ERROR] $Label failed: $_" -Level ERROR
        }
        return $null
    }
}


# ------------------------------------------------------------------------------
# FUNCTION : Get-IntuneDeviceByHostname
# Purpose  : Filters managedDevices by deviceName.
#            Returns array of matching records (handles duplicates).
#            $filter only - NO $select (HTTP 400 if combined on this endpoint).
# ------------------------------------------------------------------------------
function Get-IntuneDeviceByHostname {
    param (
        [Parameter(Mandatory)][string]$Hostname,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $Encoded = [System.Uri]::EscapeDataString($Hostname)
    $Uri     = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices" +
               "?`$filter=deviceName eq '$Encoded'"

    $Response = Invoke-GraphGet -Uri $Uri -AccessToken $AccessToken `
                                -Label "Intune lookup [$Hostname]"

    if ($null -eq $Response) { return @() }
    return @($Response.value)
}


# ------------------------------------------------------------------------------
# FUNCTION : Get-AzureADDevice
# Purpose  : Direct GET on devices/{id} using azureADDeviceId from Intune.
#            No extra filter needed - ID is already known.
#            Returns $null if not found or on error.
# ------------------------------------------------------------------------------
function Get-AzureADDevice {
    param (
        [Parameter(Mandatory)][string]$AzureADDeviceId,
        [Parameter(Mandatory)][string]$AccessToken
    )

    $Uri = "https://graph.microsoft.com/v1.0/devices/$AzureADDeviceId"

    return Invoke-GraphGet -Uri $Uri -AccessToken $AccessToken `
                           -Label "Azure AD lookup [$AzureADDeviceId]"
}


# ------------------------------------------------------------------------------
# FUNCTION : Get-AutopilotDevice
# Purpose  : Filters windowsAutopilotDeviceIdentities by serialNumber.
#            CRITICAL CONSTRAINTS on this endpoint:
#              - $select combined with $filter = HTTP 500
#              - $expand combined with $filter = HTTP 500
#              - $filter only is safe; field extraction done client-side
#            Returns first matching Autopilot record or $null if not found.
# ------------------------------------------------------------------------------
function Get-AutopilotDevice {
    param (
        [Parameter(Mandatory)][string]$SerialNumber,
        [Parameter(Mandatory)][string]$AccessToken
    )

    if ([string]::IsNullOrWhiteSpace($SerialNumber) -or $SerialNumber -eq "N/A") {
        return $null
    }

    $Encoded = [System.Uri]::EscapeDataString($SerialNumber)
    $Uri     = "https://graph.microsoft.com/v1.0/deviceManagement/windowsAutopilotDeviceIdentities" +
               "?`$filter=contains(serialNumber,'$Encoded')"

    $Response = Invoke-GraphGet -Uri $Uri -AccessToken $AccessToken `
                                -Label "Autopilot lookup [SN:$SerialNumber]"

    if ($null -eq $Response)                   { return $null }
    if ($null -eq $Response.value)             { return $null }
    if ($Response.value.Count -eq 0)           { return $null }
    return $Response.value[0]
}


# ------------------------------------------------------------------------------
# FUNCTION : ConvertTo-FriendlyOSName
# ------------------------------------------------------------------------------
function ConvertTo-FriendlyOSName {
    param ([string]$OSVersion)

    if ([string]::IsNullOrWhiteSpace($OSVersion)) { return "Unknown" }

    $BuildNumber = 0
    if ($OSVersion -match "10\.0\.(\d+)") {
        $BuildNumber = [int]$Matches[1]
    }
    elseif ($OSVersion -match "^(\d+)$") {
        $BuildNumber = [int]$OSVersion
    }

    if ($BuildNumber -ge 28000) { return "Windows 11 26H1" }
    if ($BuildNumber -ge 26200) { return "Windows 11 25H2" }
    if ($BuildNumber -ge 26100) { return "Windows 11 24H2" }
    if ($BuildNumber -ge 22631) { return "Windows 11 23H2" }
    if ($BuildNumber -ge 22621) { return "Windows 11 22H2" }
    if ($BuildNumber -ge 22000) { return "Windows 11 21H2" }
    if ($BuildNumber -ge 19045) { return "Windows 10 22H2" }
    if ($BuildNumber -ge 19044) { return "Windows 10 21H2" }
    if ($BuildNumber -ge 19043) { return "Windows 10 21H1" }
    if ($BuildNumber -ge 19042) { return "Windows 10 20H2" }
    if ($BuildNumber -ge 19041) { return "Windows 10 2004" }
    if ($BuildNumber -ge 18363) { return "Windows 10 1909" }
    if ($BuildNumber -ge 18362) { return "Windows 10 1903" }
    if ($BuildNumber -ge 17763) { return "Windows 10 1809" }
    if ($BuildNumber -ge 17134) { return "Windows 10 1803" }
    if ($BuildNumber -ge 16299) { return "Windows 10 1709" }
    if ($BuildNumber -ge 15063) { return "Windows 10 1703" }
    if ($BuildNumber -ge 14393) { return "Windows 10 1607" }
    if ($BuildNumber -ge 10586) { return "Windows 10 1511" }
    if ($BuildNumber -ge 10240) { return "Windows 10 1507" }
    if ($BuildNumber -ge 20348) { return "Windows Server 2022" }
    if ($BuildNumber -ge 17763) { return "Windows Server 2019" }
    if ($BuildNumber -ge 14393) { return "Windows Server 2016" }
    if ($BuildNumber -gt 0)     { return "Windows (Build $BuildNumber)" }
    return "Unknown"
}


# ------------------------------------------------------------------------------
# FUNCTION : ConvertTo-FriendlyDate
# ------------------------------------------------------------------------------
function ConvertTo-FriendlyDate {
    param ([string]$DateString)

    if ([string]::IsNullOrWhiteSpace($DateString)) { return "N/A" }
    if ($DateString -like "0001-01-01*")            { return "Never" }

    try {
        $dt = [datetime]::Parse($DateString, $null,
              [System.Globalization.DateTimeStyles]::RoundtripKind)
        return $dt.ToLocalTime().ToString("yyyy-MM-dd HH:mm:ss")
    }
    catch { return $DateString }
}


# ------------------------------------------------------------------------------
# FUNCTION : ConvertTo-FriendlyEnrollmentType
# ------------------------------------------------------------------------------
function ConvertTo-FriendlyEnrollmentType {
    param ([string]$Value)

    $Map = @{
        "userEnrollment"                   = "User Enrollment (BYOD)"
        "deviceEnrollmentManager"          = "Device Enrollment Manager (DEM)"
        "azureDomainJoined"                = "Azure AD Joined"
        "userEnrollmentWithServiceAccount" = "User Enrollment with Service Account"
        "deviceEnrollmentProgram"          = "Apple DEP / Autopilot"
        "windowsAutoEnrollment"            = "Windows Auto-Enrollment (MDM)"
        "windowsBulkAzureDomainJoin"       = "Bulk Azure AD Join"
        "windowsBulkUserless"              = "Bulk Userless (Autopilot)"
        "windowsCoManagement"              = "Co-Management (Intune + SCCM)"
        "unknownFutureValue"               = "Unknown"
        "unknown"                          = "Unknown"
    }

    if ([string]::IsNullOrWhiteSpace($Value)) { return "N/A" }
    if ($Map.ContainsKey($Value))             { return $Map[$Value] }
    return $Value
}


# ------------------------------------------------------------------------------
# FUNCTION : Get-AADTrustType
# Purpose  : Maps Azure AD trustType raw value to readable string.
# ------------------------------------------------------------------------------
function Get-AADTrustType {
    param ([string]$Value)

    $Map = @{
        "AzureAd"         = "Azure AD Joined"
        "ServerAd"        = "Hybrid Azure AD Joined"
        "Workplace"       = "Azure AD Registered (BYOD)"
    }

    if ([string]::IsNullOrWhiteSpace($Value)) { return "N/A" }
    if ($Map.ContainsKey($Value))             { return $Map[$Value] }
    return $Value
}


# ------------------------------------------------------------------------------
# FUNCTION : Shape-FullRecord
# Purpose  : Merges Intune, Azure AD, and Autopilot objects into one flat row.
#            AAD and Autopilot objects may be $null - handled with N/A fallback.
# ------------------------------------------------------------------------------
function Shape-FullRecord {
    param (
        [Parameter(Mandatory)][PSObject]$IntuneDevice,
        [PSObject]$AADDevice,
        [PSObject]$AutopilotDevice,
        [Parameter(Mandatory)][string]$LookupStatus,
        [Parameter(Mandatory)][bool]$IsDuplicate
    )

    # -- Build number + days since sync from Intune record --------------------
    $BuildNumber = "N/A"
    if ($IntuneDevice.osVersion -match "10\.0\.(\d+)") {
        $BuildNumber = $Matches[1]
    }

    $DaysSinceSync = "N/A"
    if ($IntuneDevice.lastSyncDateTime -and
        $IntuneDevice.lastSyncDateTime -notlike "0001*") {
        try {
            $SyncDate      = [datetime]::Parse($IntuneDevice.lastSyncDateTime, $null,
                             [System.Globalization.DateTimeStyles]::RoundtripKind)
            $DaysSinceSync = [math]::Round(((Get-Date) - $SyncDate).TotalDays, 1)
        }
        catch { $DaysSinceSync = "N/A" }
    }

    # -- AAD registered owner (first entry only) ------------------------------
    $AADOwner = "N/A"
    if ($null -ne $AADDevice -and
        $null -ne $AADDevice.registeredOwners -and
        $AADDevice.registeredOwners.Count -gt 0) {
        $OwnerObj = $AADDevice.registeredOwners[0]
        if ($OwnerObj.userPrincipalName) {
            $AADOwner = [string]$OwnerObj.userPrincipalName
        }
        elseif ($OwnerObj.displayName) {
            $AADOwner = [string]$OwnerObj.displayName
        }
    }

    return [PSCustomObject]@{

        # ======================================================================
        # INTUNE
        # ======================================================================
        "DeviceName"                   = if ($IntuneDevice.deviceName)            { [string]$IntuneDevice.deviceName }            else { "N/A" }
        "IntuneDeviceID"               = [string]$IntuneDevice.id
        "SerialNumber"                 = if ($IntuneDevice.serialNumber)          { [string]$IntuneDevice.serialNumber }          else { "N/A" }

        "OperatingSystem"              = "Windows"
        "FriendlyOSName"               = ConvertTo-FriendlyOSName -OSVersion $IntuneDevice.osVersion
        "OSVersion"                    = if ($IntuneDevice.osVersion)             { [string]$IntuneDevice.osVersion }             else { "N/A" }
        "OSBuildNumber"                = $BuildNumber

        "Manufacturer"                 = if ($IntuneDevice.manufacturer)          { [string]$IntuneDevice.manufacturer }          else { "N/A" }
        "DeviceModel"                  = if ($IntuneDevice.model)                 { [string]$IntuneDevice.model }                 else { "N/A" }

        "PrimaryUser_UPN"              = if ($IntuneDevice.userPrincipalName)     { [string]$IntuneDevice.userPrincipalName }     else { "No Primary User" }
        "PrimaryUser_DisplayName"      = if ($IntuneDevice.userDisplayName)       { [string]$IntuneDevice.userDisplayName }       else { "N/A" }

        "ComplianceState"              = if ($IntuneDevice.complianceState)       { [string]$IntuneDevice.complianceState }       else { "N/A" }
        "ManagementState"              = if ($IntuneDevice.managementState)       { [string]$IntuneDevice.managementState }       else { "N/A" }
        "ManagementAgent"              = if ($IntuneDevice.managementAgent)       { [string]$IntuneDevice.managementAgent }       else { "N/A" }

        "EnrollmentType"               = ConvertTo-FriendlyEnrollmentType -Value $IntuneDevice.deviceEnrollmentType
        "OwnerType"                    = if ($IntuneDevice.managedDeviceOwnerType){ [string]$IntuneDevice.managedDeviceOwnerType } else { "N/A" }

        "IsEncrypted"                  = if ($null -ne $IntuneDevice.isEncrypted) { $IntuneDevice.isEncrypted }                   else { "N/A" }

        "EnrolledDateTime"             = ConvertTo-FriendlyDate -DateString $IntuneDevice.enrolledDateTime
        "LastSyncDateTime"             = ConvertTo-FriendlyDate -DateString $IntuneDevice.lastSyncDateTime
        "DaysSinceLastSync"            = $DaysSinceSync

        "JailBroken"                   = if ($IntuneDevice.jailBroken)            { [string]$IntuneDevice.jailBroken }            else { "N/A" }
        "EASActivated"                 = if ($null -ne $IntuneDevice.easActivated){ $IntuneDevice.easActivated }                  else { "N/A" }
        "EASDeviceId"                  = if ($IntuneDevice.easDeviceId)           { [string]$IntuneDevice.easDeviceId }           else { "N/A" }
        "SupervisedMode"               = if ($null -ne $IntuneDevice.isSupervised){ $IntuneDevice.isSupervised }                  else { "N/A" }
        "PartnerReportedThreatState"   = if ($IntuneDevice.partnerReportedThreatState){ [string]$IntuneDevice.partnerReportedThreatState } else { "N/A" }

        # ======================================================================
        # AZURE AD
        # ======================================================================
        "AzureAD_DeviceID"             = if ($null -ne $AADDevice -and $AADDevice.deviceId)             { [string]$AADDevice.deviceId }             else { "N/A" }
        "AzureAD_ObjectID"             = if ($null -ne $AADDevice -and $AADDevice.id)                   { [string]$AADDevice.id }                   else { "N/A" }
        "AzureAD_TrustType"            = if ($null -ne $AADDevice)                                      { Get-AADTrustType -Value $AADDevice.trustType } else { "N/A" }
        "AzureAD_JoinType"             = if ($null -ne $AADDevice -and $AADDevice.joinType)             { [string]$AADDevice.joinType }             else { "N/A" }
        "AzureAD_IsCompliant"          = if ($null -ne $AADDevice -and $null -ne $AADDevice.isCompliant){ $AADDevice.isCompliant }                  else { "N/A" }
        "AzureAD_IsManaged"            = if ($null -ne $AADDevice -and $null -ne $AADDevice.isManaged)  { $AADDevice.isManaged }                    else { "N/A" }
        "AzureAD_AccountEnabled"       = if ($null -ne $AADDevice -and $null -ne $AADDevice.accountEnabled){ $AADDevice.accountEnabled }            else { "N/A" }
        "AzureAD_RegisteredOwner"      = $AADOwner
        "AzureAD_ApproximateLastSignIn"= if ($null -ne $AADDevice -and $AADDevice.approximateLastSignInDateTime){ ConvertTo-FriendlyDate -DateString $AADDevice.approximateLastSignInDateTime } else { "N/A" }
        "AzureAD_MDMAppId"             = if ($null -ne $AADDevice -and $AADDevice.mdmAppId)             { [string]$AADDevice.mdmAppId }             else { "N/A" }
        "AzureAD_ProfileType"          = if ($null -ne $AADDevice -and $AADDevice.profileType)          { [string]$AADDevice.profileType }          else { "N/A" }

        # ======================================================================
        # AUTOPILOT
        # ======================================================================
        "AP_AutopilotDeviceId"         = if ($null -ne $AutopilotDevice -and $AutopilotDevice.id)                    { [string]$AutopilotDevice.id }                    else { "N/A" }
        "AP_GroupTag"                  = if ($null -ne $AutopilotDevice -and $AutopilotDevice.groupTag)              { [string]$AutopilotDevice.groupTag }              else { "N/A" }
        "AP_PurchaseOrderId"           = if ($null -ne $AutopilotDevice -and $AutopilotDevice.purchaseOrderIdentifier){ [string]$AutopilotDevice.purchaseOrderIdentifier } else { "N/A" }
        "AP_DeploymentProfileName"     = if ($null -ne $AutopilotDevice -and $AutopilotDevice.deploymentProfileAssignmentDetailedStatus){ [string]$AutopilotDevice.deploymentProfileAssignmentDetailedStatus } else { "N/A" }
        "AP_LastContactedDateTime"     = if ($null -ne $AutopilotDevice -and $AutopilotDevice.lastContactedDateTime){ ConvertTo-FriendlyDate -DateString $AutopilotDevice.lastContactedDateTime } else { "N/A" }
        "AP_EnrollmentState"           = if ($null -ne $AutopilotDevice -and $AutopilotDevice.enrollmentState)       { [string]$AutopilotDevice.enrollmentState }       else { "N/A" }
        "AP_AddressableUserName"       = if ($null -ne $AutopilotDevice -and $AutopilotDevice.addressableUserName)   { [string]$AutopilotDevice.addressableUserName }   else { "N/A" }

        # ======================================================================
        # LOOKUP METADATA
        # ======================================================================
        "DuplicateFlag"                = $IsDuplicate
        "LookupStatus"                 = $LookupStatus
    }
}


# ------------------------------------------------------------------------------
# FUNCTION : New-NotFoundRow
# Purpose  : Placeholder row for hostnames with no Intune record.
# ------------------------------------------------------------------------------
function New-NotFoundRow {
    param ([Parameter(Mandatory)][string]$Hostname)

    $NA = "N/A"
    return [PSCustomObject]@{
        "DeviceName"                    = $Hostname
        "IntuneDeviceID"                = $NA
        "SerialNumber"                  = $NA
        "OperatingSystem"               = $NA
        "FriendlyOSName"                = $NA
        "OSVersion"                     = $NA
        "OSBuildNumber"                 = $NA
        "Manufacturer"                  = $NA
        "DeviceModel"                   = $NA
        "PrimaryUser_UPN"               = $NA
        "PrimaryUser_DisplayName"       = $NA
        "ComplianceState"               = $NA
        "ManagementState"               = $NA
        "ManagementAgent"               = $NA
        "EnrollmentType"                = $NA
        "OwnerType"                     = $NA
        "IsEncrypted"                   = $NA
        "EnrolledDateTime"              = $NA
        "LastSyncDateTime"              = $NA
        "DaysSinceLastSync"             = $NA
        "JailBroken"                    = $NA
        "EASActivated"                  = $NA
        "EASDeviceId"                   = $NA
        "SupervisedMode"                = $NA
        "PartnerReportedThreatState"    = $NA
        "AzureAD_DeviceID"              = $NA
        "AzureAD_ObjectID"              = $NA
        "AzureAD_TrustType"             = $NA
        "AzureAD_JoinType"              = $NA
        "AzureAD_IsCompliant"           = $NA
        "AzureAD_IsManaged"             = $NA
        "AzureAD_AccountEnabled"        = $NA
        "AzureAD_RegisteredOwner"       = $NA
        "AzureAD_ApproximateLastSignIn" = $NA
        "AzureAD_MDMAppId"              = $NA
        "AzureAD_ProfileType"           = $NA
        "AP_AutopilotDeviceId"          = $NA
        "AP_GroupTag"                   = $NA
        "AP_PurchaseOrderId"            = $NA
        "AP_DeploymentProfileName"      = $NA
        "AP_LastContactedDateTime"      = $NA
        "AP_EnrollmentState"            = $NA
        "AP_AddressableUserName"        = $NA
        "DuplicateFlag"                 = $false
        "LookupStatus"                  = "NotFound"
    }
}

#endregion --------------------------------------------------------------------


#region --- MAIN --------------------------------------------------------------

# -- Step 1: Resolve paths and initialise log file ----------------------------
$Timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$OutputFile     = Join-Path $PSScriptRoot ("Windows_Inventory_ByHostname_Full_" + $Timestamp + ".csv")
$script:LogFile = Join-Path $PSScriptRoot ("Windows_Inventory_ByHostname_Full_" + $Timestamp + ".log")

$LogHeader = @"
================================================================================
  Windows Device Inventory - Full Cross-Source (By Hostname)  |  Sethu Kumar B
  Run started : $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
  Script      : $PSCommandPath
  Input file  : $InputFile
  Output CSV  : $OutputFile
  Log file    : $($script:LogFile)
  Sources     : Intune + Azure AD + Autopilot
  Endpoint    : v1.0 managedDevices / devices / windowsAutopilotDeviceIdentities
================================================================================

"@

try {
    [System.IO.File]::WriteAllText($script:LogFile, $LogHeader,
        [System.Text.Encoding]::UTF8)
}
catch {
    Write-Host "[WARN] Could not create log file: $_" -ForegroundColor Yellow
    $script:LogFile = $null
}

# -- Step 2: Console + log banner ---------------------------------------------
Write-Log "" -Level BLANK
Write-Log "================================================================" -Level SECTION
Write-Log "  Windows Inventory - Full Cross-Source (By Hostname)           " -Level SECTION
Write-Log "  Sethu Kumar B                                                  " -Level SECTION
Write-Log "================================================================" -Level SECTION
Write-Log "[INFO] Script root     : $PSScriptRoot"      -Level INFO
Write-Log "[INFO] Input file      : $InputFile"         -Level INFO
Write-Log "[INFO] Output CSV      : $OutputFile"        -Level INFO
Write-Log "[INFO] Log file        : $($script:LogFile)" -Level INFO
Write-Log "[INFO] Timestamp       : $Timestamp"         -Level INFO
Write-Log "[INFO] Sources         : Intune + Azure AD + Autopilot" -Level INFO
Write-Log "[INFO] API calls       : ~3 per hostname (Intune + AAD + Autopilot)" -Level INFO
Write-Log "" -Level BLANK

# -- Step 3: Load and validate input file -------------------------------------
if (-not (Test-Path $InputFile)) {
    Write-Log "[ERROR] Input file not found: $InputFile" -Level ERROR
    exit 1
}

$RawLines  = Get-Content -Path $InputFile -Encoding UTF8 -ErrorAction Stop
$Hostnames = [System.Collections.Generic.List[string]]::new()

foreach ($Line in $RawLines) {
    $Trimmed = $Line.Trim()
    if ([string]::IsNullOrWhiteSpace($Trimmed)) { continue }
    if ($Trimmed.StartsWith("#"))               { continue }
    $Hostnames.Add($Trimmed)
}

if ($Hostnames.Count -eq 0) {
    Write-Log "[WARN] Input file contains no valid hostnames after skipping blanks and comments." -Level WARN
    exit 0
}

Write-Log "[INFO] Hostnames loaded: $($Hostnames.Count)" -Level INFO
Write-Log "[INFO] Estimated API calls: ~$($Hostnames.Count * 3)" -Level INFO
Write-Log "" -Level BLANK

# -- Step 4: Authenticate -----------------------------------------------------
$AccessToken = Get-GraphAccessToken -TenantId $TenantID `
               -ClientId $ClientID -ClientSecret $ClientSecret

# -- Step 5: Per-hostname cross-source lookup ---------------------------------
Write-Log "------------------------------------------------------------" -Level SECTION
Write-Log "  STEP 1 OF 2  -  Cross-Source Lookup Per Hostname          " -Level SECTION
Write-Log "------------------------------------------------------------" -Level SECTION

$FinalRecords        = [System.Collections.Generic.List[PSObject]]::new()
$CountFound          = 0
$CountNotFound       = 0
$CountDuplicate      = 0
$CountAADMiss        = 0
$CountAutopilotMiss  = 0
$Total               = $Hostnames.Count

for ($i = 0; $i -lt $Total; $i++) {
    $Hostname  = $Hostnames[$i]
    $ProgressMsg = "  [{0,4}/{1}]  {2}" -f ($i + 1), $Total, $Hostname
    Write-Log $ProgressMsg -Level PROGRESS

    # -- 1. Intune lookup -----------------------------------------------------
    $IntuneRecords = Get-IntuneDeviceByHostname -Hostname $Hostname `
                                                -AccessToken $AccessToken

    if ($null -eq $IntuneRecords -or $IntuneRecords.Count -eq 0) {
        Write-Log "           -> Intune: NotFound" -Level WARN
        $FinalRecords.Add((New-NotFoundRow -Hostname $Hostname))
        $CountNotFound++
        continue
    }

    $IsDup = ($IntuneRecords.Count -gt 1)
    if ($IsDup) {
        Write-Log ("           -> Intune: DUPLICATE ({0} records)" -f $IntuneRecords.Count) -Level WARN
        $CountDuplicate++
    }
    else {
        Write-Log "           -> Intune: Found" -Level SUCCESS
        $CountFound++
    }

    # -- 2. Process each Intune record (handles duplicates) -------------------
    foreach ($IntuneDevice in $IntuneRecords) {

        # -- 2a. Azure AD lookup via azureADDeviceId from Intune --------------
        $AADDevice = $null
        $AADId     = [string]$IntuneDevice.azureADDeviceId

        if (-not [string]::IsNullOrWhiteSpace($AADId) -and
            $AADId -ne "00000000-0000-0000-0000-000000000000") {

            $AADDevice = Get-AzureADDevice -AzureADDeviceId $AADId `
                                           -AccessToken $AccessToken

            if ($null -eq $AADDevice) {
                Write-Log "           -> Azure AD: NotFound (ID: $AADId)" -Level WARN
                $CountAADMiss++
            }
            else {
                Write-Log "           -> Azure AD: Found" -Level SUCCESS
            }
        }
        else {
            Write-Log "           -> Azure AD: Skipped (no valid azureADDeviceId on Intune record)" -Level WARN
            $CountAADMiss++
        }

        # -- 2b. Autopilot lookup via serialNumber from Intune ----------------
        $AutopilotDevice = $null
        $Serial          = [string]$IntuneDevice.serialNumber

        if (-not [string]::IsNullOrWhiteSpace($Serial) -and $Serial -ne "N/A") {
            $AutopilotDevice = Get-AutopilotDevice -SerialNumber $Serial `
                                                   -AccessToken $AccessToken

            if ($null -eq $AutopilotDevice) {
                Write-Log "           -> Autopilot: NotFound (SN: $Serial)" -Level WARN
                $CountAutopilotMiss++
            }
            else {
                Write-Log "           -> Autopilot: Found" -Level SUCCESS
            }
        }
        else {
            Write-Log "           -> Autopilot: Skipped (no valid serial on Intune record)" -Level WARN
            $CountAutopilotMiss++
        }

        # -- 2c. Shape and collect merged record ------------------------------
        $Status = if ($IsDup) { "Duplicate" } else { "Found" }

        $FinalRecords.Add((Shape-FullRecord -IntuneDevice    $IntuneDevice `
                                            -AADDevice       $AADDevice `
                                            -AutopilotDevice $AutopilotDevice `
                                            -LookupStatus    $Status `
                                            -IsDuplicate     $IsDup))
    }
}

Write-Log "" -Level BLANK
Write-Log "[INFO] Lookup complete. Total rows to export: $($FinalRecords.Count)" -Level INFO
Write-Log "" -Level BLANK

# -- Step 6: Export CSV -------------------------------------------------------
Write-Log "------------------------------------------------------------" -Level SECTION
Write-Log "  STEP 2 OF 2  -  Exporting CSV                            " -Level SECTION
Write-Log "------------------------------------------------------------" -Level SECTION

try {
    $FinalRecords | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
    $SizeMB = (((Get-Item $OutputFile).Length) / 1MB).ToString("0.00")
    Write-Log "[EXPORT] CSV exported successfully." -Level SUCCESS
    Write-Log "         Path  : $OutputFile"        -Level INFO
    Write-Log "         Rows  : $($FinalRecords.Count)   |   Size: $SizeMB MB" -Level INFO
    Write-Log "" -Level BLANK
}
catch {
    Write-Log "[EXPORT] Failed to write CSV: $_" -Level ERROR
    exit 1
}

# -- Step 7: Summary ----------------------------------------------------------
$Win11        = ($FinalRecords | Where-Object { $_.FriendlyOSName -like "Windows 11*"     }).Count
$Win10        = ($FinalRecords | Where-Object { $_.FriendlyOSName -like "Windows 10*"     }).Count
$WinServer    = ($FinalRecords | Where-Object { $_.FriendlyOSName -like "Windows Server*" }).Count
$Compliant    = ($FinalRecords | Where-Object { $_.ComplianceState -eq "compliant"        }).Count
$NonCompliant = ($FinalRecords | Where-Object { $_.ComplianceState -eq "nonCompliant"     }).Count
$Encrypted    = ($FinalRecords | Where-Object { $_.IsEncrypted -eq $true                 }).Count
$NotEncrypted = ($FinalRecords | Where-Object { $_.IsEncrypted -eq $false                }).Count
$APFound      = ($FinalRecords | Where-Object { $_.AP_AutopilotDeviceId -ne "N/A"        }).Count
$APMissing    = ($FinalRecords | Where-Object { $_.AP_AutopilotDeviceId -eq "N/A" -and $_.LookupStatus -ne "NotFound" }).Count
$Stale30      = ($FinalRecords | Where-Object { $_.DaysSinceLastSync -ne "N/A" -and [double]$_.DaysSinceLastSync -gt 30  }).Count
$Stale90      = ($FinalRecords | Where-Object { $_.DaysSinceLastSync -ne "N/A" -and [double]$_.DaysSinceLastSync -gt 90  }).Count
$Stale180     = ($FinalRecords | Where-Object { $_.DaysSinceLastSync -ne "N/A" -and [double]$_.DaysSinceLastSync -gt 180 }).Count
$AADJoined    = ($FinalRecords | Where-Object { $_.AzureAD_TrustType -eq "Azure AD Joined"         }).Count
$HybridJoined = ($FinalRecords | Where-Object { $_.AzureAD_TrustType -eq "Hybrid Azure AD Joined"  }).Count

Write-Log "================================================================" -Level SECTION
Write-Log "   SUMMARY                                                      " -Level SECTION
Write-Log "================================================================" -Level SECTION
Write-Log "  -- Lookup Results -----------------------------------------------" -Level SECTION
Write-Log "  Input hostnames              : $Total"              -Level INFO
Write-Log "  Found in Intune (unique)     : $CountFound"         -Level SUCCESS
Write-Log "  Not found in Intune          : $CountNotFound"      -Level WARN
Write-Log "  Hostnames with duplicates    : $CountDuplicate"     -Level WARN
Write-Log "  Azure AD record missing      : $CountAADMiss"       -Level WARN
Write-Log "  Autopilot record missing     : $CountAutopilotMiss" -Level WARN
Write-Log "  Total CSV rows               : $($FinalRecords.Count)" -Level INFO
Write-Log "" -Level BLANK
Write-Log "  -- OS Breakdown --------------------------------------------------" -Level SECTION
Write-Log "  Windows 11                   : $Win11"              -Level INFO
Write-Log "  Windows 10                   : $Win10"              -Level INFO
Write-Log "  Windows Server               : $WinServer"          -Level INFO
Write-Log "" -Level BLANK
Write-Log "  -- Azure AD Join Type --------------------------------------------" -Level SECTION
Write-Log "  Azure AD Joined              : $AADJoined"          -Level INFO
Write-Log "  Hybrid Azure AD Joined       : $HybridJoined"       -Level INFO
Write-Log "" -Level BLANK
Write-Log "  -- Compliance ----------------------------------------------------" -Level SECTION
Write-Log "  Compliant                    : $Compliant"          -Level SUCCESS
Write-Log "  Non-Compliant                : $NonCompliant"       -Level WARN
Write-Log "" -Level BLANK
Write-Log "  -- Encryption ----------------------------------------------------" -Level SECTION
Write-Log "  Encrypted                    : $Encrypted"          -Level SUCCESS
Write-Log "  Not Encrypted                : $NotEncrypted"       -Level WARN
Write-Log "" -Level BLANK
Write-Log "  -- Autopilot Coverage --------------------------------------------" -Level SECTION
Write-Log "  Autopilot record found       : $APFound"            -Level SUCCESS
Write-Log "  No Autopilot record          : $APMissing"          -Level WARN
Write-Log "" -Level BLANK
Write-Log "  -- Check-In Health -----------------------------------------------" -Level SECTION
Write-Log "  Not synced > 30 days         : $Stale30"            -Level WARN
Write-Log "  Not synced > 90 days         : $Stale90"            -Level ERROR
Write-Log "  Not synced > 180 days        : $Stale180"           -Level ERROR
Write-Log "" -Level BLANK
Write-Log "  -- Output Files --------------------------------------------------" -Level SECTION
Write-Log "  CSV  : $OutputFile"         -Level INFO
Write-Log "  Log  : $($script:LogFile)"  -Level INFO
Write-Log "================================================================" -Level SECTION
Write-Log "" -Level BLANK

#endregion --------------------------------------------------------------------
