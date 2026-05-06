#Requires -Version 5.1
# ==============================================================================
# Script Name  : Get-IntuneAndAADDevicesByUser.ps1
# Description  : Retrieves all Intune and Azure AD devices associated with one
#                or more users from a text file. Queries both Intune managed
#                devices and Azure AD registered devices per user, deduplicates
#                the results, and exports ALL users into a single combined CSV.
#
#                OUTPUT:
#                  All users written into ONE CSV file named:
#                    UserDevices_[yyyyMMdd_HHmmss].csv
#                  The UserEmail column identifies which user each row belongs to.
#                  Users with no devices appear as a placeholder row so every
#                  address in the input is accounted for in the output.
#
#                COLUMNS:
#                  UserEmail, DeviceSource, DeviceName,
#                  IntuneDeviceId, AzureADDeviceId, AzureADObjectId,
#                  UserPrincipalName, SerialNumber, OperatingSystem
#
# Author       : Sethu Kumar B
# Version      : 1.1
# Created Date : 2026-04-03
# Last Modified: 2026-04-10
#
# Requirements :
#   - Microsoft Graph PowerShell SDK (Install-Module Microsoft.Graph)
#   - Azure AD App Registration:
#       DeviceManagementManagedDevices.Read.All
#       Device.Read.All
#       User.Read.All
#
# Change Log   :
#   v1.0 - 2026-04-03 - Sethu Kumar B - Initial release. Per-user CSV output.
#   v1.1 - 2026-04-10 - Sethu Kumar B - Single combined CSV for all users.
#                        Fixed op_Addition error: switched all collections to
#                        [System.Collections.Generic.List] and explicitly cast
#                        all Graph response fields to [string] before comparison
#                        — prevents PSObject method invocation failure when Graph
#                        returns a nested object instead of a plain string.
#                        Error rows included in output so every user in the
#                        input file always appears in the CSV.
# ==============================================================================

param(
  [string]$TenantId     = "",
    [string]$ClientId     = "",
    [string]$ClientSecret = "",
    [string]$InputFile    = "users.txt",
    [string]$TargetOS     = "Windows"
)

# ── Paths ──────────────────────────────────────────────────────────────────────
$ScriptRoot     = $PSScriptRoot
$Timestamp      = Get-Date -Format "yyyyMMdd_HHmmss"
$TranscriptFile = Join-Path $ScriptRoot "Get-UserDevices-Transcript_$Timestamp.log"
$ActionLogFile  = Join-Path $ScriptRoot "Get-UserDevices-Actions_$Timestamp.log"
$OutputFile     = Join-Path $ScriptRoot "UserDevices_$Timestamp.csv"
$InputPath      = Join-Path $ScriptRoot $InputFile


# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION : Write-ActionLog
# ─────────────────────────────────────────────────────────────────────────────
function Write-ActionLog {
    param(
        [string]$Message,
        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level = "INFO"
    )
    $ColourMap = @{ INFO = "Gray"; WARN = "Yellow"; ERROR = "Red" }
    $ts   = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $line = "$ts [$Level] $Message"
    Write-Host $line -ForegroundColor $ColourMap[$Level]
    try { Add-Content -Path $ActionLogFile -Value $line -Encoding UTF8 } catch { }
}


# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION : Connect-ToGraph
# ─────────────────────────────────────────────────────────────────────────────
function Connect-ToGraph {
    $secureSecret = ConvertTo-SecureString $ClientSecret -AsPlainText -Force
    $cred         = [pscredential]::new($ClientId, $secureSecret)
    Connect-MgGraph -TenantId $TenantId -ClientSecretCredential $cred | Out-Null
}


# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION : Invoke-GraphPagedGet
# Purpose  : Pages through Graph API results. Returns a Generic List so the
#            caller can safely use .AddRange() without risking op_Addition.
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-GraphPagedGet {
    param([Parameter(Mandatory)][string]$Uri)

    $items = [System.Collections.Generic.List[PSObject]]::new()
    $next  = $Uri

    while ($next) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $next
        if ($response.value) {
            foreach ($item in $response.value) { $items.Add($item) }
        }
        $next = $response.'@odata.nextLink'
    }

    return $items
}


# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION : Get-UserIntuneDevices
# Purpose  : Retrieves Intune managed devices matching the given email address.
#
#            ROOT CAUSE FIX — op_Addition error:
#            Graph API occasionally returns nested PSObject or OrderedDictionary
#            values for string fields instead of plain strings. Calling .ToLower()
#            on those triggers the PSObject method invocation failure. All fields
#            are explicitly cast to [string] before any string operation is called.
# ─────────────────────────────────────────────────────────────────────────────
function Get-UserIntuneDevices {
    param([Parameter(Mandatory)][string]$Email)

    $results    = [System.Collections.Generic.List[PSObject]]::new()
    $emailLower = $Email.ToLower()
    $osLower    = if (-not [string]::IsNullOrWhiteSpace($TargetOS)) { $TargetOS.ToLower() } else { "" }

    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices" +
           "?`$select=id,deviceName,userPrincipalName,emailAddress,serialNumber,operatingSystem,azureADDeviceId" +
           "&`$top=999"

    while ($uri) {
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri

        foreach ($device in $response.value) {

            # Cast all fields to [string] before calling string methods
            # This prevents the op_Addition / method invocation error when
            # Graph returns a PSObject instead of a plain string value
            $upn      = [string]($device.userPrincipalName)
            $mail     = [string]($device.emailAddress)
            $deviceOS = [string]($device.operatingSystem)

            $userMatch = ($upn.ToLower()  -eq $emailLower -or
                          $mail.ToLower() -eq $emailLower)
            $osMatch   = ([string]::IsNullOrWhiteSpace($osLower) -or
                          $deviceOS.ToLower() -eq $osLower)

            if ($userMatch -and $osMatch) {
                $results.Add([PSCustomObject]@{
                    UserEmail         = $Email
                    DeviceSource      = "Intune (Managed Device)"
                    DeviceName        = [string]($device.deviceName)
                    IntuneDeviceId    = [string]($device.id)
                    AzureADDeviceId   = [string]($device.azureADDeviceId)
                    AzureADObjectId   = [string]($device.azureADDeviceId)
                    UserPrincipalName = [string]($device.userPrincipalName)
                    SerialNumber      = [string]($device.serialNumber)
                    OperatingSystem   = [string]($device.operatingSystem)
                })
            }
        }

        $uri = $response.'@odata.nextLink'
    }

    return $results
}


# ─────────────────────────────────────────────────────────────────────────────
# FUNCTION : Get-UserAzureADDevices
# Purpose  : Retrieves Azure AD registered devices for the given email address.
# ─────────────────────────────────────────────────────────────────────────────
function Get-UserAzureADDevices {
    param([Parameter(Mandatory)][string]$Email)

    $results   = [System.Collections.Generic.List[PSObject]]::new()
    $osLower   = if (-not [string]::IsNullOrWhiteSpace($TargetOS)) { $TargetOS.ToLower() } else { "" }

    $userQuery    = "https://graph.microsoft.com/v1.0/users" +
                    "?`$filter=userPrincipalName eq '$Email' or mail eq '$Email'" +
                    "&`$select=id,userPrincipalName,mail"
    $userResponse = Invoke-MgGraphRequest -Method GET -Uri $userQuery

    if (-not $userResponse.value -or $userResponse.value.Count -eq 0) {
        return $results
    }

    foreach ($user in $userResponse.value) {
        $regUri  = "https://graph.microsoft.com/v1.0/users/$($user.id)/registeredDevices" +
                   "?`$select=id,deviceId,displayName,operatingSystem"
        $devices = Invoke-GraphPagedGet -Uri $regUri

        foreach ($d in $devices) {
            $deviceOS = [string]($d.operatingSystem)
            $osMatch  = ([string]::IsNullOrWhiteSpace($osLower) -or
                         $deviceOS.ToLower() -eq $osLower)

            if ($osMatch) {
                $results.Add([PSCustomObject]@{
                    UserEmail         = $Email
                    DeviceSource      = "Azure AD (Registered Device)"
                    DeviceName        = [string]($d.displayName)
                    IntuneDeviceId    = ""
                    AzureADDeviceId   = [string]($d.deviceId)
                    AzureADObjectId   = [string]($d.id)
                    UserPrincipalName = [string]($user.userPrincipalName)
                    SerialNumber      = ""
                    OperatingSystem   = $deviceOS
                })
            }
        }
    }

    return $results
}


# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
try {
    New-Item -Path $ActionLogFile -ItemType File -Force | Out-Null
    Start-Transcript -Path $TranscriptFile -Force | Out-Null

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  Get-UserDevices  |  Sethu Kumar B  |  READ ONLY              " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan

    Write-ActionLog "Script started."
    Write-ActionLog "Script root    : $ScriptRoot"
    Write-ActionLog "Input file     : $InputPath"
    Write-ActionLog "Output CSV     : $OutputFile"
    Write-ActionLog "Transcript     : $TranscriptFile"
    Write-ActionLog "OS filter      : $(if ($TargetOS) { $TargetOS } else { 'All platforms' })"
    Write-ActionLog "-----------------------------------------------------------"

    if (-not (Test-Path $InputPath)) {
        throw "Input file not found: $InputPath"
    }

    Write-ActionLog "Connecting to Microsoft Graph..."
    Connect-ToGraph
    Write-ActionLog "Connected to Microsoft Graph."

    # Read and clean email list — remove blank lines and whitespace
    $emails = Get-Content $InputPath |
              ForEach-Object { $_.Trim() } |
              Where-Object   { -not [string]::IsNullOrWhiteSpace($_) }

    if (-not $emails -or $emails.Count -eq 0) {
        throw "No email addresses found in $InputPath"
    }

    Write-ActionLog ("Found {0} email address(es) in input file." -f $emails.Count)
    Write-ActionLog "-----------------------------------------------------------"

    # ── Master results list — accumulates all rows across all users ───────────
    # Using Generic List throughout — combining two Generic Lists with .AddRange()
    # is always safe. The old @($a + $b) pattern fails with op_Addition when
    # $a or $b contains a single PSObject item instead of an array.
    $AllResults  = [System.Collections.Generic.List[PSObject]]::new()
    $UserCounter = 0
    $TotalUsers  = $emails.Count

    foreach ($email in $emails) {
        $UserCounter++
        Write-ActionLog "[$UserCounter/$TotalUsers] Processing: $email"

        try {
            $intuneDevices = Get-UserIntuneDevices  -Email $email
            $azureDevices  = Get-UserAzureADDevices -Email $email

            # Merge both source lists safely using AddRange — never + operator
            $combined = [System.Collections.Generic.List[PSObject]]::new()
            if ($intuneDevices -and $intuneDevices.Count -gt 0) { $combined.AddRange([System.Collections.Generic.List[PSObject]]$intuneDevices) }
            if ($azureDevices  -and $azureDevices.Count  -gt 0) { $combined.AddRange([System.Collections.Generic.List[PSObject]]$azureDevices)  }

            if ($combined.Count -gt 0) {
                # Deduplicate by DeviceName + DeviceSource
                $deduped = @($combined |
                             Where-Object { -not [string]::IsNullOrWhiteSpace($_.DeviceName) } |
                             Sort-Object DeviceName, DeviceSource -Unique)

                foreach ($item in $deduped) {
                    Write-ActionLog ("  Device: {0,-45} Source: {1}" -f $item.DeviceName, $item.DeviceSource)
                    $AllResults.Add($item)
                }

                Write-ActionLog ("  → {0} device(s) found." -f $deduped.Count)
            }
            else {
                # Placeholder row — user still appears in the CSV with no-device flag
                $AllResults.Add([PSCustomObject]@{
                    UserEmail         = $email
                    DeviceSource      = "No devices found"
                    DeviceName        = ""
                    IntuneDeviceId    = ""
                    AzureADDeviceId   = ""
                    AzureADObjectId   = ""
                    UserPrincipalName = ""
                    SerialNumber      = ""
                    OperatingSystem   = ""
                })
                Write-ActionLog "  → No devices found." -Level WARN
            }
        }
        catch {
            Write-ActionLog "  Error processing $email : $($_.Exception.Message)" -Level ERROR

            # Error placeholder — user still appears in CSV with error flag
            $AllResults.Add([PSCustomObject]@{
                UserEmail         = $email
                DeviceSource      = "ERROR — see log"
                DeviceName        = ""
                IntuneDeviceId    = ""
                AzureADDeviceId   = ""
                AzureADObjectId   = ""
                UserPrincipalName = ""
                SerialNumber      = ""
                OperatingSystem   = ""
            })
        }

        Write-ActionLog "-----------------------------------------------------------"
    }

    # ── Export single combined CSV ────────────────────────────────────────────
    Write-ActionLog "Exporting combined CSV..."

    if ($AllResults.Count -gt 0) {
        try {
            $AllResults | Export-Csv -Path $OutputFile -NoTypeInformation -Encoding UTF8
            $SizeMB = (((Get-Item $OutputFile).Length) / 1MB).ToString("0.00")
            Write-ActionLog "CSV exported successfully."
            Write-ActionLog "  Path  : $OutputFile"
            Write-ActionLog ("  Rows  : {0}  |  Size: {1} MB" -f $AllResults.Count, $SizeMB)
        }
        catch {
            Write-ActionLog "Failed to export CSV: $($_.Exception.Message)" -Level ERROR
        }
    }
    else {
        Write-ActionLog "No results to export." -Level WARN
    }

    # ── Summary ───────────────────────────────────────────────────────────────
    $TotalDevices  = @($AllResults | Where-Object { $_.DeviceSource -notlike "No devices*" -and $_.DeviceSource -notlike "ERROR*" }).Count
    $IntuneCount   = @($AllResults | Where-Object { $_.DeviceSource -eq "Intune (Managed Device)" }).Count
    $AzureCount    = @($AllResults | Where-Object { $_.DeviceSource -eq "Azure AD (Registered Device)" }).Count
    $NoDeviceUsers = @($AllResults | Where-Object { $_.DeviceSource -eq "No devices found" }).Count
    $ErrorUsers    = @($AllResults | Where-Object { $_.DeviceSource -like "ERROR*" }).Count

    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "  COMPLETE — READ ONLY — NO CHANGES MADE                       " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-ActionLog "  Users processed            : $TotalUsers"
    Write-ActionLog "  Total device records       : $TotalDevices"
    Write-ActionLog "  Intune managed devices     : $IntuneCount"
    Write-ActionLog "  Azure AD registered        : $AzureCount"
    Write-ActionLog "  Users with no devices      : $NoDeviceUsers"
    Write-ActionLog "  Users with errors          : $ErrorUsers"
    Write-ActionLog "  Output CSV                 : $OutputFile"
    Write-ActionLog "  Action log                 : $ActionLogFile"
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""

    Disconnect-MgGraph | Out-Null
    Write-ActionLog "Disconnected from Microsoft Graph."
    Write-ActionLog "Script complete."
}
catch {
    Write-ActionLog "Fatal error: $($_.Exception.Message)" -Level ERROR
    throw
}
finally {
    Stop-Transcript | Out-Null
}