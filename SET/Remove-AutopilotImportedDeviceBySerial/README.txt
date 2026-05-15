================================================================================
  README - Remove-AutopilotImportedDeviceBySerial.ps1
================================================================================

SCRIPT NAME
-----------
Remove-AutopilotImportedDeviceBySerial.ps1

FOLDER NAME
-----------
Autopilot-ImportedDevice-Cleanup


--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Removes device entries from the Microsoft Graph API endpoint
importedWindowsAutopilotDeviceIdentities by serial number.

IMPORTANT: This endpoint stores ALL imported device records regardless of
import status - including pending, completed, and errored entries.
Running this script will delete any matching record, not just pending/staging
records. Completed imports WILL be removed and the completed count WILL
decrease.


--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Reads serial numbers from Serials.txt (one per line)
2. Authenticates to Microsoft Graph API using Azure AD App credentials
3. Fetches ALL records from importedWindowsAutopilotDeviceIdentities
4. Matches serial numbers from TXT against fetched records
5. Deletes each matched record one by one (Graph API has no bulk delete)
6. Handles 429 throttling with automatic retry and backoff
7. Exports results to a timestamped CSV file
8. Writes a detailed log file and transcript for auditing

OUTPUT CSV COLUMNS:
  SerialNumber, ImportedDeviceID, ImportStatus,
  ErrorCode, ErrorName, DeleteResult, DeleteDetail

DELETE RESULT VALUES:
  deleted   - Record successfully removed
  not found - Serial not present in endpoint (already clean or never imported)
  failed    - Delete call returned an error


--------------------------------------------------------------------------------
WHAT THIS SCRIPT DOES NOT AFFECT
--------------------------------------------------------------------------------
- windowsAutopilotDeviceIdentities (fully registered Autopilot devices)
- Intune managed device records
- Azure AD device objects
- Group tag assignments
- Entra ID / Azure AD joined device entries


--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- TLS 1.2 enabled (script enables this automatically)
- Azure AD App Registration with a Client Secret
- Admin consent granted for required Graph API permission (see below)
- Serials.txt file placed in the same folder as the script
- Internet access to reach login.microsoftonline.com and graph.microsoft.com


--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSION
--------------------------------------------------------------------------------
Permission Type : Application (not Delegated)
Permission Name : DeviceManagementServiceConfig.ReadWrite.All
Admin Consent   : Required

Steps to grant:
  1. Go to Azure Portal > Azure Active Directory > App Registrations
  2. Open your App Registration
  3. Go to API Permissions > Add a Permission > Microsoft Graph
  4. Select Application Permissions
  5. Search and add: DeviceManagementServiceConfig.ReadWrite.All
  6. Click Grant Admin Consent


--------------------------------------------------------------------------------
HOW TO CONFIGURE THE SCRIPT
--------------------------------------------------------------------------------
Open the script and fill in the CONFIGURATION section at the top:

  $TenantID     = "your-tenant-id"
  $ClientID     = "your-client-id"
  $ClientSecret = "your-client-secret"

The Serials.txt file should be in the same folder as the script.
Format: One serial number per line.
Blank lines and lines starting with # are ignored (use # for comments).

Example Serials.txt:
  # Devices to remove - April 2026
  SN1234567890
  SN0987654321
  ABCDEF123456


--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
1. Open PowerShell (Run as Administrator recommended)
2. Navigate to the script folder:
     cd "C:\Scripts\Autopilot-ImportedDevice-Cleanup"
3. Run the script:
     .\Remove-AutopilotImportedDeviceBySerial.ps1
4. Review the console output during execution
5. Check the CSV and log files generated in the same folder when complete

If execution policy blocks the script:
     Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass


--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console output shows real-time progress with color-coded status:
  Cyan   - Section headers and completion banner
  Green  - Successfully deleted records
  Yellow - Serials not found in endpoint
  Red    - Errors or failed deletes
  Gray   - General information

Files generated in the script folder (timestamped):
  AutopilotStagingDelete_YYYYMMDD_HHmmss.csv
  AutopilotStagingDelete_YYYYMMDD_HHmmss.log
  AutopilotStagingDelete_Transcript_YYYYMMDD_HHmmss.log

Summary at end of run:
  Deleted   : X  (successfully removed)
  Not found : X  (not present in endpoint)
  Failed    : X  (delete errors - check log)


--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
1. DELETES COMPLETED IMPORTS TOO
   This script removes ALL matching records from importedWindowsAutopilotDeviceIdentities
   regardless of import status. Completed device imports WILL be deleted.
   The completed device count in Intune will decrease accordingly.

2. DOES NOT REMOVE FROM AUTOPILOT DEVICE LIST
   This script only removes from the import history/queue endpoint.
   It does NOT remove devices from windowsAutopilotDeviceIdentities.
   To fully remove a device from Autopilot, additional steps are required.

3. NO BULK DELETE IN GRAPH API
   Microsoft Graph API does not support bulk delete for this endpoint.
   Each record is deleted individually. Large batches may take several minutes.

