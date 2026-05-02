================================================================================
  README - Import-AutopilotDevices.ps1
================================================================================

SCRIPT NAME
-----------
Import-AutopilotDevices.ps1

FOLDER NAME
-----------
Autopilot-Device-Import


--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Bulk imports Windows Autopilot devices into Microsoft Intune using hardware
hash CSV files via the Microsoft Graph API.

Supports multiple CSV files in one run, automatic batching up to 500 devices
per API call, Group Tag assignment during import, and real-time status polling
until all devices reach a terminal import state (complete or error).


--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES (STEP BY STEP)
--------------------------------------------------------------------------------
1.  Scans the Import\ subfolder for all .csv hardware hash files
2.  Validates each CSV has the required columns
3.  Skips rows with blank serial number or hardware hash
4.  Authenticates to Microsoft Graph API using Azure AD App credentials
5.  Batches devices (up to 500 per API call) and POSTs to Graph import endpoint
6.  Import endpoint returns 204 No Content (no IDs in response)
7.  Waits 10 seconds then queries staging endpoint to resolve import IDs by serial
8.  Filters out stale records from previous runs using batch submit timestamp
9.  Polls import status every 30 seconds until all devices reach terminal state
    or the 30 minute poll timeout is reached
10. Exports full per-device import status to timestamped CSV
11. Writes detailed log file and full PowerShell transcript

TERMINAL IMPORT STATES:
  complete           - Device successfully imported into Autopilot
  error              - Import failed (error code and name in StatusDetail column)
  completedWithError - Imported with partial error

NON-TERMINAL STATES (still processing):
  pending            - Processing not yet started
  unknown            - Initial state before Graph processes the record


--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
Place one or more hardware hash CSV files inside the Import\ subfolder.
The Import\ folder must be in the same directory as the script.

REQUIRED COLUMNS (must be present in every CSV):
  Device Serial Number  - device serial number
  Hardware Hash         - base64 encoded hardware hash string

OPTIONAL COLUMNS (used if present, safely ignored if missing):
  Windows Product ID    - Windows product key (can be blank)
  Group Tag             - Autopilot group tag applied during import (can be blank)

The CSV format matches exactly what is exported by the Get-WindowsAutoPilotInfo
PowerShell script - the standard tool used to capture hardware hashes from devices.

Example CSV header row:
  Device Serial Number,Windows Product ID,Hardware Hash,Group Tag

Notes:
  - Multiple CSV files are supported in one run
  - Each file is validated independently
  - Files with missing required columns are skipped with an error logged
  - Rows with blank serial or hash are skipped with a warning logged
  - Blank Group Tag and Windows Product ID are omitted from the API request
    (not sent as empty string - avoids API validation errors)


--------------------------------------------------------------------------------
BATCH SIZE
--------------------------------------------------------------------------------
$BatchSize = 500   <-- Maximum allowed by Graph API per import call

Large CSV files are automatically split into batches of 500.
Multiple batches are submitted sequentially with a short pause between each.
All batches are polled together in a single status polling loop.


--------------------------------------------------------------------------------
POLL SETTINGS
--------------------------------------------------------------------------------
$PollIntervalSeconds = 30   -- How often to check import status
$PollTimeoutMinutes  = 30   -- Maximum time to wait before stopping poll

If devices are still pending when timeout is reached, the script exports
whatever status is available and logs a timeout warning. You can re-check
status manually in Intune > Devices > Enrollment > Windows Autopilot Devices.

For large imports (500+ devices), consider increasing $PollTimeoutMinutes.


--------------------------------------------------------------------------------
OUTPUT CSV COLUMNS
--------------------------------------------------------------------------------
  SourceFile       - Name of the CSV file the device came from
  SerialNumber     - Device serial number
  WindowsProductID - Windows product ID (if provided)
  GroupTag         - Group tag applied during import (if provided)
  ImportedDeviceID - Staging record GUID (N/A if ID resolution failed)
  ImportStatus     - complete / error / pending / submitted / SUBMIT FAILED
  StatusDetail     - Error code, error name, registration ID (if applicable)
  BatchNumber      - Which batch this device was submitted in
  SubmittedAt      - Timestamp when the batch was submitted
  StatusCheckedAt  - Timestamp of the last status poll

