================================================================================
  README - Get-DeviceOwnerDetails.ps1
================================================================================

SCRIPT NAME
-----------
Get-DeviceOwnerDetails.ps1

FOLDER NAME
-----------
Intune-Device-Owner-Details


--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Retrieves full device and owner details for one or more Windows devices by
serial number using the Microsoft Graph API.

READ ONLY - This script makes only GET requests.
No changes are made to any device, user, policy, or configuration.
Safe to run in production environments and safe to delegate to helpdesk staff.

For each serial number the script retrieves:
  - Intune managed device record (hardware, OS, compliance, enrollment)
  - Primary user profile (department, job title, location, phone)
  - Azure AD manager (manager name and UPN)
  - Windows Autopilot registration (group tag, profile, enrollment state)


--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES (STEP BY STEP)
--------------------------------------------------------------------------------
1.  Reads serial numbers from SerialNumbers.txt (one per line)
2.  Authenticates to Microsoft Graph API using Azure AD App credentials
3.  Bulk pulls ALL Intune managed devices into a hashtable lookup
      - Filtered by $TargetOS (default: Windows) to reduce data volume
      - Configurable to pull any OS platform or all platforms
4.  Bulk pulls ALL Autopilot device identities into a hashtable lookup
5.  For each serial number:
      a. Looks up Intune managed device record from hashtable
      b. Looks up Autopilot record from hashtable
      c. If Intune record found - fetches primary user Azure AD profile
      d. Fetches manager details for the primary user
      e. If NOT in Intune but found in Autopilot - reports as AUTOPILOT ONLY
      f. If not found anywhere - reports as NOT FOUND
6.  Exports full per-device results to timestamped CSV (40+ columns)
7.  Writes detailed run log

LOOKUP STRATEGY NOTE:
  Script does NOT use $filter on serialNumber - this endpoint returns
  HTTP 500 in some tenants when filtered. Bulk pull with client-side
  hashtable lookup is used instead. This is reliable across all tenants.


--------------------------------------------------------------------------------
OS PLATFORM FILTER
--------------------------------------------------------------------------------
$TargetOS = "Windows"   <-- DEFAULT

Controls which OS platform is pulled from Intune managed devices.
Set to the platform matching your devices or leave blank to pull all.

Valid values:
  "Windows"   - Windows laptops and desktops (default)
  "macOS"     - Mac devices
  "iOS"       - iPhones and iPads
  "Android"   - Android devices
  "Linux"     - Linux devices
  "ChromeOS"  - Chromebooks
  ""          - All platforms (slower for large mixed-OS environments)

Note: Autopilot lookup always pulls ALL records regardless of $TargetOS.
Autopilot only stores Windows devices by design.


--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File name : SerialNumbers.txt
Location  : Same folder as the script

Format: One serial number per line.
Lines starting with # are treated as comments and ignored.
Blank lines are ignored.

Example SerialNumbers.txt:
  # Laptops for asset audit
  5CG1466TDQ
  5CG2891XZA
  # Office desktop
  5CG3302LPQ
  MXL1234ABC


--------------------------------------------------------------------------------
OUTPUT CSV COLUMNS (40+ FIELDS)
--------------------------------------------------------------------------------

IDENTITY
  SerialNumber           - Serial number from input file
  DeviceName             - Device hostname from Intune
  IntuneDeviceID         - Intune managed device GUID
  AzureAD_DeviceID       - Azure AD device object GUID
  AutopilotDeviceID      - Autopilot device identity GUID

HARDWARE
  Manufacturer           - Device manufacturer (HP, Dell, Lenovo, etc.)
  Model                  - Device model name
  OSPlatform             - Operating system platform
  OSVersion              - Full OS version string
  OSBuildNumber          - Windows build number extracted from OS version
  FreeStorageGB          - Free disk space in GB
  TotalStorageGB         - Total disk capacity in GB
  PhysicalMemoryGB       - Physical RAM in GB

ENROLLMENT
  EnrollmentType         - Human-readable enrollment type
  EnrollmentDate         - Date device was enrolled in Intune
  LastSyncDateTime       - Last time device checked in with Intune
  DaysSinceLastSync      - Number of days since last sync
  ComplianceState        - compliant / noncompliant / unknown / notApplicable
  ManagementState        - managed / retirePending / wipePending / etc.
  ManagementAgent        - mdm / easMdm / configurationManagerClientMdm / etc.
  JoinType               - Azure AD Joined / Hybrid Azure AD Joined / Registered
  OwnerType              - company / personal
  IsEncrypted            - True / False - BitLocker or FileVault status
  IsSupervised           - True / False
  AutopilotEnrolled      - True / False - whether enrolled via Autopilot

