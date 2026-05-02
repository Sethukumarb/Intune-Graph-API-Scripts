================================================================================
  README - Remove-IntuneAndAutopilotDeviceBySerial.ps1
================================================================================

SCRIPT NAME
-----------
Remove-IntuneAndAutopilotDeviceBySerial.ps1

FOLDER NAME
-----------
Intune-Autopilot-Device-Removal


--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Permanently removes Windows device records from both Microsoft Intune
(managedDevices) and Windows Autopilot (windowsAutopilotDeviceIdentities)
by serial number using the Microsoft Graph API.

Includes a built-in Dry Run mode (enabled by default) so you can safely
preview exactly what will be deleted before committing any changes.


--------------------------------------------------------------------------------
WHAT THE SCRIPT DELETES
--------------------------------------------------------------------------------
  Intune Managed Device      - DELETE /deviceManagement/managedDevices/{id}
  Autopilot Device Identity  - DELETE /deviceManagement/windowsAutopilotDeviceIdentities/{id}

WHAT THE SCRIPT DOES NOT DELETE
--------------------------------
  Azure AD / Entra ID Device Object - Script looks up and REPORTS the Azure AD
  device but does NOT delete it. No permission is requested for deletion.
  If needed, delete the Azure AD device manually from the Entra portal.


--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES (STEP BY STEP)
--------------------------------------------------------------------------------
1.  Reads serial numbers from remove_inputserialnumbers.txt (one per line)
2.  Validates input count against $MaxBatchSize safety cap
3.  Authenticates to Microsoft Graph API using Azure AD App credentials
4.  Bulk pulls ALL Windows Intune managed devices into a hashtable lookup
5.  Bulk pulls ALL Autopilot device identities into a hashtable lookup
6.  For each serial number:
      - Matches against Intune hashtable - deletes all matched records
      - Matches against Autopilot hashtable - deletes all matched records
      - Looks up Azure AD device via azureADDeviceId - REPORTS only, no delete
      - Handles duplicate records per serial independently
7.  Exports full audit results to a timestamped CSV file
8.  Writes detailed log file and full PowerShell transcript

NOTE ON LOOKUP STRATEGY:
  Script does NOT use $filter on serial number. These Graph API endpoints
  return HTTP 500 when $filter is used. Instead the script bulk pulls all
  records and does client-side hashtable lookup. This is reliable and fast.


--------------------------------------------------------------------------------
DRY RUN MODE (DEFAULT - ENABLED)
--------------------------------------------------------------------------------
$DryRun = $true   <-- DEFAULT. Safe. No DELETE calls are made.
$DryRun = $false  <-- LIVE mode. Device records WILL be permanently deleted.

ALWAYS run with $DryRun = $true first.
Review the CSV output carefully.
Only set $DryRun = $false when you are confident the correct records are listed.

WARNING: Deletion is PERMANENT and CANNOT BE UNDONE.


--------------------------------------------------------------------------------
BATCH CAP SAFETY GATE
--------------------------------------------------------------------------------
$MaxBatchSize = 1   <-- DEFAULT. Script aborts if input has more than 1 serial.

This is an intentional safety gate to prevent accidental mass deletions.
Increase this value to match your expected input size before running.
Set to 0 to disable the cap entirely (no limit).

Example:
  $MaxBatchSize = 50    -- allows up to 50 serials per run
  $MaxBatchSize = 0     -- no limit


--------------------------------------------------------------------------------
CSV OUTPUT COLUMNS
--------------------------------------------------------------------------------
  SerialNumber          - Serial from input file
  DeviceName            - Device name from Intune or Autopilot record
  Manufacturer          - Device manufacturer
  Model                 - Device model
  RecordType            - Intune / Autopilot / Azure AD / Intune (Duplicate X/Y)
  IntuneDeviceID        - Intune managed device GUID
  IntuneDeleteStatus    - DELETED / DRY RUN / NOT FOUND / FAILED / N/A
  IntuneDeleteNote      - Detail message for Intune action
  AutopilotDeviceID     - Autopilot device identity GUID
  AutopilotDeleteStatus - DELETED / DRY RUN / NOT FOUND / FAILED / N/A
  AutopilotDeleteNote   - Detail message for Autopilot action
  AzureADDeviceID       - Azure AD device GUID (from Intune record)
  AzureADStatus         - SKIPPED with note (exists or not found)
  OverallResult         - Summary result for the row
  Timestamp             - Date and time of action

