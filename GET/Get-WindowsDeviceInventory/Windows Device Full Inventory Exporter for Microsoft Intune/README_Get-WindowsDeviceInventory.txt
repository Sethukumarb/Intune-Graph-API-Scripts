================================================================================
  README - Get-WindowsDeviceInventory.ps1
================================================================================

SCRIPT NAME
-----------
Get-WindowsDeviceInventory.ps1

FOLDER NAME
-----------
Get-WindowsDeviceInventory

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Exports the most complete possible inventory of all Windows managed devices
from Microsoft Intune via the Microsoft Graph API beta endpoint. This is the
full version — it uses parallel runspace processing to enrich every device with
the last logged-on user, and exports 50+ fields covering identity, OS, hardware,
user, enrollment, compliance, security, Exchange, and timestamps.

Use this script when you need maximum field coverage for audits, migrations,
compliance reviews, or detailed endpoint reporting.

For a faster, simpler export using only standard fields, use the lightweight
version: Get-WindowsDeviceInventory-Simple.ps1

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
STEP 1 — Authentication
  Connects to Microsoft Graph API using Client Credentials (no user login).

STEP 2 — Fetch All Windows Devices
  Retrieves ALL Windows managed devices from the beta endpoint:
  https://graph.microsoft.com/beta/deviceManagement/managedDevices
  - Server-side filter: operatingSystem eq 'Windows'
  - $filter only (no $select) — avoids HTTP 400 on this endpoint
  - Full OData pagination (1000 devices per page — Graph maximum)

STEP 3 — Parallel Last-Logon Enrichment
  Runs a separate per-device API call for each device to retrieve the
  last logged-on user (usersLoggedOn property — not available on collection).
  Uses PowerShell Runspaces for true parallel processing:
  - PS 5.1 compatible (no PS 7 ForEach-Object -Parallel required)
  - Configurable thread pool ($MaxParallelJobs, default 10, max 20)
  - Progress reported every 100 devices

STEP 4 — Shape + Export
  Maps all raw device objects to clean, labelled CSV columns.
  Exports timestamped CSV to script folder (or custom $OutputFolder).

STEP 5 — Console Summary
  Prints OS breakdown, compliance, encryption, Autopilot, and join type counts.

OUTPUT FILES
  - CSV  : <OutputFolder>\Windows_Device_Inventory_<timestamp>.csv
  - Log  : <ScriptRoot>\Windows_Device_Inventory_<timestamp>.log

COLUMNS EXPORTED (50+)
  IDENTITY
    DeviceName, IntuneDeviceID, AzureAD_DeviceID, SerialNumber

  OPERATING SYSTEM
    OperatingSystem, FriendlyOSName, OSVersion_Full, OSBuildNumber, SKUFamily

  HARDWARE
    Manufacturer, DeviceModel, RAM_GB, TotalStorage_GB, FreeStorage_GB,
    ProcessorArchitecture, WiFi_MAC, Ethernet_MAC

  PRIMARY USER
    PrimaryUser_UPN, PrimaryUser_DisplayName, PrimaryUser_AADObjectID,
    PrimaryUser_Email

  LAST LOGGED ON USER (parallel enrichment)
    LastLoggedOn_UserID

  ENROLLED BY
    EnrolledBy_UPN, EnrolledBy_DisplayName, EnrolledBy_UPN_Explicit

  ENROLLMENT DETAILS
    EnrollmentType, EnrollmentType_Raw, JoinType, JoinType_Raw,
    AutopilotEnrolled, DeviceRegistrationState, EnrolledDateTime

  OWNERSHIP
    OwnerType, DeviceCategory, IsSharedDevice

  COMPLIANCE
    ComplianceState, ComplianceGracePeriodExpiry

  MANAGEMENT
    ManagementState, ManagementAgent, ManagementCertExpiry, IsSupervised

  SECURITY
    IsEncrypted, BootstrapTokenEscrowed, DeviceGuard_VBS_HWRequirement,
    DeviceGuard_VBS_State, DeviceGuard_CredentialGuard, PartnerThreatState

  EXCHANGE / EAS
    EAS_Activated, EAS_ActivationDateTime, EAS_AccessState,
    EAS_AccessStateReason

  TIMESTAMPS
    LastSyncDateTime, DaysSinceLastSync

  NOTES
    DeviceNotes

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
----------------------------------------+-----------+---------------------------
DeviceManagementManagedDevices.Read.All  Application Device inventory + last logon
DeviceManagementConfiguration.Read.All  Application Enrollment profiles
Device.Read.All                          Application AAD device join type info

  > All are Application permissions (not delegated) — no user sign-in required.
  > All three must be granted Admin Consent in Azure AD.

