================================================================================
  README — Export-DeviceInventoryWithCleanPolicy.ps1
================================================================================

SCRIPT NAME
  Export-DeviceInventoryWithCleanPolicy.ps1

VERSION
  1.1

AUTHOR
  Sethu Kumar B

FOLDER NAME
  Export-DeviceInventoryWithCleanPolicy

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Exports a complete device inventory across Intune, Azure AD, and Windows
Autopilot into a colour-coded multi-sheet Excel workbook. Each device receives
a sync verdict (health status) and a clean policy recommendation based on
configurable inactivity thresholds — helping admins identify stale, inactive,
and deletable devices at a glance.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
  1. Authenticates to Microsoft Graph API using App Registration credentials.
  2. Fetches all devices from three sources:
       - Intune managed devices (beta endpoint)
       - Azure AD registered/joined devices (beta endpoint)
       - Windows Autopilot device identities (beta endpoint)
  3. For each device, calculates:
       - Days since last sync / sign-in / contact
       - Sync Verdict : Healthy / Stale / Critical
       - Clean Policy Recommendation based on inactivity thresholds:
           Active          — within 90 days
           Review >90d     — not reported in 90+ days
           Pending >120d   — not reported in 120+ days
           Can Delete >180d — not reported in 180+ days
  4. Exports a colour-coded Excel workbook with 4 sheets:
       - Summary         — device counts by source and health bucket
       - Intune Devices  — full Intune inventory with verdict
       - Azure AD Devices — full Azure AD inventory with verdict
       - Autopilot Devices — full Autopilot inventory with verdict
  5. Falls back to 3 separate CSV files if ImportExcel module is unavailable.
  6. Generates a timestamped log file alongside the output.

READ ONLY — this script makes no changes to any device or tenant object.

--------------------------------------------------------------------------------
OUTPUT FILES
--------------------------------------------------------------------------------
  File                                         Description
  -------------------------------------------  --------------------------------
  AllDeviceInventory_[timestamp].xlsx          Colour-coded Excel workbook
  AllDeviceInventory_[timestamp].log           Script run log

  Fallback (if ImportExcel unavailable):
  Intune_[timestamp].csv                       Intune devices CSV
  AzureAD_[timestamp].csv                      Azure AD devices CSV
  Autopilot_[timestamp].csv                    Autopilot devices CSV

  All files saved to the same folder as the script ($PSScriptRoot).

--------------------------------------------------------------------------------
EXCEL WORKBOOK — SHEET DETAILS
--------------------------------------------------------------------------------
  Sheet: Summary
    Source | TotalDevices | Healthy | Stale | Critical |
    Review >90d | Pending >120d | Can Delete >180d
    Colour-coded per column — green/amber/red/orange/dark red.

  Sheet: Intune Devices
    DeviceName, IntuneDeviceId, AzureADDeviceId, SerialNumber,
    OperatingSystem, OSVersion, Model, Manufacturer,
    UserPrincipalName, UserDisplayName, EnrolledDateTime,
    LastSyncDateTime, DaysSinceLastSync, SyncVerdict,
    CleanPolicyRecommendation, ComplianceState, ManagementState,
    JoinType, IsEncrypted, IsSupervised, ManagedDeviceOwnerType

  Sheet: Azure AD Devices
    DisplayName, AzureADObjectId, AzureADDeviceId, OperatingSystem,
    OSVersion, TrustType, IsCompliant, IsManaged, ProfileType,
    RegisteredDateTime, ApproximateLastSignIn, DaysSinceLastSignIn,
    SyncVerdict, CleanPolicyRecommendation, AccountEnabled,
    DeviceOwnership, EnrollmentType, ManagementType,
    OnPremisesSyncEnabled, OnPremisesLastSyncDateTime

  Sheet: Autopilot Devices
    SerialNumber, AutopilotDeviceId, ManagedDeviceId, AzureADDeviceId,
    Model, Manufacturer, GroupTag, PurchaseOrderIdentifier,
    UserPrincipalName, EnrollmentState, LastContactedDateTime,
    DaysSinceLastContact, SyncVerdict, CleanPolicyRecommendation,
    ProfileAssignmentStatus, RemediationState

--------------------------------------------------------------------------------
COLOUR CODING LEGEND
--------------------------------------------------------------------------------
  Row / Cell Colour   Meaning
  ------------------  ----------------------------------------------------------
  White               Active — device reported within threshold
  Light Yellow        Review Required — not reported >90 days
  Amber / Orange      Pending Deletion — not reported >120 days
  Dark Red            Can Be Deleted — not reported >180 days (Clean Policy)
  Red                 Critically stale — exceeds critical sync threshold
  Amber               Stale — exceeds warn sync threshold

  Dark Navy header row on all sheets.
  Driver columns (SyncVerdictColor, CleanPolicyColor) auto-hidden in output.