RESULT VALUES:
  DELETED    - Record found and successfully deleted
  DRY RUN    - Would be deleted (DryRun = $true)
  NOT FOUND  - No record found for this serial in that endpoint
  FAILED     - Delete call returned an error (see Note column for detail)
  SKIPPED    - Not attempted (no permission or not applicable)


--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later (fully compatible with PS 7.x)
- TLS 1.2 enabled (script enables this automatically)
- Azure AD App Registration with Client Secret
- Admin consent granted for required Graph API permissions (see below)
- remove_inputserialnumbers.txt placed in the same folder as the script
- Internet access to login.microsoftonline.com and graph.microsoft.com


--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Both permissions must be Application type (not Delegated).
Admin consent must be granted for both.

  Permission 1: DeviceManagementManagedDevices.ReadWrite.All
    - Read and delete Intune managed device records

  Permission 2: DeviceManagementServiceConfig.ReadWrite.All
    - Read and delete Windows Autopilot device identity records

Steps to grant permissions:
  1. Go to Azure Portal > Azure Active Directory > App Registrations
  2. Open your App Registration
  3. Go to API Permissions > Add a Permission > Microsoft Graph
  4. Select Application Permissions
  5. Search and add both permissions listed above
  6. Click Grant Admin Consent for your tenant
  7. Confirm both show green checkmark (Granted)

NOTE: Azure AD device deletion permission is NOT required or requested.
      Azure AD device removal must be done manually from the Entra portal.


--------------------------------------------------------------------------------
HOW TO CONFIGURE THE SCRIPT
--------------------------------------------------------------------------------
Open the script and update the CONFIGURATION section at the top:

  $TenantID     = "your-tenant-id"
  $ClientID     = "your-client-id"
  $ClientSecret = "your-client-secret"
  $DryRun       = $true           -- keep true until ready to delete
  $MaxBatchSize = 1               -- increase to match your input count

Input file name (default, do not change unless needed):
  $InputFileName = "remove_inputserialnumbers.txt"

Place remove_inputserialnumbers.txt in the same folder as the script.
Format: One serial number per line.
Lines starting with # and blank lines are ignored.

Example remove_inputserialnumbers.txt:
  # Devices scheduled for removal - May 2026
  SN1234567890
  SN0987654321
  ABCDEF123456


--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
RECOMMENDED WORKFLOW:

Step 1 - Dry Run first (default):
  1. Set $DryRun = $true (already default)
  2. Set $MaxBatchSize to match your input count
  3. Open PowerShell and navigate to script folder:
       cd "C:\Scripts\Intune-Autopilot-Device-Removal"
  4. Run the script:
       .\Remove-IntuneAndAutopilotDeviceBySerial.ps1
  5. Review the CSV output - verify correct devices are listed
  6. Check for any duplicates flagged in the summary

Step 2 - Live deletion (after confirming Dry Run):
  1. Set $DryRun = $false
  2. Run the script again
  3. Review CSV and log for DELETED / FAILED results

If execution policy blocks the script:
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass


--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console output uses color-coded status:
  Cyan   - Section headers and completion banner (Dry Run mode)
  Red    - Live mode banner and completion (LIVE mode warning)
  Green  - Successfully deleted records
  Yellow - Warnings, not found, dry run actions
  Red    - Errors and failed deletes
  Gray   - General information

Files generated in the script folder (timestamped):
  [DRY RUN] RemoveDevices_YYYYMMDD_HHmmss.csv
  [DRY RUN] RemoveDevices_YYYYMMDD_HHmmss.log
  [DRY RUN] RemoveDevices_Transcript_YYYYMMDD_HHmmss.log

  RemoveDevices_YYYYMMDD_HHmmss.csv
  RemoveDevices_YYYYMMDD_HHmmss.log
  RemoveDevices_Transcript_YYYYMMDD_HHmmss.log

Summary at end of run shows:
  Mode                  : DRY RUN or LIVE
  Total serials         : count from input file
  Intune deleted        : count of Intune records deleted or would delete
  Autopilot deleted     : count of Autopilot records deleted or would delete
  Not found (either)    : count of serials with no match in either endpoint
  Failures              : count of delete errors
  Azure AD found        : count found in Azure AD (skipped - no delete permission)
  Duplicates            : listed per serial if multiple records found


