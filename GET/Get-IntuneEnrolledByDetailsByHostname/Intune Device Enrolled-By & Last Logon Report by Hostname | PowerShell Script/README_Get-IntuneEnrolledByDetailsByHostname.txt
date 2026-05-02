================================================================================
  README - Get-IntuneEnrolledByDetailsByHostname.ps1
  Author : Sethu Kumar B
================================================================================

SCRIPT NAME
-----------
Get-IntuneEnrolledByDetailsByHostname.ps1

FOLDER NAME
-----------
Get-IntuneEnrolledByDetailsByHostname

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Retrieves full device details from Microsoft Intune for a list of hostnames,
with a focus on enrollment identity and last logged-on user resolution.

For each hostname the script fetches the complete $entity payload from the
Intune Graph API beta endpoint — guaranteeing all fields are returned,
including usersLoggedOn which is excluded from standard list responses.
The last logged-on user GUID is resolved to a UPN via a separate Graph call.

Use this script when you need to know who enrolled a device, who last logged
on, and the full device context — from a list of computer names.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Authenticates to Microsoft Graph API using Azure AD app credentials
   (client credentials flow — no user sign-in required).

2. Reads hostnames from a .txt file (one per line) or accepts a runtime
   prompt. Blank lines are ignored. Hostnames are uppercased and deduplicated.

3. For each hostname:

   Step 1 — Searches Intune by deviceName using $filter=deviceName eq '<n>'.
            $select is intentionally omitted — $filter + $select on the Intune
            endpoint causes HTTP 400 Bad Request.

   Step 2 — Fetches the full $entity record for each matched device by ID:
              GET /beta/deviceManagement/managedDevices/{id}
            This guarantees every field is returned including usersLoggedOn.

   Step 3 — Resolves the most recent usersLoggedOn userId GUID to UPN via:
              GET /beta/users/{userId}?$select=userPrincipalName

4. Maps OS version to a human-readable friendly name:
   Windows build numbers → Win10 1507 through Win11 24H2
   macOS major versions  → Big Sur through Sequoia / Tahoe

5. Flags duplicate Intune records when more than one device matches a hostname.

6. Adds a NOT FOUND placeholder row for any hostname not found in Intune.

7. Also supports All-devices mode (pull everything, client-side OS filter).

8. Exports a timestamped CSV to the configured output folder.

NO changes are made to any Intune or Azure AD record.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Hostname .txt file (one hostname per line)
- Azure AD App Registration with Tenant ID, Client ID, Client Secret
- Admin consent granted for required Graph API permissions (see below)
- Network access to login.microsoftonline.com and graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission Type : Application (no user sign-in required)

Permission Name                          Required For
----------------------------------------+--------------------------------------
DeviceManagementManagedDevices.Read.All  Intune device records and entity fetch
User.Read.All                            Resolve usersLoggedOn userId to UPN

Admin Consent : Required for both permissions.

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1 - Open Get-IntuneEnrolledByDetailsByHostname.ps1 in any text editor.

Step 2 - Fill in the CONFIGURATION block:

         $TenantID     = "your-tenant-id"
         $ClientID     = "your-client-id"
         $ClientSecret = "your-client-secret"
         $InputFile    = "C:\temp\Hostnames.txt"   (or leave "" to be prompted)
         $OSFilter     = "Windows"                 (All-devices mode only)
         $OutputFolder = "C:\temp\Output"

Step 3 - Create your hostname .txt file with one hostname per line.

Step 4 - Open PowerShell 5.1 or later and run:
         .\Get-IntuneEnrolledByDetailsByHostname.ps1

Step 5 - If $InputFile is blank, you will be prompted to choose:
           [1] Load hostnames from a .txt file
           [2] Pull ALL devices from Intune

Step 6 - Review the console output and generated CSV in the output folder.

--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File   : Any .txt file — path set in $InputFile or entered at runtime
Format : One hostname per line. Blank lines ignored. Case-insensitive.

Example:
  DESKTOP-ABC123
  LAPTOP-XYZ789
  WS-FINANCE-01

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console:
  - Per-hostname search result (FOUND / NOT FOUND / DUPLICATE warning)
  - Entity fetch confirmation per device
  - Last logon UPN resolution status
  - Summary of not-found hostnames

File (saved to $OutputFolder):
  All_IntuneDeviceSummary_ByHostname_[Timestamp].csv   (hostname file mode)
  All_IntuneDeviceSummary_[OSFilter]_[Timestamp].csv   (all-devices mode)