HOW TO CONFIGURE:
  1. Go to Azure Portal > Azure Active Directory > App Registrations
  2. Create or select your App Registration
  3. Go to API Permissions > Add Permission > Microsoft Graph > Application
  4. Add all three permissions listed above
  5. Click "Grant Admin Consent"
  6. Under Certificates & Secrets, create a Client Secret and copy the value

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1: Open the script file in a text editor or VS Code

Step 2: Fill in the three required credential values at the top:

    $TenantID     = "your-tenant-id-here"
    $ClientID     = "your-client-id-here"
    $ClientSecret = "your-client-secret-here"

Step 3: (Optional) Configure performance settings:

    $MaxParallelJobs = 10    <- Parallel threads for last-logon enrichment
                                Safe default: 10. Maximum: 20.
                                Increase for faster runs on large fleets.
                                Decrease if you hit Graph 429 throttling errors.

    $PageSize = 1000         <- Devices per API page. 1000 = Graph maximum.
                                Reduce to 100 only if throttling occurs.

Step 4: (Optional) Set a custom output folder:

    $OutputFolder = "C:\Reports\Intune"   <- Leave empty to save next to script

Step 5: Open PowerShell (Run as Administrator recommended)

Step 6: Navigate to the script folder:

    cd "C:\Path\To\Get-WindowsDeviceInventory"

Step 7: Run the script:

    .\Get-WindowsDeviceInventory.ps1

  > If execution policy blocks the script, run first:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console: Live step-by-step progress including per-page fetch count, parallel
enrichment progress (every 100 devices), and a full summary at completion.

CSV file example (Windows_Device_Inventory_20260327_143022.csv):

  DeviceName  | FriendlyOSName  | RAM_GB | IsEncrypted | LastLoggedOn_UserID
  ------------|-----------------|--------|-------------|--------------------
  DESKTOP-001 | Windows 11 23H2 | 16 GB  | True        | john.doe@contoso.com
  LAPTOP-042  | Windows 10 22H2 | 8 GB   | False       | jane.smith@contoso.com
  SERVER-001  | Win Server 2022 | 32 GB  | True        | No Logon Data

Console Summary example:
  Total Windows devices     : 1,240
  Windows 11                : 890
  Windows 10                : 320
  Compliant                 : 1,100
  Non-Compliant             : 98
  Encrypted                 : 1,190
  Not Encrypted             : 50
  Autopilot Enrolled        : 740
  Azure AD Joined           : 510
  Hybrid Azure AD Joined    : 730

Log file: Full timestamped audit trail saved to script folder.

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Uses Graph API /beta endpoint — required for fields like enrolledByUserId,
  physicalMemoryInBytes, processorArchitecture, DeviceGuard states, and
  bootstrapTokenEscrowed. Monitor Microsoft Graph changelog for beta changes.
- $filter and $select cannot be combined on the managedDevices endpoint
  (causes HTTP 400). This script uses $filter only — by design, not a bug.
- Last-logon enrichment requires one extra API call per device. On a 1,000-device
  tenant with 10 parallel threads, expect approximately 2-4 minutes total.
- $MaxParallelJobs controls Graph API call rate. Keep at or below 20 to stay
  within Graph throttling limits (10,000 requests per 10 minutes per app).
- Log file is always saved to $PSScriptRoot. CSV goes to $OutputFolder (or
  $PSScriptRoot if OutputFolder is left empty).
- Always test in a non-production tenant first.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
ISSUE: "Authentication failed"
FIX  : Verify TenantID, ClientID, ClientSecret. Confirm Admin Consent granted
       for all three permissions in Azure AD.

