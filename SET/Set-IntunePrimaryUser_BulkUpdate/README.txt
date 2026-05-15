================================================================================
  README — Set-IntunePrimaryUser_BulkUpdate.ps1
  Author : Sethu Kumar B
  Version: 1.1
================================================================================

SCRIPT NAME
-----------
Set-IntunePrimaryUser_BulkUpdate.ps1

FOLDER NAME
-----------
Intune-Device-Management

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Bulk-updates the Primary User on multiple Intune managed devices in one run.
Reads a simple two-column CSV (Hostname + PrimaryUserEmail), validates each
device and user against Intune and Azure AD, then sets the Primary User
automatically — no per-device confirmation required.

Includes a Dry-Run mode to preview all changes before applying them.
Exports a full timestamped audit CSV after every run.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
For each row in the input CSV, the script:

  Step 1 — Validates the row has both Hostname and PrimaryUserEmail.
  Step 2 — Searches Intune for the device by hostname.
           Skips with ERROR if not found.
           Warns if duplicate Intune records exist and processes all of them.
  Step 3 — Validates the new PrimaryUserEmail exists in Azure AD.
           Skips with ERROR if user not found.
  Step 4 — Updates the Primary User on the device:
             B — DELETE existing primary user $ref
             C — POST new primary user $ref
           Skips update if Primary User already matches target (no change needed).
  Step 5 — Logs result to audit CSV (Success / Error / Skipped / DryRun).

Dry-Run mode ($DryRun = $true):
  Runs all validation steps. Makes zero API changes. Exports a preview audit CSV
  showing exactly what would be updated. Switch $DryRun = $false to apply live.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Azure AD App Registration with a Client Secret
- Admin consent granted for required Graph API permissions (see below)
- Input CSV file placed in the same folder as this script

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission                                  Type          Purpose
------------------------------------------  ------------  ----------------------
DeviceManagementManagedDevices.ReadWrite.All Application  Read + update devices
User.Read.All                               Application   Validate users in AAD

Grant type : Application permissions (not delegated)
Consent    : Admin consent required

WARNING: This script WRITES to Intune (updates Primary User).
         Use Dry-Run mode first to validate before running live.
         Use a dedicated app registration scoped to these two permissions only.

--------------------------------------------------------------------------------
INPUT CSV FORMAT
--------------------------------------------------------------------------------
File name : InputDevices_BulkUpdate.csv
Location  : Same folder as the script ($PSScriptRoot)
Columns   : Hostname, PrimaryUserEmail (header row required)

Example:
  Hostname,PrimaryUserEmail
  DESKTOP-ABC123,john.doe@contoso.com
  LAPTOP-XYZ789,jane.smith@contoso.com
  WS-FINANCE-01,mike.jones@contoso.com

Rules:
- Hostname must exactly match the device name in Intune (case-insensitive).
- PrimaryUserEmail must be a valid UPN that exists in Azure AD.
- Both columns are required for every row. Rows missing either field are skipped.
- No limit on number of rows.

--------------------------------------------------------------------------------
HOW TO RUN
--------------------------------------------------------------------------------
Step 1 — Place the script and InputDevices_BulkUpdate.csv in the same folder.

Step 2 — Open the script and fill in the CONFIGURATION block:

    $TenantID     = "your-tenant-id"
    $ClientID     = "your-app-client-id"
    $ClientSecret = "your-client-secret"
    $DryRun       = $true    ← Start here. Review preview CSV first.

Step 3 — Run in PowerShell 5.1 or later:

    .\Set-IntunePrimaryUser_BulkUpdate.ps1

Step 4 — Review the audit CSV generated in the same folder.
         Check for any SKIPPED or ERROR rows. Fix the CSV if needed.

Step 5 — Set $DryRun = $false and run again to apply changes live.

Step 6 — Review the live audit CSV to confirm all updates succeeded.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Two files saved to $PSScriptRoot (same folder as the script):

  SetPrimaryUser_Audit_DryRun_[timestamp].csv   ← Dry-run preview
  SetPrimaryUser_Audit_Live_[timestamp].csv      ← Live run results

AUDIT CSV COLUMNS:
  Hostname        — Device hostname from input CSV
  IntuneDeviceId  — Intune managed device ID (GUID)
  SerialNumber    — Device serial number from Intune
  OldPrimaryUser  — Previous primary user UPN (before update)
  NewPrimaryUser  — New primary user UPN (target)
  Action          — UPDATED / SKIPPED / DRY-RUN
  Result          — SUCCESS / ERROR / NO CHANGE NEEDED / WOULD UPDATE
  Note            — Detail message (error reason, skip reason, etc.)
  Timestamp       — Date and time the row was processed

CONSOLE SUMMARY includes:
  - Total rows processed
  - Updated OK count
  - Already correct (no change needed) count
  - Errors / Skipped count
  - Audit CSV path

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- ALWAYS run Dry-Run first. Validate the preview CSV before running live.
- Duplicate Intune records: If multiple Intune devices share the same hostname,
  the script will process ALL of them and log a warning. Review duplicates in
  the audit CSV and clean up stale Intune records if needed.
- No 429 throttle protection. For very large CSV files (500+ rows) run during
  off-peak hours to reduce the risk of Graph API rate limiting.
- Primary User already correct: If the current Primary User already matches
  the target email, the device is skipped with Result = NO CHANGE NEEDED.
  No API call is made. This is safe to re-run.
- Uses Graph API beta endpoint for device lookup and Primary User update.
  Beta endpoints may change — verify against Microsoft documentation if issues
  arise after a Graph API update.
