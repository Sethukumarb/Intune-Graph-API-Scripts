================================================================================
  README - Remove-IntuneDeviceOnlyBySerial.ps1
  Author  : Sethu Kumar B
  Version : 1.0
  Updated : 2026-05-14
================================================================================


OVERVIEW
--------
This script removes Intune managed device records for devices identified by
serial number. Autopilot and Entra ID (Azure AD) objects are NOT deleted -
they are discovered and reported only.

Use this script when decommissioning or re-imaging devices where:
  - Intune managed device record must be wiped
  - Autopilot registration must be preserved
  - Entra ID device objects need to be cleaned up by a separate team


WHAT THIS SCRIPT DOES
---------------------
  DELETES   : Intune managed device record
              DELETE /deviceManagement/managedDevices/{id}

  REPORTS   : Autopilot device identity (not touched)
              windowsAutopilotDeviceIdentities

  REPORTS   : Entra ID (Azure AD) device object (not touched)
              Exported to Sheet 3 for handoff to Entra team


WHAT THIS SCRIPT DOES NOT DO
-----------------------------
  - Does NOT delete Autopilot device registrations
  - Does NOT delete Entra ID / Azure AD device objects
  - Does NOT modify any user accounts or group memberships
  - Does NOT touch macOS, iOS, or Android devices
    (Intune pull is filtered to Windows only)


PRE-REQUISITES
--------------
1. PowerShell 5.1 or later

2. ImportExcel module
   Install once:
     Install-Module ImportExcel -Scope CurrentUser

3. Azure AD App Registration with the following API permissions
   (application permissions, admin consent granted):
     DeviceManagementManagedDevices.ReadWrite.All
     DeviceManagementServiceConfig.ReadWrite.All
     Device.Read.All

4. Input file:
     remove_inputserialnumbers.txt
     Place in the same folder as the script.
     One serial number per line.
     Lines starting with # and blank lines are ignored.

   Example:
     # Batch - May 2026 refresh
     SN1234567890
     SN0987654321
     # SN1111111111  <- this line is skipped


CONFIGURATION
-------------
Open the script and update the CONFIGURATION block at the top:

  $TenantID     = ""        <- Your Azure AD Tenant ID
  $ClientID     = ""        <- App Registration Client ID
  $ClientSecret = ""        <- App Registration Client Secret

  $DryRun       = $true     <- ALWAYS start with $true. Review output first.
  $MaxBatchSize = 10         <- Max serials per run. 0 = no limit.
  $MaxRetries   = 5          <- Graph API 429 retry attempts.


DRY RUN MODE (IMPORTANT - READ THIS)
--------------------------------------
$DryRun = $true  (default)
  - No DELETE calls are made.
  - Script runs end-to-end: auth, bulk pull, lookup, Excel export.
  - Sheet 2 shows DeleteStatus = "DRY RUN" for all found records.
  - Safe to run as many times as needed.

$DryRun = $false  (LIVE mode)
  - Intune DELETE calls execute immediately.
  - DELETION IS PERMANENT AND CANNOT BE UNDONE.
  - Always review the DRY RUN Excel output before switching to $false.


HOW TO RUN
----------
1. Place script and remove_inputserialnumbers.txt in the same folder.

2. Run dry run first:
     Set $DryRun = $true in the config block.
     Right-click -> Run with PowerShell
     OR in PowerShell console:
       .\Remove-IntuneDeviceOnlyBySerial.ps1

3. Review the output Excel file (Sheet 1 and Sheet 2).
   Confirm the correct devices are listed under PlannedAction = "WILL DELETE".

4. If correct, set $DryRun = $false and run again.

5. Share Sheet 3 (Entra ID Handoff) with your Entra ID / Azure AD team
   for manual cleanup of device objects.


OUTPUT FILES
------------
All files are saved in the same folder as the script ($PSScriptRoot).

File naming:
  [DRY RUN] RemoveIntuneDevices_YYYYMMDD_HHMMSS.xlsx   <- DryRun = $true
  RemoveIntuneDevices_YYYYMMDD_HHMMSS.xlsx              <- DryRun = $false
  (same pattern for .log and Transcript .log)


EXCEL WORKBOOK - 3 SHEETS
--------------------------

Sheet 1 - Full Discovery
  Every record found for each input serial number.
  RecordTypes: Intune | Autopilot | EntraID

  Columns:
    SerialNumber      - Input serial number
    Hostname          - Device name from Intune record
    RecordType        - Intune / Autopilot / EntraID
    IntuneDeviceID    - Intune managed device GUID
    AzureADDeviceID   - deviceId GUID (visible in Entra portal device properties)
    AzureADObjectID   - Object ID GUID (used for deletion in Entra portal/Graph API)
    AutopilotDeviceID - Autopilot identity GUID
    PlannedAction     - WILL DELETE / SKIPPED / NOT FOUND
    Manufacturer      - Device manufacturer
    Model             - Device model
    OS                - Operating system
    UPN               - Assigned user UPN from Intune
    Timestamp         - Record timestamp

  Color coding (PlannedAction column):
    Red background    - WILL DELETE (Intune records)
    Blue background   - SKIPPED (Autopilot / EntraID)
    Yellow background - NOT FOUND