IMPORT STATUS VALUES:
  complete                   - Successfully imported into Autopilot
  error                      - Import failed (see StatusDetail for error info)
  pending                    - Still processing when poll timeout was reached
  submitted                  - Submitted but ID not yet resolved
  submitted - id not resolved - Submitted but staging record not found after wait
  SUBMIT FAILED              - API call failed (see StatusDetail for error)


--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later (fully compatible with PS 7.x)
- TLS 1.2 enabled (script enables this automatically)
- Azure AD App Registration with Client Secret
- Admin consent granted for required Graph API permission (see below)
- Import\ subfolder created in the same folder as the script
- One or more hardware hash CSV files placed in the Import\ subfolder
- Internet access to login.microsoftonline.com and graph.microsoft.com


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
  6. Click Grant Admin Consent for your tenant
  7. Confirm green checkmark (Granted) is shown


--------------------------------------------------------------------------------
HOW TO CONFIGURE THE SCRIPT
--------------------------------------------------------------------------------
Open the script and update the CONFIGURATION section at the top:

  $TenantID            = "your-tenant-id"
  $ClientID            = "your-client-id"
  $ClientSecret        = "your-client-secret"
  $BatchSize           = 500     -- do not exceed 500 (Graph API limit)
  $PollIntervalSeconds = 30      -- increase if you want less frequent polling
  $PollTimeoutMinutes  = 30      -- increase for large imports

Folder structure expected:
  C:\Scripts\Autopilot-Device-Import\
      Import-AutopilotDevices.ps1
      Import\
          devices_batch1.csv
          devices_batch2.csv


--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
1. Place hardware hash CSV file(s) in the Import\ subfolder
2. Open PowerShell and navigate to the script folder:
     cd "C:\Scripts\Autopilot-Device-Import"
3. Run the script:
     .\Import-AutopilotDevices.ps1
4. Monitor console output for real-time batch submission and poll status
5. Review the CSV output when complete for per-device import results

If execution policy blocks the script:
  Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass


--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console output uses color-coded status:
  Cyan   - Section headers and completion banner
  Green  - Successfully imported devices (complete)
  Yellow - Warnings, pending devices, poll timeout
  Red    - Errors and failed imports
  Gray   - General information

Files generated in the script folder (timestamped):
  AutopilotImport_YYYYMMDD_HHmmss.csv
  AutopilotImport_YYYYMMDD_HHmmss.log
  AutopilotImport_Transcript_YYYYMMDD_HHmmss.log

Summary at end of run shows:
  Files processed    : how many CSV files were loaded vs total found
  Total devices      : total valid devices submitted
  Batches submitted  : how many API calls were made
  COMPLETE           : devices successfully imported
  ERRORS             : devices that failed import
  PENDING / UNKNOWN  : devices still processing when poll ended


--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
1. IMPORT ENDPOINT RETURNS NO IDs
   The Graph API /import endpoint returns HTTP 204 No Content with no body.
   The script resolves import IDs by querying the staging endpoint after
   submit and matching by serial number. A 10 second wait is built in
   before the ID resolution query to allow records to appear.

2. STALE RECORD FILTERING
   The staging endpoint retains records from previous runs. On re-runs,
   the same serial may have both old and new records. The script filters
   to records created at or after the batch submit time to avoid picking
   up stale records that could cause false status reporting.

3. RE-IMPORTING ALREADY REGISTERED DEVICES
   If a device is already registered in Autopilot, the import will return
   error status with code 806 (ZtdDeviceAlreadyAssigned). This is expected
   and is not a script bug. The device already exists in Autopilot.

