================================================================================
  README — Get-IntuneAndAADDevicesByUser.ps1
================================================================================

SCRIPT NAME
  Get-IntuneAndAADDevicesByUser.ps1

VERSION
  1.1

AUTHOR
  Sethu Kumar B

FOLDER NAME
  Get-IntuneAndAADDevicesByUser

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Retrieves all Intune managed devices and Azure AD registered devices associated
with one or more users. Accepts a plain text file of email addresses as input
and exports a single combined CSV report covering all users.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
  1. Reads a list of user email addresses from users.txt (one email per line).
  2. For each user:
       - Queries Intune managedDevices endpoint for managed devices.
       - Queries Azure AD registeredDevices endpoint for registered devices.
  3. Deduplicates results by DeviceName + DeviceSource.
  4. Writes ALL users into ONE combined CSV file.
       - Users with no devices appear as a placeholder row.
       - Users that caused errors appear with an error flag row.
  5. Generates:
       - Combined CSV  : UserDevices_[yyyyMMdd_HHmmss].csv
       - Action log    : Get-UserDevices-Actions_[yyyyMMdd_HHmmss].log
       - Full transcript: Get-UserDevices-Transcript_[yyyyMMdd_HHmmss].log
  6. All output files saved to the same folder as the script ($PSScriptRoot).

READ ONLY — this script makes no changes to any device or user object.

--------------------------------------------------------------------------------
OUTPUT COLUMNS
--------------------------------------------------------------------------------
  UserEmail         — Input email address used for the lookup
  DeviceSource      — "Intune (Managed Device)" or "Azure AD (Registered Device)"
  DeviceName        — Device display name
  IntuneDeviceId    — Intune managed device GUID (blank for Azure AD-only devices)
  AzureADDeviceId   — Azure AD deviceId GUID
  AzureADObjectId   — Azure AD object ID
  UserPrincipalName — UPN returned by Graph
  SerialNumber      — Hardware serial number (Intune devices only)
  OperatingSystem   — OS name (e.g., Windows, macOS, iOS)

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
  - PowerShell 5.1 or later
  - Microsoft Graph PowerShell SDK installed:
      Install-Module Microsoft.Graph -Scope CurrentUser
  - Azure AD App Registration with the permissions listed below
  - A users.txt file in the same folder as the script (one email per line)

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
  Permission                              Type        Purpose
  --------------------------------------  ----------  --------------------------
  DeviceManagementManagedDevices.Read.All Application  Read Intune devices
  Device.Read.All                         Application  Read Azure AD devices
  User.Read.All                           Application  Resolve user objects

  NOTE: All permissions are Application type (not Delegated).
        Grant admin consent in Azure Portal after adding permissions.