Sheet 2 - Intune Deletions
  Intune records only. Shows the deletion result for each device.
  Use this sheet to confirm what was deleted.

  Columns:
    SerialNumber   - Input serial number
    Hostname       - Device name
    IntuneDeviceID - Intune managed device GUID
    DeleteStatus   - DELETED / DRY RUN / FAILED / NOT FOUND
    DeleteNote     - Success message or error detail
    Manufacturer   - Device manufacturer
    Model          - Device model
    Timestamp      - Record timestamp

  Color coding (DeleteStatus column):
    Green  - DELETED
    Yellow - DRY RUN
    Red    - FAILED
    Grey   - NOT FOUND


Sheet 3 - Entra ID Handoff
  Entra ID device objects found but NOT deleted by this script.
  Share this sheet with the Entra ID team for manual cleanup.

  Columns:
    SerialNumber    - Input serial number
    Hostname        - Device name
    AzureADDeviceID - deviceId GUID (visible in Entra portal)
    AzureADObjectID - Object ID GUID (USE THIS for deletion in portal or Graph)
    Status          - SKIPPED - Not deleted by script
    Note            - Instruction for Entra team
    Timestamp       - Record timestamp

  NOTE FOR ENTRA TEAM:
    Use the AzureADObjectID column to locate and delete device objects.
    In Entra portal: Devices -> All devices -> search by Device ID or Object ID.
    In Graph API: DELETE /v1.0/devices/{AzureADObjectID}


DUPLICATE HANDLING
------------------
If a serial number has multiple Intune or Autopilot records (duplicate
enrollments), each record gets its own row in the relevant sheet.
Duplicate rows are labeled: e.g. "Intune (Duplicate 1 of 2)"
All duplicates are processed and deleted individually.


BATCH CAP ($MaxBatchSize)
--------------------------
Default is 10 serials per run.
Script aborts BEFORE authentication if input exceeds the cap.
This is a safety gate to prevent accidental bulk deletions.
Set to 0 to remove the limit entirely.


GRAPH API NOTES
---------------
- Intune managedDevices: $filter on serialNumber causes HTTP 500.
  Script performs a full bulk pull of all Windows devices and does
  client-side lookup using a hashtable. This is by design.

- Autopilot windowsAutopilotDeviceIdentities: $select or $filter combined
  with $top causes HTTP 500. Script pulls without $select/$filter.

- Both endpoints support pagination via @odata.nextLink.
  Script handles all pages automatically.

- 429 throttling is handled with exponential backoff (up to $MaxRetries).


PERMISSIONS REFERENCE
---------------------
  Permission                                  Used For
  ------------------------------------------  --------------------------------
  DeviceManagementManagedDevices.ReadWrite.All  Read + DELETE Intune devices
  DeviceManagementServiceConfig.ReadWrite.All   Read Autopilot identities
  Device.Read.All                               Read Entra ID device objects

  Recommended: Maintain separate read-only and read-write app registrations.
  Use read-only for discovery/audit runs, read-write only for deletion runs.


TROUBLESHOOTING
---------------
ImportExcel not found
  Run: Install-Module ImportExcel -Scope CurrentUser
  If restricted: Install-Module ImportExcel -Scope CurrentUser -Force

Authentication failed
  Verify TenantID, ClientID, ClientSecret in config block.
  Confirm admin consent granted for all three permissions in Azure portal.
  Check that client secret has not expired.

No devices found for serials
  Confirm serial numbers are exact matches (case-insensitive, whitespace trimmed).
  Intune pull is Windows-only. Non-Windows devices will not appear.
  Verify the app registration has DeviceManagementManagedDevices.ReadWrite.All.

Sheet 3 empty
  Entra ID lookup requires Device.Read.All permission.
  If missing, lookup silently returns null and no Sheet 3 rows are written.
  Also possible the device was already removed from Entra ID.

FAILED in Sheet 2
  Check DeleteNote column for HTTP error code and message.
  Common causes: token expired mid-run, device already deleted, throttling.


CHANGE LOG
----------
  v1.0 - 2026-05-14 - Sethu Kumar B
    Initial release.
    Deletes Intune only. Autopilot untouched. Entra ID report only.
    Excel output with 3 sheets. ImportExcel module.
    PS 5.1 compatible. 429 retry with backoff. Batch cap safety gate.

================================================================================