--------------------------------------------------------------------------------
DUPLICATE DEVICE HANDLING
--------------------------------------------------------------------------------
If a serial number has multiple records in Intune or Autopilot (duplicate
enrollments), the script processes and deletes EACH record independently.

The CSV RecordType column will show:
  Intune (Duplicate 1/2)
  Intune (Duplicate 2/2)

The summary flags which input serials had duplicates and how many records
were found across both Intune and Autopilot.


--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
1. PERMANENT DELETION - NO UNDO
   Live mode deletions cannot be reversed. Always run Dry Run first.

2. AZURE AD DEVICE NOT DELETED
   Script reports whether the Azure AD device exists but does not delete it.
   Go to Entra portal > Devices and delete manually if required.

3. BULK PULL APPROACH
   Script pulls ALL Intune and Autopilot records before processing.
   In large environments (10,000+ devices) the pull may take several minutes.
   This is normal and expected behavior.

4. WINDOWS ONLY FILTER ON INTUNE
   Intune pull is filtered to operatingSystem eq 'Windows' to reduce data
   volume. Non-Windows devices are not included in the lookup.

5. BATCH CAP DEFAULT IS 1
   The default $MaxBatchSize = 1 means the script will abort if more than
   1 serial is in the input file. This is intentional. Increase before use.

6. THROTTLE PROTECTION
   Script retries automatically on HTTP 429 (Too Many Requests) up to 5
   times using Retry-After header value plus random jitter.

7. CREDENTIAL SECURITY
   Credentials are cleared from memory at end of script run.
   Do not commit the script with credentials filled in.
   Consider using environment variables or Azure Key Vault in production.

8. NO $FILTER ON SERIAL NUMBER
   Graph API returns HTTP 500 when $filter is used on serialNumber for
   managedDevices and windowsAutopilotDeviceIdentities endpoints.
   Script uses bulk pull and client-side hashtable lookup instead.


--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Issue   : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret values are correct.
          Check the client secret has not expired in Azure portal.

Issue   : 403 Forbidden on API calls
Fix     : Confirm both permissions are added as Application type (not Delegated)
          and admin consent is granted. Check green checkmark in Azure portal.

Issue   : BATCH CAP EXCEEDED error on startup
Fix     : Increase $MaxBatchSize in the configuration section to match or
          exceed the number of serials in your input file.

Issue   : Input file not found error
Fix     : Confirm remove_inputserialnumbers.txt is in the exact same folder
          as the script. File name must match exactly.

Issue   : All serials show NOT FOUND
Fix     : Verify the devices exist in Intune and Autopilot by checking
          the Intune portal manually. Confirm serial numbers are correct
          with no leading/trailing spaces in the TXT file.

Issue   : Some deletes show FAILED
Fix     : Check the log file for HTTP error codes.
          Common causes: record already deleted, insufficient permissions,
          throttling exceeded max retries, or network timeout.

Issue   : Duplicate records flagged in summary
Fix     : Review the CSV - each duplicate is listed as a separate row.
          Script deletes all duplicates. This is expected and correct behavior.

Issue   : Script blocked by execution policy
Fix     : Run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Issue   : Azure AD device still exists after script run
Fix     : Expected. Script does not delete Azure AD devices.
          Go to Entra portal > Devices, search by device name or serial,
          and delete the object manually.


================================================================================
  GUMROAD LISTING INFORMATION
================================================================================

LISTING TITLE
-------------
PowerShell Script - Remove Intune & Autopilot Devices by Serial Number (Dry Run + Graph API)


PRODUCT DESCRIPTION
-------------------
A production-ready PowerShell script that removes Windows device records from
both Microsoft Intune and Windows Autopilot by serial number using the Microsoft
Graph API - with a built-in Dry Run mode for safe previewing before any deletion.

Simply provide a list of serial numbers in a text file, run the script in Dry Run
mode first to verify what will be deleted, then switch to Live mode to execute.
The script handles everything automatically - authentication, bulk data pull,
hashtable lookup, deletion, duplicate handling, throttle protection, and full
CSV and log export.

Designed for IT administrators who need a reliable, auditable, and safe method
to clean up retired, replaced, or incorrectly enrolled Windows devices from
Intune and Autopilot without manually searching the portal one device at a time.

This script targets both:
  - managedDevices (Intune enrolled device records)
  - windowsAutopilotDeviceIdentities (Autopilot registered device records)

Azure AD device objects are looked up and reported but NOT deleted, keeping
the script within a safe and minimal permission scope.


