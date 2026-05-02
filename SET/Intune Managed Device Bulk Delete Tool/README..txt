================================================================================
  README — Remove-IntuneManagedDeviceByDevicesIDs.ps1
  Author : Sethu Kumar B
  Version: 3.0
================================================================================

SCRIPT NAME
-----------
Remove-IntuneManagedDeviceByDevicesIDs.ps1

FOLDER NAME
-----------
Intune-Device-Management

================================================================================
  !!  CRITICAL WARNING — READ BEFORE RUNNING  !!
================================================================================

  THIS SCRIPT PERMANENTLY DELETES INTUNE MANAGED DEVICE RECORDS.

  - Deletions are IMMEDIATE and IRREVERSIBLE.
  - There is NO recycle bin, NO undo, NO recovery option in Intune.
  - A deleted device record loses all:
      Compliance status, policy assignments, app assignments,
      device history, audit trail, and enrollment state.
  - If the device is still active and enrolled, deleting the record
    will trigger a re-enrollment on next check-in — the device will
    re-appear in Intune but as a NEW record with no history.
  - ALWAYS run Dry-Run mode first. ALWAYS verify the device list
    before setting $DryRun = $false.
  - ALWAYS confirm with your manager or change management process
    before running live on more than a handful of devices.

================================================================================

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Bulk-deletes Intune Managed Device records from Microsoft Intune via the
Microsoft Graph API using a list of Managed Device IDs (GUIDs).

Designed for IT admins decommissioning retired devices, cleaning up stale
Intune records, or removing devices that are no longer active — at scale,
with full control, a batch size safety cap, and a permanent audit log.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
Step 1 — Validates the input file (DeviceIDs.txt) exists and is not empty.

Step 2 — Enforces the batch size cap ($MaxBatchSize).
         If the input file contains MORE device IDs than $MaxBatchSize,
         the script ABORTS before making any API calls. This is a deliberate
         safety gate — you must consciously raise $MaxBatchSize to process
         larger batches.

Step 3 — Authenticates to Microsoft Graph API using app credentials.

Step 4 — For each Device ID in the input file:
           - GET  : Retrieves device details (DeviceName, OS, UPN) for logging
           - DELETE : Removes the Intune managed device record permanently
           In Dry-Run mode: GET is performed but DELETE is skipped.
           Logs each result: DELETED / DRY RUN WOULD DELETE / NOT FOUND / FAILED

Step 5 — Prints and logs a full execution summary.

Step 6 — Security cleanup: clears $ClientSecret and $Token from memory.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Azure AD App Registration with a Client Secret
- Admin consent granted for required Graph API permissions (see below)
- Input file DeviceIDs.txt placed in the same folder as the script
- Change management approval for bulk device deletions (recommended)

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission                                   Type          Purpose
-------------------------------------------  ------------  ---------------------
DeviceManagementManagedDevices.ReadWrite.All Application   Read + delete devices

Grant type : Application permissions (not delegated)
Consent    : Admin consent required

SECURITY NOTE: This permission grants full read AND write access to all Intune
managed device records. Use a dedicated app registration for this script.
Rotate the client secret after use if operating in a high-security environment.
The script clears $ClientSecret and $Token from memory at the end of each run.

--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File name : DeviceIDs.txt
Location  : Same folder as the script ($PSScriptRoot)

Format    : One Intune Managed Device ID (GUID) per line.
            Blank lines are ignored automatically.

Example:
  3f2a1b4c-1234-5678-abcd-9e8f7a6b5c4d
  7c6d5e4f-abcd-1234-5678-1a2b3c4d5e6f
  a1b2c3d4-5678-abcd-ef01-2345678901ab