- Credentials must be filled in before running. They are intentionally left
  empty in the distributed version.
- Output files are timestamped — safe to run multiple times without overwriting.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------
Problem : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Confirm the app registration exists and secret has not expired.

Problem : Input CSV not found
Fix     : Confirm InputDevices_BulkUpdate.csv is in the same folder as the
          script. Do not change $InputCSV path in the config block.

Problem : CSV column error on startup
Fix     : Ensure the CSV header row is exactly: Hostname,PrimaryUserEmail
          No extra spaces, no BOM encoding issues. Save as UTF-8.

Problem : Hostname not found in Intune
Fix     : Verify the hostname matches exactly what is shown in Intune
          (Devices > All Devices > Device Name column). Check for typos
          or naming convention differences (e.g., DESKTOP- prefix).

Problem : User not found in Azure AD
Fix     : Confirm the UPN is correct and the user account exists and is
          not deleted or soft-deleted in Azure AD.

Problem : DELETE existing user failed (HTTP 4xx)
Fix     : Confirm DeviceManagementManagedDevices.ReadWrite.All is granted
          with admin consent. Check that the device is still active in Intune.

Problem : Duplicate devices processed unexpectedly
Fix     : Search Intune for the hostname and delete stale/retired device
          records. Each hostname should map to exactly one active device.

Problem : Script stops mid-run on large CSV
Fix     : Likely HTTP 429 rate limit. No retry logic in this script.
          Split large CSV into smaller batches and re-run for failed rows.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Intune Bulk Primary User Updater — PowerShell + Graph API

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Set the Primary User on hundreds of Intune devices in one run — no clicking
through the portal device by device.

This PowerShell script reads a simple CSV (Hostname + email), validates every
device and user against Intune and Azure AD, and bulk-updates the Primary User
automatically. A built-in Dry-Run mode lets you preview every change before
anything is touched. Every run exports a full audit CSV showing what changed,
what was skipped, and why.

No third-party modules required. No user login needed. Just fill in your app
credentials, drop your CSV in the same folder, and run.

Perfect for device reassignments, hardware refreshes, onboarding waves, or
fixing bulk Primary User mismatches after an Autopilot deployment.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Bulk CSV-driven Primary User update — no portal clicks
- Dry-Run mode — preview all changes before applying, zero risk
- Azure AD user validation before any write operation
- Duplicate Intune record detection with warning + full processing
- Skips devices where Primary User already matches — no unnecessary writes
- Full audit CSV per run — Success / Error / Skipped / DryRun per device
- OldPrimaryUser + NewPrimaryUser columns for before/after tracking
- READ-ONLY Dry-Run / WRITE Live — controlled by a single $DryRun flag
- Pure PowerShell 5.1 — no extra modules required
- $PSScriptRoot paths — portable, no hardcoded paths to edit

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Modern Workplace Engineers handling device reassignments at scale
- IT admins fixing Primary User mismatches after Autopilot deployments
- Endpoint teams managing hardware refresh waves with user reassignment
- MSPs onboarding or offboarding users across multiple managed devices
- Anyone who has ever manually updated Primary User one device at a time

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Microsoft Intune, Graph API, PowerShell, Primary User, Bulk Update,
Device Reassignment, Endpoint Management, Modern Workplace, Azure AD, Entra ID,
MDM, Intune Automation, Hardware Refresh, User Assignment, Managed Devices,
Autopilot, Dry Run, Audit CSV, DeviceManagement

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Place Set-IntunePrimaryUser_BulkUpdate.ps1 in a working folder.
3. Create InputDevices_BulkUpdate.csv in the SAME folder with columns:
     Hostname,PrimaryUserEmail
4. Open the script and fill in $TenantID, $ClientID, $ClientSecret.
5. Set $DryRun = $true. Run the script. Review the preview audit CSV.
6. Fix any ERROR or SKIPPED rows in your CSV.
7. Set $DryRun = $false. Run again to apply changes live.
8. Open the live audit CSV — confirm all rows show Result = SUCCESS.

Required Graph API permissions on your app registration:
  DeviceManagementManagedDevices.ReadWrite.All  (Application)
  User.Read.All                                 (Application)
Both require admin consent.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Will this script delete or wipe any devices?
A: No. It only updates the Primary User field on the device record in Intune.
   No device data is affected.

Q: What happens if a hostname appears twice in Intune?
A: The script processes all matching records and logs a WARN in the console.
   Both devices will appear in the audit CSV. Clean up stale Intune records
   to avoid unintended updates.

Q: Can I run this multiple times safely?
A: Yes. Devices where Primary User already matches are skipped automatically
   with Result = NO CHANGE NEEDED. No duplicate writes occur.

Q: Does Dry-Run mode make any changes at all?
A: No. Dry-Run skips all DELETE and POST API calls. Only reads are performed.
   The preview audit CSV shows exactly what would happen on a live run.

Q: Do I need the Microsoft.Graph PowerShell module?
A: No. The script uses direct REST API calls via Invoke-RestMethod only.

Q: Can I schedule this to run automatically?
A: Yes. Use Windows Task Scheduler or Azure Automation with a service principal.
   Ensure the input CSV is updated before each scheduled run.

Q: What is the Primary User used for in Intune?
A: Primary User links a device to a specific user for licensing, app targeting,
   self-service portal access (Company Portal), and user-based compliance
   policies. Incorrect Primary User can cause app deployment and compliance
   policy gaps.

================================================================================
  End of README — Set-IntunePrimaryUser_BulkUpdate.ps1
  Author: Sethu Kumar B
================================================================================