AUTOPILOT
  GroupTag               - Autopilot group tag (or "(empty)" / "Not in Autopilot")
  AutopilotProfile       - Deployment profile assignment status
  AutopilotEnrollState   - enrolled / notContacted / pending / failed
  AutopilotLastContacted - Last time device contacted Autopilot service

PRIMARY USER
  PrimaryUser_UPN            - Primary user sign-in name
  PrimaryUser_DisplayName    - Primary user full name
  PrimaryUser_Department     - Department from Azure AD user profile
  PrimaryUser_JobTitle       - Job title from Azure AD user profile
  PrimaryUser_OfficeLocation - Office location from Azure AD user profile
  PrimaryUser_City           - City from Azure AD user profile
  PrimaryUser_Country        - Country from Azure AD user profile
  PrimaryUser_Phone          - Mobile phone (falls back to business phone)
  PrimaryUser_Manager        - Manager display name
  PrimaryUser_ManagerUPN     - Manager sign-in name / UPN
  PrimaryUser_AccountEnabled - True / False - whether user account is active

STATUS
  LookupStatus           - FOUND / NOT FOUND / AUTOPILOT ONLY
  LookupNote             - Detail message explaining the lookup result

LOOKUP STATUS VALUES:
  FOUND          - Device found in Intune with full details retrieved
  AUTOPILOT ONLY - Registered in Autopilot but not yet enrolled in Intune
  NOT FOUND      - Serial not found in Intune or Autopilot


--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later (fully compatible with PS 7.x)
- TLS 1.2 enabled (script enables this automatically)
- Azure AD App Registration with Client Secret
- Admin consent granted for required Graph API permissions (see below)
- SerialNumbers.txt placed in the same folder as the script
- Internet access to login.microsoftonline.com and graph.microsoft.com


--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
All permissions must be Application type (not Delegated).
Admin consent must be granted for all four.
All permissions are READ ONLY - no write access is requested or needed.

  Permission 1: DeviceManagementManagedDevices.Read.All
    - Read Intune managed device records (hardware, OS, enrollment, compliance)

  Permission 2: DeviceManagementServiceConfig.Read.All
    - Read Windows Autopilot device identity records (group tag, profile)

  Permission 3: User.Read.All
    - Read Azure AD user profiles (department, job title, location, phone)
    - Read manager information for each user

  Permission 4: Directory.Read.All
    - Read Azure AD directory objects
    - Required for manager lookup

Steps to grant permissions:
  1. Go to Azure Portal > Azure Active Directory > App Registrations
  2. Open your App Registration (create one if needed - READ ONLY recommended)
  3. Go to API Permissions > Add a Permission > Microsoft Graph
  4. Select Application Permissions
  5. Search and add all four permissions listed above
  6. Click Grant Admin Consent for your tenant
  7. Confirm all four show green checkmark (Granted)

SECURITY NOTE:
  Consider creating a dedicated read-only App Registration for this script.
  Using read-only permissions means this script cannot modify any data
  even if credentials are compromised.


--------------------------------------------------------------------------------
HOW TO CONFIGURE THE SCRIPT
--------------------------------------------------------------------------------
Open the script and update the CONFIGURATION section at the top:

  $TenantID      = "your-tenant-id"
  $ClientID      = "your-client-id"
  $ClientSecret  = "your-client-secret"
  $TargetOS      = "Windows"    -- change to match your device OS or leave blank

Input file (default, do not change unless needed):
  $InputFileName = "SerialNumbers.txt"

Place SerialNumbers.txt in the same folder as the script.


--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
1. Place SerialNumbers.txt in the same folder as the script
2. Open PowerShell and navigate to the script folder:
     cd "C:\Scripts\Intune-Device-Owner-Details"
3. Run the script:
     .\Get-DeviceOwnerDetails.ps1
4. Monitor console output for real-time lookup progress
5. Review the generated CSV when complete

If execution policy blocks the script:
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass


--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console output uses color-coded status:
  Cyan   - Section headers and completion banner
  Green  - Devices found successfully
  Yellow - Warnings (not found, autopilot only, no primary user)
  Red    - Errors
  Gray   - General information

Files generated in the script folder (timestamped):
  DeviceOwnerDetails_YYYYMMDD_HHmmss.csv
  DeviceOwnerDetails_YYYYMMDD_HHmmss.log