--------------------------------------------------------------------------------
HOW TO RUN
--------------------------------------------------------------------------------
  STEP 1 — Fill in credentials
    Open the script and update the param block at the top:
      $TenantId     = "your-tenant-id"
      $ClientId     = "your-app-client-id"
      $ClientSecret = "your-app-client-secret"

  STEP 2 — Prepare input file
    Create users.txt in the same folder as the script.
    Add one email address per line. Example:
      john.doe@company.com
      jane.smith@company.com

  STEP 3 — (Optional) Set OS filter
    Default TargetOS is "Windows". To retrieve all platforms, set:
      $TargetOS = ""
    Supported values: Windows, macOS, iOS, Android, or leave blank for all.

  STEP 4 — Run the script
    Open PowerShell and run:
      .\Get-IntuneAndAADDevicesByUser.ps1

  STEP 5 — Check output
    Open the generated CSV file in Excel or any CSV viewer.
    Check the action log for per-user processing details.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
  File                                       Description
  ----------------------------------------   -----------------------------------
  UserDevices_[timestamp].csv                Combined device report for all users
  Get-UserDevices-Actions_[timestamp].log    Per-user action log with device list
  Get-UserDevices-Transcript_[timestamp].log Full PowerShell session transcript

  Summary printed at end of run:
    - Users processed
    - Total device records found
    - Intune managed device count
    - Azure AD registered device count
    - Users with no devices
    - Users with errors

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
  - The script uses Application permissions. Never share ClientSecret in plain
    text. Store credentials securely (e.g., Azure Key Vault) in production.
  - AzureADObjectId and AzureADDeviceId will be identical for Intune-sourced
    rows because the Intune API does not expose a separate AAD Object ID.
    The true AAD Object ID is only available via the Azure AD devices endpoint.
  - TargetOS filter is case-insensitive but must match the OS value returned
    by Graph exactly (e.g., "Windows" not "Windows 10").
  - Users that appear in users.txt but cannot be found in Azure AD will show
    as a no-device placeholder row — not an error.
  - Large environments (1000+ devices) may take several minutes due to
    Graph API pagination.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------
  Problem : "Input file not found"
  Fix     : Confirm users.txt exists in the same folder as the script.

  Problem : "Insufficient privileges" error from Graph
  Fix     : Verify all three API permissions are granted and admin consent
            is applied in Azure Portal > App registrations > API permissions.

  Problem : Device count looks low
  Fix     : Check TargetOS filter. Set $TargetOS = "" to return all platforms.

  Problem : op_Addition error or PSObject method invocation error
  Fix     : This was resolved in v1.1. Confirm you are running v1.1 or later.

  Problem : Users show "No devices found" but devices exist in Intune
  Fix     : Confirm the email in users.txt matches the UPN or emailAddress
            field in Intune exactly (case-insensitive match is applied).

  Problem : ClientSecret authentication fails
  Fix     : Check App Registration > Certificates & secrets. Confirm the
            secret has not expired. Generate a new secret if needed.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
  Intune & Azure AD – User Device Lookup Tool (PowerShell + Graph API)

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
  Quickly find every device associated with any user — across both Microsoft
  Intune and Azure AD — using a simple PowerShell script powered by the
  Microsoft Graph API.

  Just drop a list of email addresses into a text file, run the script, and
  get a clean, deduplicated CSV report covering all users in one file.
  Every user is accounted for — even those with no devices or lookup errors.

  Built for IT admins and endpoint engineers who need fast, accurate device
  inventory without clicking through the Intune portal user by user.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
  - Queries BOTH Intune managed devices and Azure AD registered devices
  - Bulk lookup — process any number of users from a single text file
  - Single combined CSV output — all users in one file
  - Automatic deduplication by device name and source
  - Placeholder rows for users with no devices (no missing entries)
  - Error rows included so every input address appears in the output
  - Optional OS filter (Windows, macOS, iOS, Android, or all platforms)
  - Full action log and PowerShell transcript generated automatically
  - Read-only — zero changes made to any tenant object
  - PowerShell 5.1 compatible

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
  - IT Administrators managing Microsoft Intune and Azure AD environments
  - Endpoint Engineers handling device audits or user offboarding
  - Modern Workplace teams needing bulk user-device inventory
  - Help Desk L2/L3 staff investigating device assignment issues
  - Anyone who needs a fast device report without Intune portal access

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
  Intune, Azure AD, Microsoft Graph API, PowerShell, Device Inventory,
  Endpoint Management, User Devices, MDM, Graph PowerShell, Bulk Export,
  Device Report, Modern Workplace, Microsoft Endpoint Manager, CSV Export,
  Entra ID, Device Lookup

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
  1. Download the ZIP file from Gumroad.
  2. Extract contents to a folder of your choice.
  3. Open Get-IntuneAndAADDevicesByUser.ps1 in any text editor.
  4. Fill in TenantId, ClientId, and ClientSecret in the param block.
  5. Create users.txt in the same folder with one email address per line.
  6. Run the script from PowerShell:
       .\Get-IntuneAndAADDevicesByUser.ps1
  7. Open the generated CSV file to view results.

  Refer to the PREREQUISITES and HOW TO RUN sections above for full setup
  instructions including Graph API permission requirements.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
  Q: Does this script make any changes to my tenant?
  A: No. It is completely read-only. No devices, users, or settings are modified.

  Q: How many users can I process at once?
  A: No hard limit. Add as many email addresses as needed in users.txt.
     Runtime will increase with user count and device volume.

  Q: Do I need a paid Intune license?
  A: You need appropriate Microsoft 365 / Intune licensing for your tenant.
     The script itself does not require any additional license.

  Q: Can I run this for a single user instead of a list?
  A: Yes. Add one email address to users.txt and run normally.

  Q: Why does a user appear in the CSV with no device data?
  A: Either the user has no devices enrolled, or the email in users.txt
     does not match the UPN or emailAddress field in Intune/Azure AD.

  Q: Does this work with Entra ID (formerly Azure AD)?
  A: Yes. Azure AD and Entra ID refer to the same service. This script
     is fully compatible.

  Q: Is PowerShell 7 supported?
  A: The script requires PowerShell 5.1 or later. PowerShell 7 is supported.

================================================================================
  Sethu Kumar B
================================================================================