4. GROUP TAG IS APPLIED AT IMPORT TIME
   Group Tag is applied when the device is submitted to the import endpoint.
   It cannot be changed by re-running this script for already-registered
   devices. Use the Intune portal or a separate script to update Group Tags
   on existing Autopilot devices.

5. POLL TIMEOUT FOR LARGE IMPORTS
   For imports of 500+ devices, the default 30 minute poll timeout may not
   be enough. Increase $PollTimeoutMinutes if devices are still pending
   when the script ends. Import continues in the cloud regardless.

6. MULTIPLE CSV FILES
   All CSV files in the Import\ folder are processed in alphabetical order.
   Results from all files are combined into a single output CSV.

7. NO THIRD-PARTY MODULES REQUIRED
   Script uses only built-in PowerShell cmdlets and direct Graph API REST
   calls. The Microsoft.Graph PowerShell module is NOT required.


--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Issue   : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Check that the client secret has not expired in Azure portal.

Issue   : 403 Forbidden on API calls
Fix     : Confirm DeviceManagementServiceConfig.ReadWrite.All is added as
          Application permission and admin consent is granted.

Issue   : Import folder not found error
Fix     : Create an Import\ subfolder in the same folder as the script.
          Place hardware hash CSV files inside the Import\ folder.

Issue   : CSV skipped - missing required columns
Fix     : Confirm the CSV has columns named exactly:
            Device Serial Number
            Hardware Hash
          Column names are case-sensitive. Use the exact names above.
          The Get-WindowsAutoPilotInfo script produces the correct format.

Issue   : ImportedDeviceID shows N/A for some devices
Fix     : Staging records may not have appeared within the 10 second wait.
          This can happen when the API is under load. The device was still
          submitted - check Intune portal for actual import status.
          You can also increase the wait time in the script after Submit-AutopilotBatch.

Issue   : All devices show error with code 806 / ZtdDeviceAlreadyAssigned
Fix     : These devices are already registered in Autopilot. No action needed.
          If you need to re-import with a different Group Tag, delete the
          existing Autopilot record first using Remove-AutopilotImportedDeviceBySerial.ps1
          then re-import.

Issue   : Devices stuck as pending after poll timeout
Fix     : Import is still processing in the cloud. Wait a few minutes and
          check Intune > Devices > Enrollment > Windows Autopilot Devices.
          Increase $PollTimeoutMinutes for future large batch imports.

Issue   : Script blocked by execution policy
Fix     : Run: Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass

Issue   : Single-row CSV causes errors
Fix     : This is handled automatically in v1.6+. The script wraps Import-Csv
          results in @() to force array type for single-row files.


================================================================================
  GUMROAD LISTING INFORMATION
================================================================================

LISTING TITLE
-------------
PowerShell Script - Bulk Import Autopilot Devices from Hardware Hash CSV (Graph API)


PRODUCT DESCRIPTION
-------------------
A production-ready PowerShell script that bulk imports Windows Autopilot devices
into Microsoft Intune from hardware hash CSV files using the Microsoft Graph API.

Drop one or more hardware hash CSV files into the Import folder, run the script,
and it handles everything automatically - validation, batching, submission,
import ID resolution, status polling, and full CSV export with per-device results.

No manual steps in the Intune portal. No third-party modules required. Just
PowerShell and your Azure AD App credentials.

Built for IT teams who need to register large numbers of devices into Autopilot
quickly and reliably, with full visibility into which devices imported successfully
and which ones encountered errors.

Compatible with CSV files generated by the Get-WindowsAutoPilotInfo script -
the standard tool used to capture hardware hashes directly from Windows devices.


KEY FEATURES
------------
- Supports multiple CSV files in a single run - all processed automatically
- Automatic batching - splits large CSV files into batches of up to 500 devices
- Group Tag support - applied per device during import (read from CSV column)
- Handles 204 No Content response from import endpoint - resolves IDs via staging
- Stale record filtering - prevents false status from previous run records
- Real-time status polling every 30 seconds until all devices reach terminal state
- Configurable poll interval and timeout for large imports
- Color-coded console output for real-time monitoring
- Timestamped CSV export with full per-device import status and error details
- Detailed log file and full PowerShell transcript for auditing
- 429 throttle protection with automatic retry and Retry-After backoff
- Fully compatible with PowerShell 5.1 and 7.x
- No third-party modules required