Summary at end of run shows:
  Total serials processed  : count from input file
  Found in Intune          : devices found with full details
  Autopilot only           : registered in Autopilot but not Intune enrolled
  Not found                : not found in Intune or Autopilot


--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
1. READ ONLY - ZERO RISK OF CHANGES
   Script makes only GET requests. No data is modified, deleted, or created.
   Safe to run in production. Safe to delegate to helpdesk or junior admins.

2. AUTOPILOT ONLY RESULT
   If a device is registered in Autopilot but has not yet enrolled in Intune
   (e.g. brand new device not yet deployed), the script reports it as
   AUTOPILOT ONLY with available Autopilot fields populated.

3. NO PRIMARY USER
   Some shared or kiosk devices have no primary user assigned. The script
   reports No Primary User in the UPN column and N/A for all user fields.

4. BULK PULL APPROACH
   Script pulls all Intune and Autopilot records before processing serials.
   In large environments this initial pull may take several minutes.
   After the pull, per-serial lookup is instant via hashtable.

5. PER-USER GRAPH CALLS
   For each device found in Intune, the script makes two additional Graph
   calls per device (user profile + manager). A 200ms delay is added between
   serials to reduce throttling risk. For large lists (50+ serials), the
   script may take a few extra minutes due to these per-user calls.

6. OS BUILD NUMBER
   Build number is extracted from the OSVersion field using regex pattern
   matching on the Windows 10.0.XXXXX format. Non-Windows devices will
   show N/A for OSBuildNumber.

7. PHONE NUMBER PRIORITY
   Mobile phone is shown if available. Falls back to first business phone
   if mobile is not set. Shows N/A if neither is populated in Azure AD.

8. MANAGER LOOKUP
   Manager is read from Azure AD using the /manager endpoint per user.
   If the user has no manager assigned or the manager record is not found,
   both Manager and ManagerUPN columns show N/A.


--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Issue   : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Check that the client secret has not expired in Azure portal.

Issue   : 403 Forbidden on API calls
Fix     : Confirm all four permissions are Application type (not Delegated)
          and admin consent is granted. Check green checkmarks in Azure portal.

Issue   : Input file not found error
Fix     : Confirm SerialNumbers.txt is in the exact same folder as the script.
          File name is case-sensitive on some systems.

Issue   : All serials show NOT FOUND
Fix     : Verify $TargetOS matches the OS of your devices.
          If looking up macOS or iOS devices, change $TargetOS accordingly.
          Set $TargetOS = "" to pull all platforms.
          Confirm serial numbers are correct with no spaces or special characters.

Issue   : User fields all show N/A
Fix     : Confirm User.Read.All and Directory.Read.All permissions are granted.
          Check that the primary user is assigned to the device in Intune.
          Some devices have no primary user (shared/kiosk) - this is expected.

Issue   : Manager shows N/A
Fix     : User may have no manager assigned in Azure AD / Entra ID.
          Check the user's profile in Azure AD portal to confirm.

Issue   : Initial pull takes a long time
Fix     : Expected for large environments. The script pulls all devices once
          then lookups are instant. Set $TargetOS to filter by platform and
          reduce the number of records pulled.

Issue   : Some devices show AUTOPILOT ONLY
Fix     : Device is registered in Autopilot but not enrolled in Intune yet.
          This is expected for new devices that have not been deployed.
          Deploy the device through Autopilot to get full Intune details.

Issue   : Script blocked by execution policy
Fix     : Run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Issue   : OSBuildNumber shows N/A for Windows devices
Fix     : OSVersion field from Intune may not follow the 10.0.XXXXX format
          for older OS versions. The raw OSVersion is still exported.


================================================================================
  GUMROAD LISTING INFORMATION
================================================================================

LISTING TITLE
-------------
PowerShell Script - Get Intune Device & Owner Details by Serial Number (Read-Only, Graph API)


PRODUCT DESCRIPTION
-------------------
A ready-to-use PowerShell script that retrieves complete device and owner
information from Microsoft Intune, Azure AD, and Windows Autopilot by serial
number - using only read-only Microsoft Graph API calls.

Provide a list of serial numbers, run the script, and get back a rich CSV
with 40+ columns covering hardware specs, OS details, enrollment info,
compliance state, Autopilot registration, primary user profile, department,
job title, office location, phone number, and manager details.

No changes are made to anything. Read-only permissions only.
Safe to run in production. Safe to hand to helpdesk staff.

Perfect for IT asset audits, user-to-device mapping, offboarding lookups,
compliance reporting, and any situation where you need to quickly find out
who owns a device and what state it is in - without clicking through the
Intune portal one device at a time.


