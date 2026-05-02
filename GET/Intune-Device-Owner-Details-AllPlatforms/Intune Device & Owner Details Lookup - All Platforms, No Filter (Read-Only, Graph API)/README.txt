================================================================================
  README - Get-AllPlatformDeviceOwnerDetails.ps1
================================================================================

SCRIPT NAME
-----------
Get-AllPlatformDeviceOwnerDetails.ps1

FOLDER NAME
-----------
Intune-Device-Owner-Details-AllPlatforms


--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Retrieves full device and owner details for one or more devices by serial number
using the Microsoft Graph API - across ALL device platforms with no OS filtering.

READ ONLY - This script makes only GET requests.
No changes are made to any device, user, policy, or configuration.
Safe to run in production environments and safe to delegate to helpdesk staff.

Unlike a filtered version, this script pulls ALL managed devices from Intune
regardless of platform - Windows, macOS, iOS, Android, Linux, ChromeOS - and
looks up your requested serials across the full device inventory.

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
3.  Bulk pulls ALL Intune managed devices (all platforms) into a hashtable
4.  Bulk pulls ALL Autopilot device identities into a hashtable
5.  For each serial number:
      a. Looks up Intune managed device record from hashtable
      b. Looks up Autopilot record from hashtable
      c. If Intune record found - fetches primary user Azure AD profile
      d. Fetches manager details for the primary user
      e. If NOT in Intune but found in Autopilot - reports as AUTOPILOT ONLY
      f. If not found anywhere - reports as NOT FOUND
6.  Exports full per-device results to timestamped CSV (40+ columns)
7.  Writes detailed run log

NO OS FILTER:
  This script pulls ALL managed devices from Intune with no platform filter.
  Use this when your serial numbers span multiple OS platforms (e.g. a mix of
  Windows laptops, Macs, and iPads) or when the platform is unknown.
  For Windows-only or single-platform environments, a filtered version will
  pull faster in large tenants.

LOOKUP STRATEGY NOTE:
  Script does NOT use $filter on serialNumber - this endpoint returns
  HTTP 500 in some tenants when filtered. Bulk pull with client-side
  hashtable lookup is used instead. This is reliable across all tenants.


--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File name : SerialNumbers.txt
Location  : Same folder as the script

Format: One serial number per line.
Lines starting with # are treated as comments and ignored.
Blank lines are ignored.

Example SerialNumbers.txt:
  # Windows laptops
  5CG114589DQ
  5CG8854866A
  # Mac devices
  C02XG1JDJGH5
  # iPads
  DMPJF3ABDERA


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
  Manufacturer           - Device manufacturer (Apple, HP, Dell, Lenovo, etc.)
  Model                  - Device model name
  OSPlatform             - Operating system platform (Windows / macOS / iOS / etc.)
  OSVersion              - Full OS version string
  OSBuildNumber          - Windows build number (N/A for non-Windows platforms)
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
  IsEncrypted            - True / False - BitLocker / FileVault status
  IsSupervised           - True / False
  AutopilotEnrolled      - True / False

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
  2. Open your App Registration (create a dedicated READ ONLY one if needed)
  3. Go to API Permissions > Add a Permission > Microsoft Graph
  4. Select Application Permissions
  5. Search and add all four permissions listed above
  6. Click Grant Admin Consent for your tenant
  7. Confirm all four show green checkmark (Granted)

SECURITY NOTE:
  Consider creating a dedicated read-only App Registration for this script.
  Read-only permissions mean no data can be modified even if credentials
  are accidentally exposed.


--------------------------------------------------------------------------------
HOW TO CONFIGURE THE SCRIPT
--------------------------------------------------------------------------------
Open the script and update the CONFIGURATION section at the top:

  $TenantID     = "your-tenant-id"
  $ClientID     = "your-client-id"
  $ClientSecret = "your-client-secret"

Input file (default, do not change unless needed):
  $InputFileName = "SerialNumbers.txt"

Place SerialNumbers.txt in the same folder as the script.
No other configuration is required - the script pulls all platforms automatically.


--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
1. Place SerialNumbers.txt in the same folder as the script
2. Open PowerShell and navigate to the script folder:
     cd "C:\Scripts\Intune-Device-Owner-Details-AllPlatforms"
3. Run the script:
     .\Get-AllPlatformDeviceOwnerDetails.ps1
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
PERFORMANCE NOTE FOR LARGE ENVIRONMENTS
--------------------------------------------------------------------------------
This script pulls ALL managed devices from Intune with no platform filter.
In large mixed-platform environments (10,000+ devices across multiple OS types)
the initial bulk pull may take longer compared to a filtered script.

After the initial pull, all per-serial lookups are instant via hashtable.
Per-user Azure AD calls (profile + manager) add roughly 1-2 seconds per serial.

If your environment is Windows-only or single-platform and has a very large
device count, consider using a platform-filtered version of this script to
reduce initial pull time.