ISSUE: HTTP 400 Bad Request on device fetch
FIX  : Do not manually add $select to the URI. This script avoids $filter +
       $select combination intentionally. Revert any URI modifications.

ISSUE: HTTP 429 Too Many Requests (throttling)
FIX  : Reduce $MaxParallelJobs from 10 to 5. Reduce $PageSize from 1000 to 500.
       Graph API allows 10,000 requests per 10 minutes per app registration.

ISSUE: LastLoggedOn_UserID shows "LOOKUP ERROR" for some devices
FIX  : The per-device enrichment API call failed for those devices. Usually
       caused by a brief throttle or network timeout. Re-run the script.
       Devices with no logon history show "No Logon Data" — this is expected.

ISSUE: CSV is empty / 0 devices returned
FIX  : Confirm DeviceManagementManagedDevices.Read.All is granted with Admin
       Consent. Verify Windows devices are enrolled and visible in Intune.

ISSUE: FriendlyOSName shows "Windows (Build XXXXX)"
FIX  : Build number is newer than the script mapping table. Export is still
       complete — update ConvertTo-FriendlyOSName when a new Windows version
       is released.

ISSUE: RAM_GB or TotalStorage_GB shows "N/A"
FIX  : These fields (physicalMemoryInBytes, storageTotal) are only populated by
       Intune for devices that have completed a hardware inventory sync. Devices
       that have never fully synced or are in a broken MDM state may not report
       hardware data.

ISSUE: Script execution blocked
FIX  : Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

ISSUE: Log file not created
FIX  : Run PowerShell as Administrator or ensure write permissions on the script
       folder. The script continues without the log if it cannot create the file.

ISSUE: EnrolledBy fields show "N/A"
FIX  : enrolledByUserId and related fields are beta-only. Confirm the script is
       using the /beta endpoint (it is by default). Some devices enrolled via
       Autopilot or bulk methods may not populate these fields.

================================================================================
  GUMROAD LISTING DETAILS
================================================================================

GUMROAD LISTING TITLE
---------------------
Export Full Windows Device Inventory from Intune to CSV — PowerShell Graph API
Script with Parallel Last-Logon Enrichment (50+ Fields)

GUMROAD PRODUCT DESCRIPTION
-----------------------------
The most complete Windows device inventory export available for Microsoft Intune
— no extra modules, no interactive login, and no manual effort required.

This PowerShell script connects to Microsoft Graph API using secure app-only
authentication and pulls every available field for every Windows managed device
in your tenant. It exports 50+ columns covering identity, OS details, hardware
specs (RAM, storage, processor architecture), primary user, last logged-on user,
enrolled-by user, enrollment type, join type, Autopilot status, compliance,
BitLocker encryption, Device Guard states, Exchange access, management
certificate expiry, and more.

What makes this script stand out is its parallel last-logon enrichment engine.
Because the last logged-on user requires a separate per-device API call, the
script uses PowerShell Runspaces to process all devices in parallel — fully
compatible with PowerShell 5.1, no PS 7 required. Thread count is configurable
to stay within Graph API throttling limits on any size tenant.

After export, a detailed console summary shows OS breakdown, compliance status,
encryption coverage, Autopilot enrolment count, and Azure AD / Hybrid join
split — instantly visible without opening the CSV.

Perfect for IT administrators, Microsoft 365 consultants, and Intune engineers
who need the deepest possible device data for audits, migrations, compliance
reviews, or endpoint clean-up projects.

KEY FEATURES
------------
- App-only authentication — no interactive user login required
- Uses Graph API /beta endpoint for maximum field coverage
- Server-side Windows filter — only Windows devices fetched
- Full OData pagination — all devices retrieved regardless of count
- 50+ exported columns: identity, OS, hardware, user, enrollment, compliance,
  security, Exchange/EAS, management, and timestamps
