================================================================================
  README — Get-IntuneAuditReport-ConfigProfileChanges.ps1
  Author : Sethu Kumar B
  Version: 1.0
================================================================================

SCRIPT NAME
-----------
Get-IntuneAuditReport-ConfigProfileChanges.ps1

FOLDER NAME
-----------
Intune-Audit-Reports

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Retrieves the full lifecycle of Configuration Profile changes from the Microsoft
Intune audit log for a specified date range. Designed for IT admins who need to
audit what changed, who changed it, and when — across all Intune config profiles.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Authenticates to Microsoft Graph API using app credentials (client credentials
   flow — no user sign-in required).

2. Queries the Intune audit log server-side for all DeviceConfiguration events
   within the specified date range.

3. Filters client-side for these lifecycle operations:
     - Create          : Profile was created
     - Delete          : Profile was deleted
     - Assign          : Profile assigned to a group
     - RemoveReference : Profile removed from a group
     - Patch           : Profile settings were modified
     - SetReference    : Assignment relationship added or updated

4. Resolves the identity of who made each change using two sources:
     Source 1 — Actor object fields (UPN > Service Principal > App Name > User ID)
     Source 2 — modifiedProperties fallback (for service-triggered changes)

5. Extracts OS platform per event from modifiedProperties or activityType string.

6. Captures OldValue and NewValue for every changed property — most useful for
   Patch events to detect configuration drift.

7. Exports a timestamped CSV and log file to the script's own folder ($PSScriptRoot).

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Azure AD App Registration with a Client Secret
- Admin consent granted for required Graph API permissions (see below)
- Script must be run by a user or automation account with rights to execute PS1

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission                               Type          Purpose
---------------------------------------  ------------  -------------------------
DeviceManagementConfiguration.Read.All  Application   Read Intune audit events

Grant type : Application permissions (not delegated)
Consent    : Admin consent required

NOTE: This script is READ-ONLY. It does not modify any data in Intune or Azure AD.

--------------------------------------------------------------------------------
HOW TO RUN
--------------------------------------------------------------------------------
Step 1 — Open the script in a text editor or VS Code.

Step 2 — Fill in the CONFIGURATION block at the top:

    $TenantID     = "your-tenant-id"
    $ClientID     = "your-app-client-id"
    $ClientSecret = "your-client-secret"
    $StartDate    = "2026-03-01"   # YYYY-MM-DD format
    $EndDate      = "2026-03-31"   # YYYY-MM-DD format

Step 3 — Save the script and run it:

    .\Get-IntuneAuditReport-ConfigProfileChanges.ps1

Step 4 — Find the output CSV and log in the same folder as the script.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Two files saved to $PSScriptRoot (same folder as the script):

  IntuneAudit_ConfigProfileChanges_[StartDate]_to_[EndDate]_[timestamp].csv
  IntuneAudit_ConfigProfileChanges_[StartDate]_to_[EndDate]_[timestamp].log

CSV COLUMNS:
  EventDateTime        — Date and time of the change (local time)
  OperationType        — Raw operation: Create, Delete, Assign, Patch, etc.
  ActionLabel          — Human-readable label: PROFILE CREATED, PROFILE DELETED, etc.
  ProfileName          — Name of the configuration profile affected
  ProfileType          — Audit resource type (e.g., ManagedDeviceWindowsOSEditionType)
  OSPlatform           — Windows / macOS / iOS / Android / Linux / ChromeOS / N/A
  ComponentName        — Intune component that generated the event
  ChangedBy            — UPN, service principal name, or app name of the actor
  ChangedBy_Type       — User / Service Principal / Application / Unknown
  ChangedBy_Source     — Where the identity was resolved from
  ChangedBy_IPAddress  — IP address of the actor (if available)
  ChangedBy_AppName    — Application display name (if applicable)
  ActivityResult       — Success / Failure
  ActivityType         — Full activity type string from Intune audit log
  OldValue             — Previous setting values (most useful for Patch events)
  NewValue             — New setting values after the change
  AuditEventID         — Unique audit event ID from Graph API

CONSOLE SUMMARY includes:
  - Total events pulled and filtered
  - Breakdown by action type
  - OS platform breakdown
  - Unique actors (who made changes)
  - Unique profiles affected
  - Settings change (Patch) count

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Maximum audit log lookback supported by Intune: 2 years.
- Client-side filtering: All DeviceConfiguration events are pulled from Graph
  first, then filtered by operation type locally. In high-volume tenants with
  many DeviceConfiguration events, this may pull more data than needed.
- OldValue / NewValue columns are most valuable for Patch events — they show
  exactly which settings changed and what the before/after values were.