CRITICAL — MANAGED DEVICE ID vs OTHER IDs:
  The input file requires the INTUNE MANAGED DEVICE ID (GUID).
  This is NOT the same as:
    - Azure AD Device ID
    - Autopilot Device ID
    - Serial Number
    - Hostname / Device Name

  How to find the Intune Managed Device ID:
    Option 1 — Intune Portal:
      Devices > All Devices > click device > Overview
      "Device ID" field shown at the top — this is the Managed Device ID.

    Option 2 — Graph API:
      GET https://graph.microsoft.com/v1.0/deviceManagement/managedDevices
      ?$filter=deviceName eq 'HOSTNAME'&$select=id,deviceName
      The "id" field is the Managed Device ID.

    Option 3 — Export from Intune:
      Devices > All Devices > Export
      Open the CSV — the "Device ID" column contains the Managed Device ID.

  Using the wrong ID type will result in HTTP 404 NOT FOUND errors.
  No device will be deleted — but always verify before live runs.

--------------------------------------------------------------------------------
HOW TO RUN
--------------------------------------------------------------------------------
Step 1 — Place script and DeviceIDs.txt in the same folder.
         One Intune Managed Device ID per line in DeviceIDs.txt.

Step 2 — Open the script and fill in the CONFIGURATION block:

    $TenantID     = "your-tenant-id"
    $ClientID     = "your-app-client-id"
    $ClientSecret = "your-client-secret"
    $DryRun       = $true      ← ALWAYS start here
    $MaxBatchSize = 1          ← Raise this to match your device count

Step 3 — Run in PowerShell 5.1 or later:

    .\Remove-IntuneManagedDeviceByDevicesIDs.ps1

Step 4 — Review the log file in the Logs\ subfolder.
         Verify every device listed is the correct one to delete.
         Check DeviceName, OS, and UPN columns in the log for each ID.

Step 5 — Set $DryRun = $false. Run again to apply live deletions.

Step 6 — Review the live log. Confirm DELETED for all expected rows.
         Investigate any NOT FOUND or FAILED rows.

--------------------------------------------------------------------------------
BATCH SIZE CAP — HOW IT WORKS
--------------------------------------------------------------------------------
$MaxBatchSize defaults to 1.

If DeviceIDs.txt contains MORE IDs than $MaxBatchSize, the script ABORTS
at Step 2 before authenticating or making any API calls.

This is a deliberate safety gate. It forces you to consciously set the batch
size to match your intent before each run. It prevents accidental bulk deletion
if the wrong input file is loaded.

Recommended approach:
  - Start with $MaxBatchSize = 1 for first test.
  - Verify the single deletion works as expected.
  - Raise $MaxBatchSize to match your full batch size when ready.
  - Never set $MaxBatchSize higher than your current input file row count
    unless you intend to process that many devices.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Log file saved to:
  $PSScriptRoot\Logs\Remove-IntuneManagedDevice_[timestamp].log

NOTE: Log file is written to a Logs\ SUBFOLDER inside the script folder —
not directly in the script folder. The Logs\ folder is created automatically
if it does not exist.

LOG ENTRY FORMATS:
  DELETED       — Device successfully deleted (live run)
  DRY RUN | WOULD DELETE — Device found, deletion skipped (dry-run)
  NOT FOUND     — Device ID returned HTTP 404 — already deleted or wrong ID
  FAILED        — Deletion failed — HTTP error code and detail logged

Each log entry includes:
  Timestamp, Level, DeviceName, OS, UPN (UserPrincipalName), Device ID

CONSOLE SUMMARY includes:
  - Mode (Dry Run / Live)
  - Total input count
  - Deleted / Would Delete count
  - Not Found count
  - Failed count
  - Log file path

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- DELETIONS ARE PERMANENT. There is no undo in Intune.

- $MaxBatchSize = 1 is the default safety cap. You must raise this to match
  your input file size. The script aborts if input exceeds the cap.

- INPUT IS MANAGED DEVICE ID (GUID) ONLY. Not hostname, not serial number,
  not Azure AD Device ID, not Autopilot ID. Wrong ID type = 404 errors.

- Active enrolled devices: If you delete the Intune record of a device that
  is still enrolled and active, the device will re-enroll on next check-in
  and create a NEW Intune record. The old record and its history are gone.