--------------------------------------------------------------------------------
CONFIGURABLE THRESHOLDS
--------------------------------------------------------------------------------
  Variable       Default   Meaning
  -----------    -------   ---------------------------------------------------
  $WarnDays      14        Amber sync verdict — stale but not critical
  $CriticalDays  30        Red sync verdict — critically stale
  $CleanWarn1    90        Review Required clean policy flag
  $CleanWarn2    120       Pending Deletion clean policy flag
  $CleanDelete   180       Can Be Deleted clean policy flag

  All thresholds are in days. Edit the CONFIG block at the top of the script.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
  - PowerShell 5.1 or later
  - ImportExcel module (auto-installed if missing):
      Install-Module ImportExcel -Scope CurrentUser
  - Azure AD App Registration with permissions listed below
  - No Microsoft Graph PowerShell SDK required — uses direct REST API calls

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
  Permission                                   Type        Purpose
  -------------------------------------------  ----------  --------------------
  DeviceManagementManagedDevices.Read.All      Application  Intune devices
  DeviceManagementServiceConfig.Read.All       Application  Autopilot devices
  Device.Read.All                              Application  Azure AD devices

  NOTE: All permissions are Application type (not Delegated).
        Grant admin consent in Azure Portal after adding permissions.

--------------------------------------------------------------------------------
HOW TO RUN
--------------------------------------------------------------------------------
  STEP 1 — Fill in credentials
    Open the script. In the CONFIG block at the top, set:
      $TenantId     = "your-tenant-id"
      $ClientId     = "your-app-client-id"
      $ClientSecret = "your-app-client-secret"

  STEP 2 — (Optional) Adjust thresholds
    Edit $WarnDays, $CriticalDays, $CleanWarn1, $CleanWarn2, $CleanDelete
    to match your organisation's device management policy.

  STEP 3 — Run the script
    Open PowerShell and run:
      .\Export-DeviceInventoryWithCleanPolicy.ps1

  STEP 4 — Open the Excel workbook
    Find AllDeviceInventory_[timestamp].xlsx in the script folder.
    Start with the Summary sheet for a health overview.
    Use AutoFilter on each sheet to sort/filter by verdict or clean policy.