- Parallel last-logon enrichment via PowerShell Runspaces (PS 5.1 compatible)
- Configurable thread pool ($MaxParallelJobs) to control API call rate
- OS build number mapped to human-readable release name (all Win10/11 versions)
- RAM and storage exported in GB (auto-converted from bytes)
- Enrollment type and join type mapped to plain-English descriptions
- Console summary: OS split, compliance, encryption, Autopilot, join types
- Configurable output folder — save CSV anywhere
- Structured log file for every run — full audit trail
- No third-party PowerShell modules required
- Clean, fully commented code — easy to read and customise

WHO THIS SCRIPT IS FOR
----------------------
- IT Administrators managing Windows fleets in Microsoft Intune
- Microsoft 365 / Endpoint Management Consultants
- Security and compliance teams running device audits
- Engineers preparing for Intune migrations or device clean-up projects
- MSPs managing large Windows environments across multiple tenants
- Teams needing last-logon user data for inactive device reviews
- Organisations requiring hardware inventory (RAM, storage) from Intune

SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Windows Device Inventory, Graph API, CSV Export,
Managed Devices, Endpoint Management, Microsoft 365, IT Automation,
Device Compliance, Encryption Audit, BitLocker, DeviceGuard, Last Logged On User,
Autopilot, Azure AD Join, Hybrid Join, Intune Reporting, MEM, MDM,
Windows 10, Windows 11, Runspaces, Parallel Processing, RAM Inventory,
Hardware Inventory, Intune Script, Graph Beta API

BUYER INSTRUCTIONS
------------------
1. Download and extract the ZIP file
2. Open Get-WindowsDeviceInventory.ps1 in any text editor or VS Code
3. Fill in your TenantID, ClientID, and ClientSecret at the top of the script
4. (Optional) Adjust $MaxParallelJobs, $PageSize, and $OutputFolder as needed
5. Run the script from PowerShell
6. CSV is saved to the script folder (or your custom OutputFolder)
7. Log file is saved alongside the script for audit reference
8. Full setup steps, column reference, and troubleshooting in this README.txt

COMMON QUESTIONS / FAQ
-----------------------
Q: Do I need to install any PowerShell modules?
A: No. The script uses only built-in PowerShell cmdlets and direct REST API
   calls. Nothing to install.

Q: Does this work with PowerShell 5.1?
A: Yes. The parallel runspace engine is specifically built for PS 5.1
   compatibility. It does not use ForEach-Object -Parallel (PS 7 only).

Q: What is the difference between this and the Simple version?
A: This full version adds: RAM, storage, processor architecture, last
   logged-on user (parallel enrichment), enrolled-by user, join type,
   Autopilot flag, Device Guard states, management certificate expiry,
   Exchange/EAS fields, device notes, and more. It also uses the /beta
   endpoint for maximum field coverage. The Simple version is faster but
   exports fewer fields using the stable v1.0 endpoint.

Q: How long does the script take to run?
A: For a 1,000-device tenant with $MaxParallelJobs = 10, expect approximately
   2-5 minutes. Most of the time is spent on per-device last-logon enrichment.
   Increase $MaxParallelJobs to 20 to roughly halve the enrichment time.

Q: What if I hit Graph API throttling (429 errors)?
A: Reduce $MaxParallelJobs to 5 and $PageSize to 500. The script will run
   slightly slower but stay within Graph rate limits.

Q: Can I disable the last-logon enrichment to run faster?
A: The enrichment step can be commented out in the MAIN section and the
   LastLogonTable replaced with an empty hashtable. All other columns will
   still export — LastLoggedOn_UserID will show "Not Enriched".

Q: Why does the script use the /beta Graph endpoint?
A: Several fields are only available in the beta endpoint, including
   physicalMemoryInBytes (RAM), processorArchitecture, enrolledByUserId,
   DeviceGuard states, bootstrapTokenEscrowed, and skuFamily. The stable v1.0
   endpoint does not expose these fields.

Q: Can I schedule this to run automatically?
A: Yes. The script runs fully unattended. Use Windows Task Scheduler or any
   automation platform to schedule regular exports.

Q: Can this export devices from multiple tenants?
A: One tenant per run. Update the credential variables and run again for each
   tenant. Each run produces its own timestamped CSV and log file.

================================================================================
  Author  : Sethu Kumar B
  Version : 1.2
  Date    : March 2026
================================================================================