- No 429 retry protection on the DELETE loop. For very large batches run
  during off-peak hours to reduce Graph API rate limiting risk.

- Set-StrictMode -Version Latest and $ErrorActionPreference = "Stop" are
  active. Any unhandled error will terminate the script immediately.

- Security cleanup: $ClientSecret and $Token are cleared from memory at the
  end of every run.

- Credentials are intentionally left empty in the distributed version.

- Output log files are timestamped — safe to run multiple times without
  overwriting previous logs.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------
Problem : Script aborts at Step 2 — batch size exceeded
Fix     : Count the IDs in your DeviceIDs.txt and set $MaxBatchSize to that
          number (or higher) in the config block. This is intentional.

Problem : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Confirm app registration exists and secret has not expired.

Problem : Input file not found
Fix     : Confirm DeviceIDs.txt is in the same folder as the script.
          Do not change $InputFile path unless you know what you are doing.

Problem : NOT FOUND (HTTP 404) for a device ID
Fix     : The device was already deleted, or the ID is incorrect.
          Verify the ID is the Intune Managed Device ID (not Azure AD Device
          ID, Autopilot ID, or Serial Number). Re-export from Intune if unsure.

Problem : FAILED with HTTP 403
Fix     : Confirm DeviceManagementManagedDevices.ReadWrite.All is granted
          with admin consent on the app registration.

Problem : FAILED with HTTP 429
Fix     : Graph API rate limit hit. No retry logic on DELETE loop.
          Wait a few minutes and re-run with only the failed IDs.

Problem : Log folder not created
Fix     : Ensure the script has write permission to $PSScriptRoot.
          Run PowerShell as Administrator if needed.

Problem : Device re-appeared in Intune after deletion
Fix     : The device was still active and enrolled. It re-enrolled on next
          check-in. To prevent re-enrollment, retire or wipe the device
          BEFORE deleting the Intune record, or block enrollment for that
          device/user.

Problem : Wrong device deleted
Fix     : Always verify DeviceName, OS, and UPN in the Dry-Run log before
          running live. The log shows full device details per ID before any
          deletion occurs. There is no recovery — prevention is the only option.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Intune Managed Device Bulk Delete Tool — PowerShell + Graph API

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Bulk-delete stale or retired Intune managed device records safely — with full
control, a built-in batch size safety cap, and a permanent audit log.

This PowerShell script reads a list of Intune Managed Device IDs, verifies each
device exists, and permanently removes the records via the Microsoft Graph API.
A built-in batch size cap prevents accidental mass deletion — you must
consciously set the limit before each run. Dry-Run mode shows exactly what would
be deleted before anything is touched.

Every run produces a timestamped log with device name, OS, and user for every
ID processed — so you always have a record of what was removed, when, and by
which run.

No third-party modules required. No user login needed. Built for endpoint
engineers who need precision, auditability, and safety guards when cleaning up
Intune at scale.

IMPORTANT: Deletions are permanent and irreversible. Always run Dry-Run first.
Always verify your device ID list before going live.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Bulk Intune managed device deletion via Managed Device ID list
- Dry-Run mode default — preview all deletions before applying, zero risk
- Batch size cap ($MaxBatchSize) — script aborts if input exceeds limit
  preventing accidental mass deletion
- Per-device GET before DELETE — logs DeviceName, OS, UPN for full audit trail
- NOT FOUND detection — HTTP 404 logged separately, no false failures
- Security cleanup — $ClientSecret and $Token cleared from memory after run
- Timestamped log per run in Logs\ subfolder — permanent deletion record
- Set-StrictMode + Stop error preference — no silent failures
- Pure PowerShell 5.1 — no extra modules required
- $PSScriptRoot input/output paths — portable, no hardcoded paths

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Modern Workplace Engineers decommissioning retired devices at scale
- IT admins cleaning up stale or duplicate Intune device records
- Endpoint teams post-hardware-refresh removing old device records in bulk
- MSPs performing tenant cleanup after device offboarding waves
- Anyone who has manually deleted Intune records one by one in the portal

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Microsoft Intune, Graph API, PowerShell, Delete Device, Managed Device,
Bulk Delete, Device Cleanup, Stale Records, Endpoint Management, Modern Workplace,
Azure AD, Entra ID, MDM, Intune Automation, Device Offboarding, Hardware Refresh,
Decommission, Device Management, Dry Run, Audit Log

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Place Remove-IntuneManagedDeviceByDevicesIDs.ps1 in a working folder.
3. Create DeviceIDs.txt in the SAME folder.
   One Intune Managed Device ID (GUID) per line. No headers.
