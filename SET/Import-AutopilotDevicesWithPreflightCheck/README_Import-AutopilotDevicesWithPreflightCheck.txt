================================================================================
  README - Import-AutopilotDevicesWithPreflightCheck.ps1
  Author  : Sethu Kumar B
  Version : 2.2
  Updated : 2026-05-04
================================================================================


OVERVIEW
--------
This script imports Windows Autopilot devices from hardware hash CSV files.
Before submitting any device, it performs a pre-import check against both the
Autopilot registry and the staging queue to avoid duplicate imports and
re-import failures intelligently.

Place one or more hardware hash CSV files in the Import subfolder, run the
script, and it handles classification, batching, submission, polling, and
result export automatically.


WHAT THIS SCRIPT DOES
---------------------
  1. Scans the Import\ subfolder for all .csv files
  2. Validates and loads each CSV (case-insensitive column matching)
  3. Checks each device serial against:
       - windowsAutopilotDeviceIdentities       (actual Autopilot registry)
       - importedWindowsAutopilotDeviceIdentities (staging queue)
  4. Classifies each device and decides action (see Decision Matrix below)
  5. Submits eligible devices in batches of up to 500 per API call
  6. Resolves import IDs from staging post-submission
  7. Polls until all devices reach terminal state or timeout
  8. Exports full result CSV and log


DECISION MATRIX
---------------
  Condition                                    Action
  -------------------------------------------  --------------------------------
  Found in Autopilot registry                  SKIP  (already enrolled)
  Found in staging with status = complete      SKIP  (recently imported)
  Found in staging with status = error         RE-IMPORT
  Not found anywhere                           FRESH IMPORT

Devices classified as SKIP are included in the output CSV with their
decision recorded. Nothing is submitted for them.


PRE-REQUISITES
--------------
1. PowerShell 5.1 or later

2. Azure AD App Registration with the following API permissions
   (application permissions, admin consent granted):
     DeviceManagementServiceConfig.ReadWrite.All  - Autopilot import + staging read
     DeviceManagementManagedDevices.Read.All      - Autopilot registry read

3. Import folder and CSV files:
     <ScriptRoot>\Import\
     Place all hardware hash CSV files here before running.
     Subfolders are not scanned - files must be directly in Import\.


CSV INPUT FORMAT
----------------
MANDATORY columns (case-insensitive, any column order):
  Device Serial Number  - device serial number
  Hardware Hash         - base64 hardware hash string

OPTIONAL columns (included in import if present, ignored if absent):
  Windows Product ID    - can be empty/blank
  Group Tag             - applied to device during Autopilot import

Any other columns in the CSV are silently ignored.

Supported CSV encodings (auto-detected via BOM):
  UTF-16 LE (common from Get-WindowsAutopilotInfo)
  UTF-16 BE
  UTF-8 BOM
  UTF-8 (no BOM, default fallback)

HP tool format: CSVs where each row is wrapped as a single quoted string
  ("col1,col2,col3") are automatically unwrapped before parsing.


CONFIGURATION
-------------
Open the script and update the CONFIGURATION block at the top:

  $TenantID     = ""     <- Your Azure AD Tenant ID
  $ClientID     = ""     <- App Registration Client ID
  $ClientSecret = ""     <- App Registration Client Secret

  $ImportFolder          <- Defaults to <ScriptRoot>\Import\  (do not change unless needed)
  $BatchSize    = 500    <- Max devices per API call. Graph API limit is 500.
  $MaxRetries   = 5      <- Retry attempts on 429 throttling.

  $PollIntervalSeconds = 30   <- How often to check import status (seconds)
  $PollTimeoutMinutes  = 30   <- Give up polling after this many minutes


HOW TO RUN
----------
1. Place the script in any folder.

2. Create an Import\ subfolder in the same folder as the script:
     <ScriptFolder>\Import\

3. Copy hardware hash CSV files into the Import\ folder.

4. Update TenantID, ClientID, ClientSecret in the config block.

5. Run:
     Right-click -> Run with PowerShell
     OR in PowerShell console:
       .\Import-AutopilotDevicesWithPreflightCheck.ps1

6. Review output CSV and log in the script folder after completion.


OUTPUT FILES
------------
All files are saved in the script root folder ($PSScriptRoot).

  AutopilotImport_YYYYMMDD_HHMMSS.csv          - full device result export
  AutopilotImport_YYYYMMDD_HHMMSS.log          - detailed run log
  AutopilotImport_Transcript_YYYYMMDD_HHMMSS.log - full PS transcript


OUTPUT CSV COLUMNS
------------------
  SourceFile        - CSV filename the device was loaded from
  SerialNumber      - Device serial number
  WindowsProductID  - Windows Product ID (if present in source CSV)
  GroupTag          - Group Tag (if present in source CSV)
  Decision          - Classification result (see Decision Values below)
  ImportedDeviceID  - Staging record GUID assigned by Graph API
  ImportStatus      - Final import status (see Status Values below)
  StatusDetail      - Error code / error name / registration ID if applicable
  BatchNumber       - Which submission batch this device was in
  SubmittedAt       - Timestamp when batch was submitted
  StatusCheckedAt   - Timestamp of final status poll