CSV Columns (33):
  IDENTITY   : DeviceName, ManagedDeviceName, FQDN, SerialNumber,
               Manufacturer, Model, ChassisType, BIOSVersion, WiFiMacAddress

  OS         : OperatingSystem, OSVersion, OSFriendlyName, SKUFamily

  USERS      : PrimaryUserDisplayName, PrimaryUserEmail,
               PrimaryUserEmailAddress, EnrolledByEmail,
               LastLogonEmail, LastLogonDateTime

  ENROLLMENT : EnrolledDateTime, EnrollmentType, EnrollmentProfileName,
               JoinType, AutopilotEnrolled, AzureADRegistered, AADRegistered

  MANAGEMENT : ManagementState, ManagementAgent, ComplianceState,
               OwnerType, DeviceRegistrationState, LastSyncDateTime

  ENTRA ID   : AzureADDeviceId, AzureActiveDirectoryDeviceId

  SECURITY   : IsEncrypted

--------------------------------------------------------------------------------
KEY COLUMNS EXPLAINED
--------------------------------------------------------------------------------
EnrolledByEmail      - UPN of the person or service that enrolled the device
                       (enrolledByUserPrincipalName from $entity payload)

LastLogonEmail       - UPN of the most recently logged-on user, resolved from
                       usersLoggedOn array via /beta/users/{userId} lookup.
                       Empty if no logon data or User.Read.All not granted.

LastLogonDateTime    - Timestamp of the most recent logon from usersLoggedOn.

OSFriendlyName       - Human-readable OS label mapped from build number:
                       Windows: Win10 1507 through Win11 24H2
                       macOS  : Big Sur through Sequoia / Tahoe

ManagedDeviceName    - Shows "NOT FOUND" for hostnames not in Intune.

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Script uses Graph API beta endpoint. usersLoggedOn is not returned by the
  list endpoint regardless of $select — per-device entity fetch is required.

- $select is intentionally omitted from the search (Step 1).
  $filter + $select on the Intune managedDevices endpoint returns HTTP 400.

- All-devices mode fetches one entity per device — runtime scales with
  tenant size. For large tenants (10,000+ devices) this may take 20+ minutes.
  Hostname file mode is faster and recommended for targeted lookups.

- 200ms delay between hostname lookups (file mode) and 100ms between entity
  fetches (all-devices mode) to reduce Graph API throttling risk.

- Duplicate hostname records (two Intune records with the same deviceName)
  are reported with a WARN and both records are included in the CSV.

- NOT FOUND rows have empty values for all columns except DeviceName and
  ManagedDeviceName = "NOT FOUND".

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Problem : Authentication fails immediately
Fix     : Verify TenantID, ClientID, ClientSecret. Check secret expiry in
          Azure AD portal.

Problem : HTTP 400 on search queries
Fix     : Do not add $select to the search URI. The script already handles
          this correctly — do not modify the $listUri construction.

Problem : LastLogonEmail is empty for all devices
Fix     : Confirm User.Read.All admin consent is granted.
          Also check: if device has never had a user log on interactively,
          usersLoggedOn will be empty — this is expected.

Problem : Hostname returns NOT FOUND but device exists in Intune
Fix     : Confirm the hostname matches exactly as it appears in Intune
          (deviceName field). Check for trailing spaces or domain suffixes.
          Intune deviceName is the NetBIOS name, not the FQDN.

Problem : All-devices mode is very slow
Fix     : Expected — one entity fetch per device. Use hostname file mode
          for targeted lookups. For full tenant exports, run during off-hours.

Problem : OSFriendlyName shows Unknown Build (NNNNN)
Fix     : The build number is not in the mapping table. This means the device
          is on a build released after the script was last updated.
          The raw OSVersion is still exported in the OSVersion column.

Problem : CSV not created
Fix     : Confirm $OutputFolder path is valid and script has write permission.
          The folder is created automatically if it does not exist.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Intune Enrolled-By & Last Logon Report by Hostname | PowerShell Graph API Script

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Find out who enrolled any Intune device — and who last logged on — from a
simple list of hostnames.

This PowerShell script takes a .txt file of computer names, looks up each
device in Microsoft Intune via the Graph API beta endpoint, fetches the full
device entity (not the stripped-down list response), and resolves the last
logged-on user GUID to an actual UPN. The result is a clean 33-column CSV
covering enrollment identity, last logon, OS details, compliance state,
join type, Autopilot status, and more.

Built for IT admins and endpoint engineers who need fast, accurate answers
about device enrollment ownership — without clicking through the Intune portal
one device at a time.

