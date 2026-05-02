================================================================================
  README - Get-WindowsDeviceInventory-Simple.ps1
================================================================================

SCRIPT NAME
-----------
Get-WindowsDeviceInventory-Simple.ps1

FOLDER NAME
-----------
Get-WindowsDeviceInventory-Simple

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Exports a complete inventory of all Windows managed devices from Microsoft Intune
via the Microsoft Graph API v1.0 (stable endpoint) to a timestamped CSV file.
This is the lightweight version — no per-device enrichment calls, no parallel
processing, no extra complexity. Designed for IT admins who need a fast, clean,
and reliable Windows device export using only the standard Intune device fields.

For additional fields such as RAM, enrolled-by user, or last logged-on user,
use the full version: Get-WindowsDeviceInventory.ps1.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1.  Authenticates to Microsoft Graph API using Client Credentials (no user login)
2.  Fetches ALL Windows managed devices from the v1.0 stable endpoint:
    https://graph.microsoft.com/v1.0/deviceManagement/managedDevices
    (filtered server-side: operatingSystem eq 'Windows')
3.  Handles OData pagination automatically (1000 devices per page — Graph maximum)
4.  Maps OS build numbers to human-readable Windows release names
    (e.g. 10.0.22631 -> "Windows 11 23H2")
5.  Exports 21 clean columns to a timestamped CSV file:

    IDENTITY
      DeviceName, IntuneDeviceID, AzureAD_DeviceID, SerialNumber

    OPERATING SYSTEM
      OperatingSystem, FriendlyOSName, OSVersion, OSBuildNumber

    HARDWARE
      Manufacturer, DeviceModel

    USER
      PrimaryUser_UPN, PrimaryUser_DisplayName

    COMPLIANCE & MANAGEMENT
      ComplianceState, ManagementState, ManagementAgent

    ENROLLMENT
      EnrollmentType, OwnerType

    SECURITY
      IsEncrypted

    TIMESTAMPS
      EnrolledDateTime, LastSyncDateTime, DaysSinceLastSync

6.  Displays a live console summary after export:
      - OS breakdown (Windows 11 / Windows 10 / Windows Server / Other)
      - Compliance breakdown (Compliant / Non-Compliant / Unknown)
      - Encryption status (Encrypted / Not Encrypted)
      - Stale device check-in buckets: >7 / >30 / >60 / >90 / >120 / >180 / >365 days

7.  Saves a full structured log file alongside the CSV for audit purposes

OUTPUT FILES
   - CSV  : <ScriptRoot>\Windows_Inventory_Simple_<timestamp>.csv
   - Log  : <ScriptRoot>\Windows_Inventory_Simple_<timestamp>.log

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- Windows PowerShell 5.1 or PowerShell 7+
- An Azure AD App Registration with a Client Secret
- Appropriate Microsoft Graph API permissions (see below)
- Network access to:
    login.microsoftonline.com
    graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH PERMISSIONS
--------------------------------------------------------------------------------
Permission                               Type        Purpose
----------------------------------------+-----------+-------------------------
DeviceManagementManagedDevices.Read.All  Application Read Intune managed devices

  > Application permission (not delegated) — no user sign-in required.
  > Must be granted Admin Consent in Azure AD.

HOW TO CONFIGURE:
  1. Go to Azure Portal > Azure Active Directory > App Registrations
  2. Create or select your App Registration
  3. Go to API Permissions > Add Permission > Microsoft Graph > Application
  4. Add: DeviceManagementManagedDevices.Read.All
  5. Click "Grant Admin Consent"
  6. Under Certificates & Secrets, create a Client Secret and copy the value

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1: Open the script file in a text editor or VS Code
Step 2: Fill in the three required values at the top of the script:

    $TenantID     = "your-tenant-id-here"
    $ClientID     = "your-client-id-here"
    $ClientSecret = "your-client-secret-here"

Step 3: (Optional) Adjust page size if needed:
    $PageSize = 1000   <- default and recommended
    Reduce to 100 only if you experience throttling in very large environments.