--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
1. READ ONLY - ZERO RISK OF CHANGES
   Script makes only GET requests. No data is modified, deleted, or created.
   Safe to run in production. Safe to delegate to helpdesk or junior admins.

2. ALL PLATFORMS - NO OS FILTER
   Intune pull includes Windows, macOS, iOS, Android, Linux, and ChromeOS.
   Use this when serial numbers span multiple platforms or platform is unknown.

3. AUTOPILOT ONLY RESULT
   If a device is registered in Autopilot but has not yet enrolled in Intune
   (e.g. brand new device not yet deployed), the script reports AUTOPILOT ONLY
   with available Autopilot fields populated.

4. NO PRIMARY USER
   Shared or kiosk devices may have no primary user assigned. The script
   reports No Primary User and N/A for all user-related fields.

5. BULK PULL APPROACH
   Script pulls all Intune and Autopilot records before processing serials.
   In large mixed-platform environments this initial pull may take several
   minutes. After the pull, per-serial lookup is instant via hashtable.

6. PER-USER GRAPH CALLS
   For each device found in Intune, the script makes two additional Graph
   calls per device (user profile + manager). A 200ms delay between serials
   reduces throttling risk. For large lists (50+ serials) allow extra time.

7. OS BUILD NUMBER
   Build number is extracted from OSVersion using Windows 10.0.XXXXX format.
   Non-Windows devices (macOS, iOS, Android) will show N/A for OSBuildNumber.
   The raw OSVersion field is still populated for all platforms.

8. PHONE NUMBER PRIORITY
   Mobile phone is shown if available. Falls back to first business phone
   if mobile is not set. Shows N/A if neither is populated in Azure AD.

9. AUTOPILOT DATA FOR NON-WINDOWS
   Autopilot only applies to Windows devices. macOS, iOS, and Android devices
   will show Not in Autopilot or N/A for all Autopilot columns.


--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Issue   : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Check the client secret has not expired in Azure portal.

Issue   : 403 Forbidden on API calls
Fix     : Confirm all four permissions are Application type (not Delegated)
          and admin consent is granted. Check green checkmarks in Azure portal.

Issue   : Input file not found error
Fix     : Confirm SerialNumbers.txt is in the exact same folder as the script.

Issue   : All serials show NOT FOUND
Fix     : Confirm serial numbers are correct with no leading/trailing spaces.
          Verify the devices are enrolled in Intune by checking the portal.
          Note this script pulls all platforms - no filter to adjust.

Issue   : User fields all show N/A
Fix     : Confirm User.Read.All and Directory.Read.All permissions are granted.
          Check that a primary user is assigned to the device in Intune.
          Shared or kiosk devices with no primary user will always show N/A.

Issue   : Manager shows N/A
Fix     : User may have no manager assigned in Azure AD / Entra ID.
          Check the user profile in Azure AD portal to confirm.

Issue   : Initial pull takes a long time
Fix     : Expected in large mixed-platform environments. The script pulls all
          platforms with no filter. For very large tenants, allow extra time
          for the initial pull. All lookups are instant after the pull completes.

Issue   : Some devices show AUTOPILOT ONLY
Fix     : Device is registered in Autopilot but has not enrolled in Intune yet.
          Expected for new devices not yet deployed. Autopilot details are
          still reported in the CSV for these devices.

Issue   : Script blocked by execution policy
Fix     : Run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Issue   : OSBuildNumber shows N/A
Fix     : Expected for macOS, iOS, Android, and other non-Windows devices.
          OSBuildNumber extraction uses the Windows 10.0.XXXXX pattern only.
          The full OSVersion string is still exported for all platforms.

Issue   : Autopilot columns show N/A for Mac or iOS devices
Fix     : Expected. Windows Autopilot only applies to Windows devices.
          macOS, iOS, and Android devices are managed via Apple DEP / Android
          Enterprise, not Windows Autopilot.


================================================================================
  GUMROAD LISTING INFORMATION
================================================================================

LISTING TITLE
-------------
PowerShell Script - Get Intune Device & Owner Details by Serial Number - All Platforms (Read-Only, Graph API)


PRODUCT DESCRIPTION
-------------------
A ready-to-use PowerShell script that retrieves complete device and owner
information from Microsoft Intune, Azure AD, and Windows Autopilot by serial
number - across ALL device platforms with no OS filtering.

Works for Windows, macOS, iOS, Android, Linux, and ChromeOS devices in the
same run. Provide a list of serial numbers from any mix of platforms, and get
back a rich CSV with 40+ columns covering hardware, OS details, enrollment,
compliance, Autopilot registration, primary user profile, department, job title,
office location, phone, and manager details.

No changes are made to anything. Read-only permissions only.
Safe to run in production. Safe to hand to helpdesk staff.

Ideal for mixed-device environments where serial numbers span multiple OS
platforms, or where the platform of each device is not known upfront. Perfect
for asset audits, user-to-device mapping, compliance reporting, offboarding
lookups, and any situation where you need complete device and owner information
without clicking through the Intune portal one device at a time.


