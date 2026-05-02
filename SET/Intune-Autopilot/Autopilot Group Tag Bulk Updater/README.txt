================================================================================
  README — Set-AutopilotGroupTag.ps1
  Author : Sethu Kumar B
  Version: 1.3
================================================================================

SCRIPT NAME
-----------
Set-AutopilotGroupTag.ps1

FOLDER NAME
-----------
Intune-Autopilot

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Bulk-sets or updates the Group Tag on Windows Autopilot registered devices
using serial numbers from a plain text input file. Designed for IT admins who
need to tag multiple Autopilot devices at once — for dynamic group targeting,
deployment profile assignment, or post-registration cleanup.

Includes Dry-Run mode (default) to preview all changes before applying.
Exports a full timestamped audit CSV and log after every run.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
Step 1 — Reads and parses AutopilotGroupTag.txt from the script folder.
         Skips blank lines and comment lines (lines starting with #).

Step 2 — Authenticates to Microsoft Graph API using app credentials.

Step 3 — Pulls ALL Windows Autopilot device records in one paginated bulk call
         and builds a hashtable keyed by serial number for fast client-side
         lookup.

         WHY BULK PULL INSTEAD OF PER-SERIAL FILTER:
         The Graph API windowsAutopilotDeviceIdentities endpoint returns
         HTTP 500 Internal Server Error when $filter is used on serialNumber
         in many tenants. This is a known Graph API limitation. The script
         pulls all devices once and looks up client-side — reliable and fast.

Step 4 — For each serial number in the input file:
           - Looks up the Autopilot device from the hashtable
           - Reads the current Group Tag
           - Determines action:
               TAG ADDED    — device had no group tag, new tag will be applied
               TAG UPDATED  — device had an existing tag, tag will be changed
               NO CHANGE    — new tag matches existing tag, skipped
               NOT FOUND    — serial not registered in Autopilot, skipped
           - In Live mode: posts new Group Tag via updateDeviceProperties action
           - Logs result to audit CSV

Step 5 — Exports timestamped audit CSV and log to $PSScriptRoot.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Azure AD App Registration with a Client Secret
- Admin consent granted for required Graph API permissions (see below)
- Input file AutopilotGroupTag.txt placed in the same folder as the script

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission                                   Type          Purpose
-------------------------------------------  ------------  ---------------------
DeviceManagementManagedDevices.Read.All      Application   Read Autopilot devices
DeviceManagementServiceConfig.ReadWrite.All  Application   Update group tags

Grant type : Application permissions (not delegated)
Consent    : Admin consent required

WARNING: This script WRITES to Autopilot device records (updates Group Tag).
         Always run Dry-Run first to verify before applying live changes.
         Use a dedicated app registration scoped to these permissions only.

--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File name : AutopilotGroupTag.txt
Location  : Same folder as the script ($PSScriptRoot)

Format    : SerialNumber,NewGroupTag  — one entry per line
            Blank lines are ignored.
            Lines starting with # are treated as comments and ignored.

Example:
  # Engineering department devices
  SN-001234,Engineering
  SN-005678,Manufacturing

  # AI team devices
  SN-009999,AI-Team
  SN-010001,AI-Team

Rules:
- Serial number must exactly match what is registered in Windows Autopilot.
- Group Tag value is case-sensitive — use consistent casing across your tenant.
- Both fields are required per line. Lines missing either are skipped with WARN.
- No limit on number of entries.

--------------------------------------------------------------------------------
HOW TO RUN
--------------------------------------------------------------------------------
Step 1 — Place script and AutopilotGroupTag.txt in the same folder.

Step 2 — Open the script and fill in the CONFIGURATION block:

    $TenantID     = "your-tenant-id"
    $ClientID     = "your-app-client-id"
    $ClientSecret = "your-client-secret"
    $DryRun       = $true    ← Always start here

Step 3 — Run in PowerShell 5.1 or later:

    .\Set-AutopilotGroupTag.ps1

Step 4 — Review the audit CSV in the same folder.
         Check all serials were found and actions are correct.
         Fix the input file if needed.

Step 5 — Set $DryRun = $false and run again to apply live.

Step 6 — Review the live audit CSV. Confirm Result = SUCCESS for all rows.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Two files saved to $PSScriptRoot (same folder as the script):

  AutopilotGroupTag_[timestamp].csv   — full audit CSV
  AutopilotGroupTag_[timestamp].log   — run log

AUDIT CSV COLUMNS:
  SerialNumber      — Serial number from input file
  AutopilotDeviceID — Autopilot device record GUID
  DeviceName        — Device display name from Autopilot
  Manufacturer      — Device manufacturer
  Model             — Device model
  EnrollmentState   — Current Autopilot enrollment state
  OldGroupTag       — Group tag before this run (empty if none was set)
  NewGroupTag       — Group tag applied (or would be applied in Dry-Run)
  Action            — TAG ADDED / TAG UPDATED / NO CHANGE / NOT FOUND / UPDATE FAILED
  Result            — SUCCESS / SKIPPED / DRY RUN / FAILED
  ErrorDetail       — Error message if Result = FAILED, reason if SKIPPED
  Timestamp         — Date and time the row was processed

ACTION LABEL MEANINGS:
  TAG ADDED    — Device had no group tag. New tag applied (or would be in Dry-Run).
  TAG UPDATED  — Device had an existing tag. Tag changed to new value.
  NO CHANGE    — New tag matches existing tag exactly. No update made.
  NOT FOUND    — Serial number not registered in Windows Autopilot. Skipped.
  UPDATE FAILED — Live update API call failed. See ErrorDetail column.

CONSOLE SUMMARY includes:
  - Total entries processed
  - TAG ADDED / TAG UPDATED / NO CHANGE / NOT FOUND / FAILED counts
  - Audit CSV and log file paths

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- ALWAYS run Dry-Run first ($DryRun = $true). Review the preview CSV before
  setting $DryRun = $false to apply live changes.

- DUPLICATE SERIAL NUMBERS IN AUTOPILOT:
  If the same serial number is registered more than once in Autopilot (common
  after device wipe and re-registration), the script keeps the FIRST matching
  record and silently ignores subsequent duplicates. Only one device record
  per serial is updated. Review the AutopilotDeviceID column in the audit CSV
  to confirm the correct record was targeted. Clean up stale Autopilot
  registrations to avoid this issue.

- Group Tag is case-sensitive. Use consistent casing across your input file
  and your Azure AD dynamic group membership rules.

- Group Tag changes do NOT immediately re-trigger Autopilot deployment profile
  assignment. Azure AD dynamic group membership must update first (can take
  5–30 minutes). Plan accordingly for time-sensitive deployments.

- Uses Graph API beta endpoint. Beta endpoints may change — verify against
  Microsoft documentation if issues arise after a Graph API update.

- Credentials must be filled in before running. Intentionally left empty in
  the distributed version.

- Output files are timestamped — safe to run multiple times without overwriting.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------
Problem : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Confirm app registration exists and secret has not expired.

Problem : Input file not found
Fix     : Confirm AutopilotGroupTag.txt is in the same folder as the script.
          Do not rename the file unless you update $InputFileName in the config.

Problem : Serial number shows NOT FOUND
Fix     : Verify the serial number is registered in Windows Autopilot
          (Intune > Devices > Windows > Windows Enrollment > Devices).
          Check for typos or leading/trailing spaces in the input file.
          Serial lookup is case-insensitive but must match exactly.

Problem : HTTP 500 on Autopilot device list pull
Fix     : The script already handles this by pulling all devices without
          $filter or $select. If HTTP 500 still occurs, check that
          DeviceManagementManagedDevices.Read.All is granted with admin consent.

Problem : UPDATE FAILED in audit CSV
Fix     : Check the ErrorDetail column for the specific error message.
          Confirm DeviceManagementServiceConfig.ReadWrite.All is granted
          with admin consent. Verify the Autopilot device is not retired
          or in a read-only state.

Problem : Group Tag updated but device still in wrong deployment profile
Fix     : Azure AD dynamic group membership update takes 5–30 minutes after
          a group tag change. Wait and re-check group membership in Azure AD
          before assuming the tag update failed.

Problem : Duplicate Autopilot records for same serial
Fix     : Clean up stale Autopilot device registrations in Intune.
          Each serial should have exactly one active Autopilot registration.
          The script processes only the first record found — verify the
          AutopilotDeviceID in the audit CSV is the correct record.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Autopilot Group Tag Bulk Updater — PowerShell + Graph API

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Set or update Autopilot Group Tags on hundreds of devices in one run — no
portal clicking, no manual edits.

This PowerShell script reads a simple text file (serial number + group tag per
line), pulls your entire Autopilot device registry once, and bulk-applies Group
Tags using the Microsoft Graph API. Built-in Dry-Run mode lets you preview every
change before anything is touched. Every run exports a full audit CSV showing
exactly what changed, what was skipped, and why.

Works around the known Graph API $filter HTTP 500 bug on the
windowsAutopilotDeviceIdentities endpoint — no workarounds needed on your end.

No third-party modules required. No user login needed. Just fill in your app
credentials, drop your serial list in the same folder, and run.

Perfect for hardware refresh waves, bulk re-tagging after a naming change, or
tagging newly registered Autopilot devices before first enrollment.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Bulk Group Tag set/update from a plain text input file
- Dry-Run mode default — preview all changes before applying, zero risk
- TAG ADDED / TAG UPDATED / NO CHANGE action labels — clear audit trail
- Single bulk Autopilot device pull — avoids known Graph API $filter HTTP 500
- 429 throttle protection with Retry-After backoff on bulk device pull
- Comment and blank line support in input file (#-prefixed lines skipped)
- Full audit CSV per run — before/after group tag, action, result per device
- Manufacturer, Model, EnrollmentState columns in audit for device context
- Pure PowerShell 5.1 — no extra modules required
- $PSScriptRoot paths — portable, no hardcoded paths to edit

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Modern Workplace Engineers managing Autopilot deployments at scale
- IT admins bulk-tagging devices for dynamic group targeting
- Endpoint teams running hardware refresh waves needing fast group tag updates
- MSPs managing multiple Autopilot tenants needing a portable, reliable tagger
- Anyone who has manually set Group Tags one device at a time in the Intune portal

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Microsoft Intune, Autopilot, Windows Autopilot, Group Tag, Graph API,
PowerShell, Bulk Update, Device Management, Endpoint Management, Modern Workplace,
Azure AD, Entra ID, Dynamic Groups, Deployment Profile, Autopilot Tagging,
Hardware Refresh, Intune Automation, DeviceManagement, Serial Number

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Place Set-AutopilotGroupTag.ps1 in a working folder.
3. Create AutopilotGroupTag.txt in the SAME folder.
   Format: SerialNumber,NewGroupTag (one per line).
   Use # to add comment lines. Blank lines are safe.
4. Open the script and fill in $TenantID, $ClientID, $ClientSecret.
5. Leave $DryRun = $true. Run the script. Review the audit CSV.
6. Verify all serials are found and actions are correct.
7. Set $DryRun = $false. Run again to apply changes live.
8. Open the live audit CSV — confirm Result = SUCCESS for all rows.

Required Graph API permissions on your app registration:
  DeviceManagementManagedDevices.Read.All      (Application)
  DeviceManagementServiceConfig.ReadWrite.All  (Application)
Both require admin consent.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Will this script affect device enrollment or wipe any data?
A: No. It only updates the Group Tag field on the Autopilot device record.
   No enrollment is triggered, no device is wiped.

Q: How long until the new Group Tag takes effect?
A: The tag is updated immediately in Autopilot. However, Azure AD dynamic group
   membership recalculation can take 5–30 minutes. Deployment profile assignment
   follows after group membership updates.

Q: Can I remove a Group Tag entirely?
A: This script requires a non-empty NewGroupTag value per entry. To clear a tag,
   you would need to modify the script to send an empty string to the API.
   This use case is not supported in the current version.

Q: What happens if a serial appears twice in Autopilot?
A: The script processes only the first matching record and logs a note in the
   audit CSV. Clean up duplicate Autopilot registrations in Intune to ensure
   the correct record is targeted.

Q: Does the input file need to be CSV format?
A: No. It is a plain text file (.txt) with SerialNumber,NewGroupTag per line.
   Blank lines and lines starting with # are ignored automatically.

Q: Do I need the Microsoft.Graph PowerShell module?
A: No. Uses direct REST API calls via Invoke-RestMethod only.

Q: Can I use this for non-Windows devices?
A: No. The script targets Windows Autopilot device identities only.

Q: Why does the script pull all Autopilot devices instead of filtering by serial?
A: The Graph API windowsAutopilotDeviceIdentities endpoint returns HTTP 500
   when $filter is used on serialNumber in many tenants — a known Microsoft
   limitation. Pulling all devices once and looking up client-side is the
   reliable workaround. For tenants with large Autopilot registries this is
   still efficient — one bulk pull shared across all entries in the input file.

================================================================================
  End of README — Set-AutopilotGroupTag.ps1
  Author: Sethu Kumar B
================================================================================