Step 4: Open PowerShell (Run as Administrator recommended)
Step 5: Navigate to the script folder:

    cd "C:\Path\To\Get-WindowsDeviceInventory-Simple"

Step 6: Run the script:

    .\Get-WindowsDeviceInventory-Simple.ps1

  > If execution policy blocks the script, run first:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console: Live progress per page fetched, then a full summary at completion.

CSV file example (Windows_Inventory_Simple_20260327_143022.csv):

  DeviceName  | FriendlyOSName   | ComplianceState | IsEncrypted | DaysSinceLastSync
  ------------|------------------|-----------------|-------------+------------------
  DESKTOP-001 | Windows 11 23H2  | compliant       | True        | 1.2
  LAPTOP-042  | Windows 10 22H2  | nonCompliant    | False       | 45.7
  SERVER-SRV1 | Windows Server.. | compliant       | True        | 3.0

Console Summary example:
  Total Windows devices     : 1,240
  Windows 11                : 890
  Windows 10                : 320
  Windows Server            : 28
  Compliant                 : 1,100
  Non-Compliant             : 98
  Encrypted                 : 1,190
  Not synced > 30 days      : 42
  Not synced > 90 days      : 11

Log file: Full timestamped audit trail saved alongside the CSV.

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Uses Graph API v1.0 (stable) — NOT beta. More reliable for production use.
- $filter and $select cannot be combined on the v1.0 managedDevices endpoint
  (causes HTTP 400). This script uses $filter only; column shaping is done
  client-side. This is by design, not a limitation.
- Page size is set to 1000 (Graph API maximum) for fastest retrieval.
- FriendlyOSName covers all Windows 10, Windows 11, and Windows Server releases
  up to Windows 11 26H2. Unknown builds fall back to "Windows (Build XXXXX)".
- DaysSinceLastSync is calculated at script runtime — it reflects age at time
  of export, not at time of last sync.
- This script does NOT wipe credentials from memory post-run (lightweight version).
  For environments requiring secure credential handling, use the full version.
- Always test in a non-production tenant first.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
ISSUE: "Authentication failed"
FIX  : Verify TenantID, ClientID, and ClientSecret are correct.
       Ensure Admin Consent is granted in Azure AD.

ISSUE: HTTP 400 Bad Request on device fetch
FIX  : Do not add $select to the URI. This endpoint does not support combining
       $filter and $select. The script is already coded correctly — check for
       any manual modifications to the URI.

ISSUE: CSV is empty / 0 devices returned
FIX  : Verify the App Registration has DeviceManagementManagedDevices.Read.All
       with Admin Consent granted. Confirm Windows devices are enrolled in Intune.

ISSUE: Script execution blocked
FIX  : Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

ISSUE: FriendlyOSName shows "Windows (Build XXXXX)"
FIX  : The build number is newer than this script's mapping table. The script
       still exports correctly — update the ConvertTo-FriendlyOSName function
       with the new build threshold when Microsoft releases a new Windows version.

ISSUE: Log file not created
FIX  : Run PowerShell as Administrator, or ensure write access to $PSScriptRoot.

ISSUE: Throttling / slow retrieval on large tenants
FIX  : Reduce $PageSize from 1000 to 100 at the top of the script. More pages
       will be fetched but each request will be lighter.

ISSUE: DaysSinceLastSync shows "N/A"
FIX  : The device has never synced, or the lastSyncDateTime field is empty in
       Intune. This is expected for newly enrolled or broken MDM devices.

================================================================================
  GUMROAD LISTING DETAILS
================================================================================

GUMROAD LISTING TITLE
---------------------
Export Windows Device Inventory from Intune to CSV — PowerShell Graph API Script (Simple / Lightweight)

GUMROAD PRODUCT DESCRIPTION
-----------------------------
Get a clean, complete export of all your Windows managed devices from Microsoft
Intune in minutes — no modules to install, no complex setup, no interactive
login required.

This lightweight PowerShell script connects to Microsoft Graph API v1.0 using
secure app-only authentication, fetches every Windows device across your tenant
with automatic pagination, and exports 21 key fields to a ready-to-use CSV file.