What you get:
- Production-ready PowerShell script (PS 5.1 compatible)
- Hostname file input — drop in your list and run
- Full $entity fetch per device — guarantees all fields including usersLoggedOn
- Last logon UPN resolution via Graph API user lookup
- Enrolled-by UPN from enrolledByUserPrincipalName field
- OS friendly name mapping (Win10 1507 → Win11 24H2, macOS Big Sur → Sequoia)
- Duplicate device detection with WARN flag
- NOT FOUND placeholder rows for unmatched hostnames
- Also supports all-devices mode with client-side OS filter
- 33-column CSV export with timestamped filename
- This README with full setup, troubleshooting, and Graph permissions

No external modules. No interactive sign-in. PS 5.1 compatible.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- EnrolledByEmail column — who enrolled the device (user or service UPN)
- LastLogonEmail column — most recent interactive logon UPN, resolved from
  usersLoggedOn array (requires User.Read.All permission)
- Full $entity fetch — not a list response; all 33 fields guaranteed present
- Hostname file mode — targeted lookup, fast, no unnecessary bulk pull
- All-devices mode — full tenant export with client-side OS filter
- OS friendly name — Windows build number mapped to release name
- Duplicate detection — flags and includes all records per hostname
- NOT FOUND rows — every input hostname accounted for in the CSV
- 200ms/100ms pacing — reduces throttling risk without slowing excessively
- $select omitted from search — avoids HTTP 400 on Intune filter endpoint
- No external modules — pure PowerShell 5.1 with Invoke-RestMethod

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Endpoint Engineers investigating device enrollment ownership
- IT Admins answering "who enrolled this device?" for compliance or audit
- Service Desk leads checking last logon before device reassignment
- Modern Workplace teams auditing enrollment type and join method at scale
- Anyone who needs enriched device context fast from a hostname list

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, PowerShell, Microsoft Graph API, EnrolledBy, Last Logon,
Device Details, Hostname Lookup, usersLoggedOn, Endpoint Management,
Modern Workplace, Device Audit, enrolledByUserPrincipalName,
Graph Beta, managedDevices entity, Device Enrollment, Intune Automation,
DeviceManagementManagedDevices, User.Read.All, OS Friendly Name

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Get-IntuneEnrolledByDetailsByHostname.ps1 in any text editor.
3. Fill in TenantID, ClientID, ClientSecret, InputFile, and OutputFolder
   in the CONFIGURATION block at the top of the script.
4. Ensure your Azure AD App Registration has admin consent for:
     DeviceManagementManagedDevices.Read.All (required)
     User.Read.All                           (required for LastLogonEmail)
5. Create your hostname .txt file — one hostname per line.
6. Run from PowerShell 5.1 or later.
7. Review the generated CSV in your configured output folder.
8. See TROUBLESHOOTING TIPS if you encounter any issues.

For questions or support, contact the author via the Gumroad product page.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script make any changes to devices?
A: No. Fully read-only. Reads and exports only.

Q: Why does the script fetch each device individually instead of using $select?
A: The Intune managedDevices list endpoint does not return usersLoggedOn
   regardless of $select. The only way to get this field is to fetch the
   full $entity record by device ID. Additionally, $filter + $select on
   this endpoint returns HTTP 400 — so $select is omitted from the search.

Q: Can I run this for a single hostname?
A: Yes. Put one hostname in the .txt file and run normally.

Q: What if a hostname has two Intune records?
A: Both records are included in the CSV. The console shows a DUPLICATE
   warning with the count. This is common for re-enrolled devices where
   the old record was not cleaned up.

Q: LastLogonEmail is blank for some devices — why?
A: Three possible reasons: (1) User.Read.All permission not granted,
   (2) device has never had an interactive user logon recorded by Intune,
   (3) the userId in usersLoggedOn could not be resolved (deleted user).

Q: What PowerShell version is required?
A: PowerShell 5.1 or later. No external modules required.

Q: How does all-devices mode work?
A: It pulls all managed devices without any server-side filter, then applies
   the $OSFilter client-side. It then fetches a full entity per device.
   For large tenants this is slow — use hostname file mode where possible.

Q: The OSFriendlyName shows "Unknown Build" — what does this mean?
A: The device is on a Windows build not yet in the mapping table. The raw
   OSVersion value is still exported. Update the Get-WindowsFriendlyName
   function with the new build number when Microsoft releases it.

================================================================================
  End of README - Get-IntuneEnrolledByDetailsByHostname.ps1
  Author : Sethu Kumar B
================================================================================