WHO THIS SCRIPT IS FOR
----------------------
- IT Administrators registering new Windows devices into Autopilot at scale
- System Engineers processing hardware hash CSVs from device imaging teams
- Helpdesk teams importing devices received from hardware vendors
- Intune consultants automating Autopilot onboarding workflows
- Organizations deploying Windows Autopilot for the first time or at refresh


SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Windows Autopilot, Graph API, Hardware Hash,
Autopilot Import, Bulk Import, CSV Import, Device Registration, Group Tag,
DeviceManagementServiceConfig, importedWindowsAutopilotDeviceIdentities,
Autopilot Onboarding, Endpoint Management, Azure AD, IT Admin, Intune Script,
Get-WindowsAutoPilotInfo, Device Enrollment, Autopilot Provisioning


BUYER INSTRUCTIONS
------------------
1.  Download and extract the ZIP file
2.  Open Import-AutopilotDevices.ps1 in a text editor
3.  Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION section
4.  Adjust $PollTimeoutMinutes if importing large batches (500+ devices)
5.  Create an Import\ subfolder in the same folder as the script
6.  Place your hardware hash CSV file(s) in the Import\ subfolder
7.  Open PowerShell and run the script:
       .\Import-AutopilotDevices.ps1
8.  Monitor console for real-time batch submission and poll progress
9.  Review the generated CSV for per-device import status and any errors
10. For devices showing error 806, they are already registered in Autopilot
11. Full setup and troubleshooting instructions are in this README.txt file


COMMON QUESTIONS / FAQ
-----------------------
Q: What CSV format does the script expect?
A: The script expects the exact format produced by Get-WindowsAutoPilotInfo.
   Required columns: Device Serial Number, Hardware Hash.
   Optional columns: Windows Product ID, Group Tag.

Q: Can I import devices from multiple CSV files in one run?
A: Yes. Place all CSV files in the Import\ subfolder. The script processes
   all of them in alphabetical order and combines results into one output CSV.

Q: Does the script support Group Tags?
A: Yes. If the CSV has a Group Tag column, the value is applied per device
   during import. Leave the column blank or omit it to import without a tag.

Q: Why does the import endpoint return no device IDs?
A: The Graph API /import endpoint returns HTTP 204 No Content with no response
   body. The script handles this by waiting 10 seconds then querying the
   staging endpoint to resolve import IDs by matching serial numbers.

Q: What happens if a device is already registered in Autopilot?
A: The import returns error status with code 806 (ZtdDeviceAlreadyAssigned).
   This means the device is already in Autopilot. No action is needed unless
   you want to re-import with a different Group Tag, in which case delete the
   existing record first.

Q: How long does the import take?
A: Submission is fast - typically seconds per batch. Processing time on the
   Microsoft side varies. Most imports complete within 5-15 minutes. The
   script polls every 30 seconds and waits up to 30 minutes by default.

Q: What if devices are still pending when the poll timeout ends?
A: The script exports whatever status is available and logs a warning. Import
   continues in the cloud regardless. Check Intune portal after a few minutes.
   Increase $PollTimeoutMinutes for future large batch runs.

Q: Do I need the Microsoft.Graph PowerShell module installed?
A: No. The script uses only built-in PowerShell cmdlets and direct REST API
   calls. No additional modules need to be installed.

Q: Is PowerShell 7 supported?
A: Yes. The script requires PowerShell 5.1 or later and is fully compatible
   with PowerShell 7.x on Windows.

Q: What Graph API permission is required?
A: DeviceManagementServiceConfig.ReadWrite.All as Application permission
   with admin consent granted in your Azure AD tenant.

================================================================================
  END OF README
================================================================================