KEY FEATURES
------------
- Read-only - zero risk of changes to any device, user, or policy
- 40+ output columns across Identity, Hardware, Enrollment, Autopilot, and User
- Handles Autopilot-only devices (registered but not yet Intune enrolled)
- Retrieves primary user department, job title, location, phone, and manager
- Configurable OS platform filter (Windows, macOS, iOS, Android, or all)
- Bulk pull with hashtable lookup - fast and reliable across all tenant sizes
- Per-user Azure AD profile and manager fetched automatically per device
- Human-readable enrollment type mapping (no raw API enum values)
- Days since last sync calculated automatically
- Storage and RAM converted from bytes to GB automatically
- Handles devices with no primary user (shared / kiosk devices)
- Color-coded console output for real-time monitoring
- Timestamped CSV and log file output
- 429 throttle protection with automatic retry
- Fully compatible with PowerShell 5.1 and 7.x
- No third-party modules required


WHO THIS SCRIPT IS FOR
----------------------
- IT Administrators running device audits or asset inventories
- Helpdesk teams looking up device and owner info for support tickets
- System Engineers mapping devices to users during offboarding
- IT Managers pulling compliance and enrollment status reports
- Intune consultants delivering device health or asset reports to clients
- Organizations auditing device encryption, compliance, or sync status


SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Graph API, Device Lookup, Serial Number,
Device Owner, Asset Audit, Read Only, Azure AD, Entra ID, Autopilot,
Primary User, Department, Manager, Compliance, Enrollment, Hardware Details,
Device Report, Intune Script, Endpoint Management, IT Admin, Device Inventory,
managedDevices, windowsAutopilotDeviceIdentities, User Profile


BUYER INSTRUCTIONS
------------------
1.  Download and extract the ZIP file
2.  Open Get-DeviceOwnerDetails.ps1 in a text editor
3.  Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION section
4.  Set $TargetOS to match your device platform (default is Windows)
5.  Create SerialNumbers.txt in the same folder (one serial per line)
6.  Open PowerShell and run the script:
       .\Get-DeviceOwnerDetails.ps1
7.  Monitor console for real-time lookup progress
8.  Open the generated CSV for full device and owner details
9.  Full setup and troubleshooting instructions are in this README.txt file


COMMON QUESTIONS / FAQ
-----------------------
Q: Does this script make any changes to devices or users?
A: No. The script makes only GET (read) requests. Nothing is modified,
   deleted, or created. It is completely safe to run in production.

Q: What permissions does the App Registration need?
A: Four read-only Application permissions with admin consent:
   DeviceManagementManagedDevices.Read.All
   DeviceManagementServiceConfig.Read.All
   User.Read.All
   Directory.Read.All

Q: Can I use this for macOS, iOS, or Android devices?
A: Yes. Change $TargetOS to macOS, iOS, Android, or leave blank for all
   platforms. Note that Autopilot details only apply to Windows devices.

Q: What if a device has no primary user?
A: The script reports No Primary User in the UPN column and N/A for all
   user-related fields. This is expected for shared or kiosk devices.

Q: What does AUTOPILOT ONLY mean in the LookupStatus column?
A: The device is registered in Windows Autopilot but has not yet enrolled
   in Intune. This is normal for new devices that have not been deployed yet.
   Available Autopilot fields (group tag, enrollment state) are still reported.

Q: How long does the script take?
A: Initial bulk pull depends on environment size. A 10,000 device tenant
   may take 2-4 minutes to pull. After that, each serial requires two
   additional Graph calls (user profile + manager) adding roughly 1-2
   seconds per device. A list of 20 serials typically completes in under
   5 minutes total.

Q: Is the output compatible with Excel?
A: Yes. The CSV is exported with UTF-8 encoding and standard comma
   delimiters. Open directly in Excel or import via Data > From Text/CSV.

Q: Do I need the Microsoft.Graph PowerShell module?
A: No. The script uses only built-in PowerShell cmdlets and direct REST
   API calls. No additional modules need to be installed.

Q: Is PowerShell 7 supported?
A: Yes. The script requires PowerShell 5.1 or later and is fully compatible
   with PowerShell 7.x on Windows.

Q: Can I run this for a large list of serials (100+)?
A: Yes. The bulk pull happens once at the start. Per-serial lookup is fast.
   The per-user Azure AD calls (profile + manager) add time proportional
   to the number of serials. A 200ms delay per serial helps avoid throttling.

================================================================================
  END OF README
================================================================================