--------------------------------------------------------------------------------
EXPECTED OUTPUT — SUMMARY EXAMPLE
--------------------------------------------------------------------------------
  Source     | Total | Healthy | Stale | Critical | >90d | >120d | >180d
  -----------|-------|---------|-------|----------|------|-------|------
  Intune     | 850   | 720     | 85    | 45       | 30   | 12    | 8
  Azure AD   | 920   | 780     | 90    | 50       | 35   | 15    | 10
  Autopilot  | 200   | 160     | 25    | 15       | 10   | 5     | 3

  (Values are illustrative — actual output depends on your tenant.)

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
  - Script uses beta Graph API endpoints to access all available device fields.
    Beta endpoints are not guaranteed stable by Microsoft but are widely used
    in production Intune tooling.
  - Auth uses direct REST (Invoke-RestMethod) with client credentials — no
    Graph PowerShell SDK required. This is intentional for portability.
  - Credentials are cleared from memory in the finally block after every run.
    Never hardcode production secrets in shared script copies.
  - ImportExcel requires .NET drawing libraries. If running on PowerShell Core
    (non-Windows), confirm System.Drawing support is available.
  - "Never Synced" devices (no date on record) are flagged as Critical and
    assigned the Review Required clean policy by default.
  - Large tenants (5000+ devices) may take several minutes due to Graph
    pagination across all three endpoints.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------
  Problem : "Token acquisition failed"
  Fix     : Verify TenantId, ClientId, ClientSecret are correct.
            Confirm App Registration exists and secret has not expired.

  Problem : "Insufficient privileges" error from Graph
  Fix     : Confirm all three API permissions are added and admin consent
            is granted in Azure Portal > App registrations > API permissions.

  Problem : ImportExcel install fails, falls back to CSV
  Fix     : Run manually: Install-Module ImportExcel -Scope CurrentUser -Force
            Requires internet access. On locked-down machines, install offline.

  Problem : Excel file opens but rows show no colour
  Fix     : Confirm ImportExcel version is 7.x or later.
            Run: Update-Module ImportExcel

  Problem : Autopilot sheet is empty
  Fix     : Confirm DeviceManagementServiceConfig.Read.All permission is
            granted. Autopilot data requires this separate permission.

  Problem : DaysSinceLastSync shows "N/A" for many devices
  Fix     : Device has never synced or date field is null in Graph. Expected
            for newly enrolled or never-contacted Autopilot entries.

  Problem : Script runs but Excel file is locked/corrupted
  Fix     : Ensure no other process has the output file open during the run.
            Delete the partial file and re-run.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
  Intune, Azure AD & Autopilot – Device Inventory & Clean Policy Tool
  (PowerShell + Graph API + Excel)

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
  Stop guessing which devices are safe to delete. This PowerShell script pulls
  your complete device inventory from Intune, Azure AD, and Windows Autopilot
  and delivers a colour-coded Excel workbook in one run — with sync health
  verdicts and clean policy recommendations built in.

  Every device is rated: Active, Review Required, Pending Deletion, or
  Can Be Deleted — based on days since last sync or sign-in. All thresholds
  are configurable to match your organisation's retention policy.

  No Graph SDK required. No manual portal clicking. Just run the script,
  open the Excel file, and know exactly where your device estate stands.

  Built for IT admins and endpoint engineers who manage large Microsoft
  environments and need a fast, repeatable device hygiene audit tool.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
  - Pulls devices from ALL three Microsoft sources in one run:
      Intune managed devices, Azure AD registered devices,
      Windows Autopilot identities
  - Sync Verdict per device: Healthy / Stale / Critical
  - Clean Policy Recommendation per device:
      Active / Review >90d / Pending >120d / Can Delete >180d
  - Colour-coded Excel workbook — dark navy headers, green/amber/red/dark-red
    row highlighting driven by sync and clean policy status
  - Summary sheet with device counts by source and health bucket
  - All thresholds configurable — no code change needed, edit CONFIG block
  - Auto-installs ImportExcel if not present
  - Falls back to CSV export if Excel module unavailable
  - No Graph PowerShell SDK required — pure REST API
  - Credentials cleared from memory after every run
  - Read-only — zero changes made to any tenant object
  - PowerShell 5.1 compatible

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
  - IT Administrators managing Microsoft Intune and Azure AD / Entra ID
  - Endpoint Engineers running periodic device hygiene audits
  - Modern Workplace teams preparing for device clean-up campaigns
  - Security teams reviewing stale or unmanaged device exposure
  - Anyone responsible for Autopilot device lifecycle management

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
  Intune, Azure AD, Autopilot, Device Inventory, Clean Policy, Stale Devices,
  Microsoft Graph API, PowerShell, Excel Report, Endpoint Management,
  Device Hygiene, ImportExcel, Entra ID, Device Cleanup, MDM Audit,
  Modern Workplace, Device Lifecycle, Sync Verdict, Inactive Devices

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
  1. Download and extract the ZIP file.
  2. Open Export-DeviceInventoryWithCleanPolicy.ps1 in any text editor.
  3. Fill in TenantId, ClientId, and ClientSecret in the CONFIG block.
  4. Optionally adjust threshold values to match your clean policy.
  5. Run from PowerShell:
       .\Export-DeviceInventoryWithCleanPolicy.ps1
  6. Open AllDeviceInventory_[timestamp].xlsx in the script folder.
  7. Review the Summary sheet first, then drill into individual sheets.

  Refer to PREREQUISITES and HOW TO RUN sections for full setup details
  including Graph API permission requirements.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
  Q: Does this script make any changes to my tenant?
  A: No. Completely read-only. No devices, users, or settings are modified.

  Q: Do I need the Microsoft Graph PowerShell SDK installed?
  A: No. This script uses direct REST API calls. No SDK required.

  Q: Can I change the inactivity thresholds?
  A: Yes. Edit $CleanWarn1, $CleanWarn2, and $CleanDelete in the CONFIG
     block at the top of the script. No other changes needed.

  Q: What happens if ImportExcel is not installed?
  A: The script attempts to install it automatically. If that fails (e.g.,
     no internet access), it falls back to exporting 3 separate CSV files.

  Q: How is "days since last sync" calculated?
  A: Script subtracts the device's last sync / sign-in / contact date from
     the current UTC time and returns the result as a whole number of days.

  Q: Why does the script use the beta Graph API endpoint?
  A: The beta endpoint exposes additional device fields (joinType, isEncrypted,
     remediationState, etc.) not available in v1.0. Widely used in production
     Intune tooling despite the beta label.

  Q: Can I run this for Autopilot only?
  A: Not directly — all three sources run together. The Excel workbook has
     separate sheets per source so you can focus on Autopilot alone.

  Q: Is PowerShell 7 supported?
  A: Yes. Script requires PowerShell 5.1 or later. PowerShell 7 is supported.

================================================================================
  Sethu Kumar B
================================================================================