4. THROTTLE HANDLING
   Script automatically retries on HTTP 429 (Too Many Requests) up to 5 times
   with Retry-After header respected plus random jitter.

5. DUPLICATE SERIALS IN ENDPOINT
   If a serial appears multiple times in the endpoint, the most recently
   created record is selected for deletion. Others are left untouched.

6. CREDENTIALS SECURITY
   Do not commit the script with credentials filled in.
   Consider using environment variables or Azure Key Vault for production use.


--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Issue   : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret. Check app registration exists.
          Confirm client secret has not expired.

Issue   : 403 Forbidden on API calls
Fix     : Confirm DeviceManagementServiceConfig.ReadWrite.All permission is added
          as Application permission and admin consent is granted.

Issue   : Serials file not found error
Fix     : Ensure Serials.txt is in the exact same folder as the script.
          File name is case-sensitive on some systems.

Issue   : All serials show "not found"
Fix     : Verify the devices were actually imported via the Autopilot import
          process. Check Intune > Devices > Enrollment > Windows Autopilot
          Devices > Import History to confirm records exist.

Issue   : Delete failed for some serials
Fix     : Check the log file for HTTP error codes. Common causes:
          - Record already deleted by another process
          - Insufficient permissions
          - Throttling exceeded max retries

Issue   : Script blocked by execution policy
Fix     : Run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass


================================================================================
  GUMROAD LISTING INFORMATION
================================================================================

LISTING TITLE
-------------
PowerShell Script - Remove Autopilot Imported Devices by Serial Number (Graph API)


PRODUCT DESCRIPTION
-------------------
A ready-to-use PowerShell script that removes Windows Autopilot imported device
records from Microsoft Intune by serial number using the Microsoft Graph API.

Simply provide a list of serial numbers in a text file, run the script, and it
handles everything automatically - authentication, fetching records, matching,
deleting, throttle handling, and exporting results to CSV.

Ideal for IT admins who need to clean up failed, duplicate, or unwanted Autopilot
import records quickly and safely without manual work in the Intune portal.

This script targets the importedWindowsAutopilotDeviceIdentities endpoint, which
stores all device import records (pending, completed, and errored). Use it to
remove specific entries from the import history by serial number.


KEY FEATURES
------------
- Input via simple TXT file - one serial number per line
- Automatic pagination - handles large environments with 1000+ records
- Smart duplicate handling - selects most recent record per serial
- 429 throttle protection - automatic retry with backoff
- Color-coded console output for easy monitoring
- Timestamped CSV export with full delete results
- Detailed log file and full transcript for auditing
- Safe to run - only touches the specified serials
- Supports comment lines (#) and blank lines in input file
- No third-party modules required - uses only built-in PowerShell


WHO THIS SCRIPT IS FOR
----------------------
- IT Administrators managing Windows Autopilot in Microsoft Intune
- System Engineers cleaning up Autopilot import records after bulk imports
- Helpdesk teams removing failed or duplicate Autopilot import entries
- Intune consultants automating device lifecycle management tasks


SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Windows Autopilot, Graph API, Device Management,
Autopilot Import, Remove Autopilot Device, Serial Number, Intune Automation,
importedWindowsAutopilotDeviceIdentities, Intune Script, IT Admin, Endpoint
Management, Azure AD, Device Cleanup


BUYER INSTRUCTIONS
------------------
1. Download and extract the ZIP file
2. Open Remove-AutopilotImportedDeviceBySerial.ps1 in a text editor
3. Fill in your TenantID, ClientID, and ClientSecret in the CONFIGURATION section
4. Create Serials.txt in the same folder with one serial number per line
5. Open PowerShell and run the script
6. Review console output and check the generated CSV and log files
7. Full setup instructions are in this README.txt file


COMMON QUESTIONS / FAQ
-----------------------
Q: Does this script remove devices from the main Autopilot device list?
A: No. It only removes records from the import history endpoint
   (importedWindowsAutopilotDeviceIdentities). The main Autopilot device
   list (windowsAutopilotDeviceIdentities) is not affected.

Q: Will it delete completed imports or only pending/staging entries?
A: It will delete any matching record regardless of import status - including
   completed, pending, and errored entries. The completed count will decrease.

Q: Do I need a special license for the Azure AD app?
A: No special license needed. You need an App Registration in Azure AD with
   the DeviceManagementServiceConfig.ReadWrite.All application permission
   and admin consent granted.

Q: What happens if a serial number is not found?
A: It is logged and skipped safely. The CSV will show "not found" for that
   serial. No error is thrown and the script continues with the next serial.

Q: Can I run this on a large list of devices?
A: Yes. The script handles pagination automatically and includes throttle
   protection with automatic retry for large environments.

Q: Is PowerShell 7 supported?
A: The script requires PowerShell 5.1 or later. It works on both 5.1 and 7.x.

Q: Does the script make any changes outside of deleting the specified records?
A: No. It only deletes records that match the serial numbers provided in
   Serials.txt. No other data is modified.

================================================================================
  END OF README
================================================================================