DECISION VALUES (Decision column)
----------------------------------
  IMPORT          - Not found anywhere. Fresh import submitted.
  REIMPORT        - Was in staging with error status. Resubmitted.
  SKIP-ENROLLED   - Already present in Autopilot registry. Not submitted.
  SKIP-COMPLETE   - Staging record exists with complete status. Not submitted.


IMPORT STATUS VALUES (ImportStatus column)
-------------------------------------------
  complete              - Successfully imported
  error                 - Import failed (see StatusDetail for error code)
  completedWithError    - Completed with partial error
  pending               - Still processing at poll timeout
  submitted             - Submitted but import ID could not be resolved
  skip-enrolled         - Skipped (already in Autopilot registry)
  skip-complete         - Skipped (staging record already complete)
  SUBMIT FAILED         - API batch call itself failed (see StatusDetail)


POLLING BEHAVIOUR
-----------------
After each batch is submitted, the script:
  1. Waits 10 seconds for staging records to appear
  2. Queries staging to resolve ImportedDeviceID per serial
  3. After all batches are submitted, polls on the configured interval
     until all devices reach a terminal state or timeout is hit

Terminal states: complete, error, completedWithError

If $PollTimeoutMinutes is reached before all devices finish, remaining
devices are recorded as "pending" in the output CSV. The import may still
complete in the background - check Intune portal or re-run to verify.


DUPLICATE HANDLING
------------------
The pre-import check prevents duplicate submissions automatically.
If the same serial appears in multiple CSV files in the Import folder,
only the first occurrence is submitted. The decision matrix applies
per serial number, not per file row.


GRAPH API NOTES
---------------
- importedWindowsAutopilotDeviceIdentities/import endpoint:
  Accepts up to 500 devices per POST. Batch size is configurable.

- windowsAutopilotDeviceIdentities endpoint:
  No $filter or $select combined with $top (causes HTTP 500).
  Script performs full bulk pull with client-side hashtable lookup.

- Staging endpoint is queried both before import (pre-check) and after
  submission (ID resolution). Post-submission query uses submit timestamp
  to filter out stale records from previous runs.

- 429 throttling handled with Retry-After header + exponential backoff
  up to $MaxRetries attempts.


PERMISSIONS REFERENCE
---------------------
  Permission                                   Used For
  -------------------------------------------  --------------------------------
  DeviceManagementServiceConfig.ReadWrite.All   Submit to staging, read staging
  DeviceManagementManagedDevices.Read.All       Read Autopilot registry

  Recommended: Maintain separate read-only and read-write app registrations.
  Use read-only for staging checks only, read-write for import runs.


TROUBLESHOOTING
---------------
"Missing required column" error on CSV load
  Confirm the CSV has columns named exactly:
    "Device Serial Number" and "Hardware Hash"
  Column names are matched case-insensitively.
  If the file is from an HP tool, the script auto-handles row wrapping.
  Check the log - it prints all column names found in the file.

Authentication failed
  Verify TenantID, ClientID, ClientSecret in config block.
  Confirm admin consent granted for both permissions in Azure portal.
  Check that client secret has not expired.

ImportedDeviceID shows "N/A" after submission
  Staging record did not appear within the 10-second post-submit window.
  The device may still import successfully - check the Intune portal.
  The ID resolution uses submit timestamp to filter stale records.
  If this is recurring, increase the Start-Sleep -Seconds 10 value.

All devices showing SKIP-ENROLLED
  Devices are already registered in Autopilot. No action needed.
  If a re-import is intentionally required, delete the Autopilot record
  first, then re-run.

Devices stuck in "pending" at poll timeout
  Increase $PollTimeoutMinutes or $PollIntervalSeconds in config.
  Import processing time varies - large batches can take 30-60+ minutes.
  Check Intune portal under Devices > Enroll devices > Windows enrollment
  > Windows Autopilot Deployment Program > Devices for live status.

SUBMIT FAILED in output CSV
  The batch POST call failed entirely. See StatusDetail for HTTP error.
  Common causes: expired token, permission missing, throttling exhausted.
  Re-run after resolving the error - pre-import check will skip
  already-enrolled devices and only retry the failed ones.


CHANGE LOG
----------
  v2.2 - 2026-05-04 - Sethu Kumar B
    Full CSV encoding fix. Auto-detects UTF-16 LE/BE and UTF-8 BOM via
    byte inspection. Handles HP tool format where each row is wrapped as
    a single quoted string. Unwraps outer quotes per-line before parsing.

  v2.1 - 2026-05-04 - Sethu Kumar B
    Fixed stray leading quote on header row. Replaced Import-Csv with
    raw ReadAllLines + ConvertFrom-Csv. Fixes "missing required column"
    error on CSVs exported by certain HP tools.

  v2.0 - 2026-05-04 - Sethu Kumar B
    Major revision. Merged Check-AutopilotStaging.ps1 into pre-import
    phase. Added windowsAutopilotDeviceIdentities registry check.
    Per-device decision engine: SKIP / RE-IMPORT / FRESH IMPORT.
    Column validation case-insensitive with flexible order. Optional
    columns (Group Tag, Windows Product ID) taken if present. Decision
    column added to output CSV.

================================================================================