4. Open the script and fill in $TenantID, $ClientID, $ClientSecret.
5. Set $MaxBatchSize to match the number of IDs in your file.
6. Leave $DryRun = $true. Run the script.
7. Open the log in the Logs\ subfolder. Verify every DeviceName, OS,
   and UPN matches the devices you intend to delete.
8. Set $DryRun = $false. Run again to apply live deletions.
9. Review the live log. Confirm DELETED for all expected rows.

Required Graph API permission on your app registration:
  DeviceManagementManagedDevices.ReadWrite.All  (Application, admin consent)

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Can deleted devices be recovered?
A: No. Intune has no recycle bin. Deletions are permanent and immediate.
   If the device is still enrolled, it will re-enroll on next check-in
   as a new record — but all history, compliance data, and assignments
   from the deleted record are gone permanently.

Q: Why does $MaxBatchSize default to 1?
A: Intentional safety gate. It forces you to consciously set the limit
   to match your intent before each run. A misconfigured input file with
   thousands of IDs will be caught and aborted before any deletion occurs.

Q: What is a Managed Device ID and how do I find it?
A: It is the Intune device record GUID. Find it in:
   Intune Portal > Devices > All Devices > click device > Device ID field.
   Or export Devices > All Devices > Export CSV > "Device ID" column.
   Or query Graph API: GET /deviceManagement/managedDevices?$select=id,deviceName

Q: What happens if I use the wrong type of ID?
A: The script will return HTTP 404 NOT FOUND for those IDs. No deletion
   occurs for 404 rows. However always verify your IDs in Dry-Run first.

Q: Does Dry-Run make any changes at all?
A: No. Dry-Run performs only the GET (read) call per device. No DELETE
   calls are made. The log shows what WOULD be deleted with full device details.

Q: What happens to devices that are still enrolled and active?
A: Deleting the Intune record of an active device removes it from Intune
   immediately. On next check-in the device will re-enroll and create a new
   Intune record. To prevent re-enrollment, retire or wipe the device first,
   or use Enrollment Restrictions to block re-enrollment.

Q: Is there any rate limiting protection?
A: The bulk pull uses 429 retry protection. The DELETE loop does not.
   For large batches (hundreds of devices), run during off-peak hours.
   If 429 errors occur mid-run, collect the failed IDs and re-run.

Q: Do I need the Microsoft.Graph PowerShell module?
A: No. Uses direct REST API calls via Invoke-RestMethod only.

Q: Can I schedule this to run automatically?
A: Technically yes, but bulk device deletion should not be unattended.
   Always review the Dry-Run output before scheduling any live run.

Q: Why does the log go to a Logs\ subfolder instead of the script folder?
A: Keeps the script folder clean when running multiple times. The Logs\
   subfolder is created automatically if it does not exist.

================================================================================
  !!  FINAL REMINDER  !!
================================================================================

  DELETIONS ARE PERMANENT AND IRREVERSIBLE.
  ALWAYS RUN DRY-RUN FIRST.
  ALWAYS VERIFY DEVICENAME, OS, AND UPN IN THE DRY-RUN LOG
  BEFORE SETTING $DryRun = $false.

================================================================================
  End of README — Remove-IntuneManagedDeviceByDevicesIDs.ps1
  Author: Sethu Kumar B
================================================================================