KEY FEATURES
------------
- Read-only - zero risk of changes to any device, user, or policy
- Supports ALL platforms - Windows, macOS, iOS, Android, Linux, ChromeOS
- No OS filter - mixed serial lists from multiple platforms work in one run
- 40+ output columns across Identity, Hardware, Enrollment, Autopilot, and User
- Handles Autopilot-only devices (registered but not yet Intune enrolled)
- Retrieves primary user department, job title, location, phone, and manager
- Bulk pull with hashtable lookup - reliable across all tenant sizes
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
- IT Administrators managing mixed-platform device environments
- Helpdesk teams looking up device and owner info across all device types
- System Engineers running asset audits across Windows, Mac, and mobile
- IT Managers pulling compliance and enrollment reports for all platforms
- Intune consultants delivering cross-platform device reports to clients
- Organizations with BYOD programs spanning multiple OS platforms


SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Graph API, Device Lookup, Serial Number,
All Platforms, macOS, iOS, Android, Windows, Cross Platform, Device Owner,
Asset Audit, Read Only, Azure AD, Entra ID, Autopilot, Primary User,
Department, Manager, Compliance, Enrollment, Hardware Details, Device Report,
Intune Script, Endpoint Management, IT Admin, Device Inventory, managedDevices,
Mixed Platform, BYOD, Multi Platform


BUYER INSTRUCTIONS
------------------
1.  Download and extract the ZIP file
2.  Open Get-AllPlatformDeviceOwnerDetails.ps1 in a text editor
3.  Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION section
4.  Create SerialNumbers.txt in the same folder (one serial per line)
5.  Mix serial numbers from any platform in the same file - no grouping needed
6.  Open PowerShell and run the script:
       .\Get-AllPlatformDeviceOwnerDetails.ps1
7.  Monitor console for real-time lookup progress
8.  Open the generated CSV for full device and owner details
9.  Full setup and troubleshooting instructions are in this README.txt file


COMMON QUESTIONS / FAQ
-----------------------
Q: Does this script make any changes to devices or users?
A: No. The script makes only GET (read) requests. Nothing is modified,
   deleted, or created. It is completely safe to run in production.

Q: What platforms does this script support?
A: All platforms managed in Intune - Windows, macOS, iOS, Android, Linux,
   and ChromeOS. Serial numbers from any mix of these can be looked up in
   one run with no configuration changes needed.

Q: What permissions does the App Registration need?
A: Four read-only Application permissions with admin consent:
   DeviceManagementManagedDevices.Read.All
   DeviceManagementServiceConfig.Read.All
   User.Read.All
   Directory.Read.All

Q: Why does the script pull ALL devices instead of filtering?
A: Two reasons. First, this script intentionally has no OS filter to support
   mixed-platform serial lists. Second, the Graph API serialNumber $filter
   returns HTTP 500 in some tenants. Bulk pull with hashtable lookup is the
   reliable approach for all environments.

Q: Will macOS or iOS devices show Autopilot details?
A: No. Windows Autopilot only applies to Windows devices. macOS and iOS
   devices managed via Apple DEP or Apple Business Manager will show N/A
   or Not in Autopilot for Autopilot columns. All other fields are populated.

Q: What if a device has no primary user?
A: The script reports No Primary User in the UPN column and N/A for all
   user-related fields. Expected for shared, kiosk, or room devices.

Q: What does AUTOPILOT ONLY mean in the LookupStatus column?
A: The device is registered in Windows Autopilot but has not yet enrolled
   in Intune. Normal for new Windows devices not yet deployed. Available
   Autopilot fields are still reported in the CSV row.

Q: How long does the script take?
A: Initial bulk pull of all platforms may take 3-6 minutes in large tenants
   with 10,000+ mixed-platform devices. After the pull, each serial requires
   two additional Graph calls (user profile + manager). A list of 20 serials
   typically completes within 5-8 minutes total depending on tenant size.

Q: Is the output compatible with Excel?
A: Yes. CSV is exported with UTF-8 encoding and standard comma delimiters.
   Open directly in Excel or import via Data > From Text/CSV.

Q: Do I need the Microsoft.Graph PowerShell module?
A: No. The script uses only built-in PowerShell cmdlets and direct REST
   API calls. No additional modules need to be installed.

Q: Is PowerShell 7 supported?
A: Yes. The script requires PowerShell 5.1 or later and is fully compatible
   with PowerShell 7.x on Windows.

Q: How is this different from the Windows-only filtered version?
A: This script pulls ALL platforms with no OS filter. The filtered version
   lets you specify a target OS (Windows, macOS, iOS, etc.) to reduce pull
   time in large single-platform environments. Use this script when your
   serial numbers span multiple platforms or platform is unknown.

================================================================================
  END OF README
================================================================================