KEY FEATURES
------------
- Dry Run mode by default - preview all actions before any deletion
- Deletes from BOTH Intune managed devices AND Autopilot identities in one run
- Input via simple TXT file - one serial number per line
- Batch cap safety gate - prevents accidental mass deletions ($MaxBatchSize)
- Bulk pull with automatic pagination - handles large environments reliably
- Client-side hashtable lookup - avoids Graph API $filter HTTP 500 errors
- Duplicate record detection - each duplicate processed and deleted independently
- Azure AD device lookup and reporting (no delete - minimal permission scope)
- 429 throttle protection with automatic retry and Retry-After backoff
- Color-coded console output - Cyan for Dry Run, Red for Live mode
- Timestamped CSV export with per-record status for full audit trail
- Detailed log file and full PowerShell transcript
- Credentials cleared from memory after run
- Fully compatible with PowerShell 5.1 and 7.x
- No third-party modules required


WHO THIS SCRIPT IS FOR
----------------------
- IT Administrators managing Windows devices in Microsoft Intune
- System Engineers offboarding or replacing devices at scale
- Helpdesk teams removing incorrectly enrolled or duplicate device records
- Intune consultants automating device lifecycle and decommission workflows
- Organizations running regular device retirement or hardware refresh cycles


SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Windows Autopilot, Graph API, Device Management,
Remove Intune Device, Delete Autopilot Device, Serial Number, Dry Run,
Intune Automation, managedDevices, windowsAutopilotDeviceIdentities,
Device Offboarding, Endpoint Management, Azure AD, Entra ID, IT Admin,
Device Cleanup, Device Retirement, Bulk Delete, Intune Script


BUYER INSTRUCTIONS
------------------
1.  Download and extract the ZIP file
2.  Open Remove-IntuneAndAutopilotDeviceBySerial.ps1 in a text editor
3.  Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION section
4.  Set $MaxBatchSize to match or exceed your expected serial count
5.  Leave $DryRun = $true for the first run
6.  Create remove_inputserialnumbers.txt in the same folder (one serial per line)
7.  Open PowerShell and run the script
8.  Review the CSV output carefully - verify correct devices are listed
9.  Set $DryRun = $false and run again to execute live deletions
10. Check Entra portal and delete Azure AD device objects manually if required
11. Full setup and troubleshooting instructions are in this README.txt file


COMMON QUESTIONS / FAQ
-----------------------
Q: Does the script delete the Azure AD / Entra ID device object?
A: No. The script looks up and reports whether the Azure AD device exists
   but does not delete it. Delete the Azure AD object manually from Entra portal.

Q: Is it safe to run for the first time?
A: Yes. Dry Run mode is enabled by default ($DryRun = $true). No deletions
   are made. Review the CSV output before switching to Live mode.

Q: What if a serial has multiple Intune or Autopilot records (duplicates)?
A: Each duplicate record is processed and deleted independently. The CSV
   shows each as a separate row with a duplicate label. The summary flags
   which serials had duplicates and how many records were found.

Q: Why does the script pull all devices instead of filtering by serial?
A: Microsoft Graph API returns HTTP 500 errors when $filter is used on
   serialNumber for these endpoints. Bulk pull with client-side hashtable
   lookup is the reliable workaround used by this script.

Q: How many serials can I process in one run?
A: The default batch cap is 1 serial (safety gate). Increase $MaxBatchSize
   to match your needs. Set to 0 for no limit.

Q: How long does the script take for large environments?
A: Initial bulk pull for 10,000+ devices may take 2-5 minutes. Deletion
   speed depends on serial count and throttle handling. Progress is logged
   in real time on the console.

Q: What happens if a serial is not found in Intune or Autopilot?
A: It is logged as NOT FOUND and skipped safely. The CSV records the result.
   No error is thrown and the script continues with the next serial.

Q: Does the script work with PowerShell 7?
A: Yes. The script requires PowerShell 5.1 or later and is fully compatible
   with PowerShell 7.x on Windows.

Q: Are any third-party modules required?
A: No. The script uses only built-in PowerShell cmdlets and direct Graph API
   REST calls. No additional modules need to be installed.

Q: What two Graph API permissions are required?
A: DeviceManagementManagedDevices.ReadWrite.All (Intune read and delete)
   DeviceManagementServiceConfig.ReadWrite.All (Autopilot read and delete)
   Both must be Application type with admin consent granted.

================================================================================
  END OF README
================================================================================