After export, the script prints a live summary directly in the console showing
OS breakdown, compliance status, encryption coverage, and stale device check-in
counts across 7 staleness thresholds — giving you instant visibility without
opening the CSV.

Perfect for IT administrators, Microsoft 365 consultants, and Intune engineers
who need a reliable, auditable, and repeatable Windows device inventory export
that just works.

KEY FEATURES
------------
- App-only authentication — no interactive user login required
- Uses Graph API v1.0 stable endpoint (not beta)
- Server-side Windows filter — only Windows devices fetched
- Full OData pagination — retrieves all devices regardless of count
- 21 exported columns covering identity, OS, hardware, user, compliance,
  encryption, enrollment type, and timestamps
- OS build number to human-readable name mapping:
  Windows 10 (all versions), Windows 11 (all versions), Windows Server
- DaysSinceLastSync calculated automatically at export time
- Enrollment type raw values mapped to plain-English descriptions
- Console summary: OS split, compliance, encryption, and 7 stale sync buckets
- Structured log file for every run — full audit trail
- No third-party PowerShell modules required
- Clean, well-commented code — easy to read and customise

WHO THIS SCRIPT IS FOR
----------------------
- IT Administrators managing Windows devices in Microsoft Intune
- Microsoft 365 / Endpoint Management Consultants
- System Engineers needing fast, repeatable device inventory exports
- MSPs managing Windows fleets across multiple Intune tenants
- Security and compliance teams auditing encryption and compliance posture
- Teams preparing for Intune migrations, audits, or device clean-up projects

SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Windows Device Inventory, Graph API, CSV Export,
Managed Devices, Endpoint Management, Microsoft 365, IT Automation,
Device Compliance, Encryption Audit, Stale Devices, Azure AD, Intune Script,
Windows 10, Windows 11, Device Management, MEM, MDM, Intune Reporting

BUYER INSTRUCTIONS
------------------
1. Download and extract the ZIP file
2. Open Get-WindowsDeviceInventory-Simple.ps1 in any text editor or VS Code
3. Fill in your TenantID, ClientID, and ClientSecret at the top of the script
4. Run the script from PowerShell
5. CSV and log file are saved automatically in the same folder as the script
6. Full setup steps and troubleshooting are included in this README.txt file

COMMON QUESTIONS / FAQ
-----------------------
Q: Do I need to install any PowerShell modules?
A: No. The script uses only built-in PowerShell cmdlets and direct REST API
   calls. Nothing to install.

Q: Does this work with PowerShell 5.1 and PowerShell 7?
A: Yes. Compatible with both Windows PowerShell 5.1 and PowerShell 7+.

Q: What is the difference between this and the full version?
A: This lightweight version exports the 21 standard fields available from the
   managedDevices collection endpoint in a single pass — no extra API calls.
   The full version adds fields like RAM, enrolled-by user, and last logged-on
   user, but requires one additional API call per device (slower on large tenants).

Q: Can this export devices from multiple tenants?
A: One tenant per run. Update the credential variables and run again for each
   tenant. Each run produces its own timestamped CSV and log file.

Q: What if I have thousands of devices?
A: Pagination is handled automatically. All devices are retrieved regardless of
   count. Page size defaults to 1000 (Graph API maximum) for fastest retrieval.

Q: Why does my FriendlyOSName show "Windows (Build XXXXX)"?
A: The build number is newer than the script's current mapping table. The export
   is still complete and accurate — update the ConvertTo-FriendlyOSName function
   when Microsoft releases a new Windows version.

Q: Does this use a stable or beta Graph endpoint?
A: It uses the stable v1.0 endpoint — not beta. This makes it more reliable for
   production and scheduled automation use.

Q: Can I schedule this script to run automatically?
A: Yes. It runs fully unattended with no user interaction. Use Windows Task
   Scheduler or any automation platform to schedule regular inventory exports.

================================================================================
  Author  : Sethu Kumar B
  Version : 1.0
  Date    : March 2026
================================================================================