- The script is completely READ-ONLY. No changes are made to any data.
- Credentials ($TenantID, $ClientID, $ClientSecret) must be filled in before
  running. They are intentionally left empty in the distributed version.
- Output files are timestamped — safe to run multiple times without overwriting.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------
Problem : Authentication failed
Fix     : Verify TenantID, ClientID, and ClientSecret are correct.
          Confirm the app registration exists and the secret has not expired.

Problem : No events returned
Fix     : Check the date range. Confirm profile changes occurred in that period.
          Verify DeviceManagementConfiguration.Read.All permission is granted
          with admin consent in Azure AD.

Problem : HTTP 429 errors
Fix     : Script handles 429 automatically using Retry-After header backoff.
          Increase $MaxRetries if needed for very large tenants.

Problem : ChangedBy shows "Unknown — Intune service"
Fix     : This is expected for automated/service-triggered events where no
          human actor identity is available in the audit log.

Problem : OldValue / NewValue columns are empty
Fix     : These are only populated for Patch (settings modified) events.
          Create, Delete, Assign events may not carry modifiedProperties data.

Problem : OSPlatform shows N/A
Fix     : OS platform data is not always present in audit events. This depends
          on how Intune records the event for the specific profile type.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Intune Config Profile Change Auditor — PowerShell + Graph API

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Audit every Configuration Profile change in Microsoft Intune — automatically.

This PowerShell script connects to the Microsoft Graph API and pulls the full
lifecycle of config profile activity from your Intune audit log for any date
range you specify. See exactly what changed, who changed it, and when — with
before-and-after values for every settings modification.

Perfect for compliance reviews, change management audits, configuration drift
detection, and incident investigations.

No third-party modules required. No user login needed. Just fill in your app
credentials, set your date range, and run.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Full lifecycle coverage: Create, Delete, Assign, Remove, Patch, SetReference
- OldValue / NewValue columns — see exactly what settings changed before/after
- Dual-source actor identity resolution (UPN, Service Principal, App, fallback)
- OS platform detection per event (Windows, macOS, iOS, Android, Linux)
- Built-in HTTP 429 throttle protection with Retry-After backoff
- Clean timestamped CSV and log output — no overwriting previous runs
- READ-ONLY — zero changes made to your environment
- Pure PowerShell 5.1 — no extra modules to install
- Hardcoded config block — easy to edit and automate

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Modern Workplace Engineers managing device configuration at scale
- IT Security and Compliance teams running change management audits
- Endpoint Managers investigating unexpected policy changes or drift
- MSPs managing multiple tenants who need regular audit exports
- Anyone who wants a reliable, documented record of Intune config profile changes

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Microsoft Intune, Graph API, PowerShell, Audit Log, Config Profile,
Configuration Profile, Device Management, Change Auditing, Compliance,
Drift Detection, Endpoint Management, Modern Workplace, Azure AD, Entra ID,
MDM, Intune Audit Report, DeviceConfiguration, Intune Automation

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Get-IntuneAuditReport-ConfigProfileChanges.ps1 in VS Code or Notepad.
3. Fill in $TenantID, $ClientID, $ClientSecret in the CONFIGURATION block.
4. Set your $StartDate and $EndDate (format: YYYY-MM-DD).
5. Run the script in PowerShell 5.1 or later.
6. Find your CSV and log file in the same folder as the script.
7. Open the CSV in Excel — filter by ActionLabel, OSPlatform, or ChangedBy
   to drill into specific changes.

For Graph API permission setup help, refer to the Prerequisites section above
or Microsoft's official App Registration documentation.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script make any changes to my Intune environment?
A: No. It is completely READ-ONLY. It only reads audit log data.

Q: Do I need an Intune or Azure AD Premium license?
A: You need a license that includes Intune audit logs (e.g., Intune Plan 1).
   No Azure AD Premium license is required for this script.

Q: How far back can I pull audit data?
A: Intune retains audit logs for up to 2 years.

Q: Can I schedule this script to run automatically?
A: Yes. Use Windows Task Scheduler or Azure Automation with a service principal.

Q: Why does ChangedBy show "Unknown — Intune service"?
A: Some events are triggered by Intune backend services with no human actor.
   This is expected and not an error.

Q: What is the difference between OldValue and NewValue?
A: For Patch (settings modified) events, OldValue shows the setting before the
   change and NewValue shows what it was changed to. Use these columns to detect
   configuration drift without manual snapshot comparison.

Q: Does this require the Microsoft.Graph PowerShell module?
A: No. The script uses direct REST API calls via Invoke-RestMethod only.

================================================================================
  End of README — Get-IntuneAuditReport-ConfigProfileChanges.ps1
  Author: Sethu Kumar B
================================================================================
