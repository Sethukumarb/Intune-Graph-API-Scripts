================================================================================
  README — Get-IntuneAuditReport-ProfileAssignmentChanges.ps1
  Author : Sethu Kumar B
  Version: 1.2
================================================================================

SCRIPT NAME
-----------
Get-IntuneAuditReport-ProfileAssignmentChanges.ps1

FOLDER NAME
-----------
Intune-Audit-Reports

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Retrieves Configuration Profile assignment and lifecycle changes from the
Microsoft Intune audit log for a specified date range. Focused on tracking
who assigned, removed, created, deleted, or modified configuration profiles —
exported as a clean, ready-to-filter CSV for audit and compliance reviews.

Lightweight version — no throttle retry logic. Suitable for small-to-medium
tenants or quick audit pulls where 429 rate limiting is not a concern.

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
     - Patch           : Profile settings or assignment modified
     - SetReference    : Assignment relationship added or updated

4. Resolves actor identity per event:
     Priority: UPN → Service Principal Name → App Display Name → User ID

5. Captures OldValue and NewValue for changed properties where available.

6. Exports a timestamped CSV and log file to the script's own folder ($PSScriptRoot).

--------------------------------------------------------------------------------
DIFFERENCE FROM Get-IntuneAuditReport-ConfigProfileChanges.ps1
--------------------------------------------------------------------------------
Feature                          This Script        ConfigProfileChanges Script
-------------------------------  -----------------  ---------------------------
429 Retry-After backoff          No                 Yes
Dual-source actor resolution     No (actor only)    Yes (actor + modifiedProps)
ChangedBy_Type column            No                 Yes
ChangedBy_Source column          No                 Yes
OSPlatform column in CSV         No                 Yes
Best for                         Small/medium tenant  Large/enterprise tenant

Use this script for quick, lightweight audit pulls.
Use ConfigProfileChanges script for large tenants or production-grade auditing.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Azure AD App Registration with a Client Secret
- Admin consent granted for required Graph API permissions (see below)

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

Step 3 — Save and run:

    .\Get-IntuneAuditReport-ProfileAssignmentChanges.ps1

Step 4 — Find the output CSV and log in the same folder as the script.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Two files saved to $PSScriptRoot (same folder as the script):

  IntuneAudit_GroupAssignments_[StartDate]_to_[EndDate]_[timestamp].csv
  IntuneAudit_GroupAssignments_[StartDate]_to_[EndDate]_[timestamp].log

CSV COLUMNS:
  EventDateTime         — Date and time of the change (local time)
  OperationType         — Raw operation: Create, Delete, Assign, Patch, etc.
  ActionLabel           — Human-readable label: PROFILE CREATED, ASSIGNED TO GROUP, etc.
  ProfileName           — Name of the configuration profile affected
  ProfileType           — Audit resource type
  ComponentName         — Intune component that generated the event
  ChangedBy_UPN         — UPN of the admin, or service principal name if automated
  ChangedBy_DisplayName — Application display name (if app-triggered)
  ChangedBy_IPAddress   — IP address of the actor (if available)
  ChangedBy_AppName     — Application name (if applicable)
  ActivityResult        — Success / Failure
  ActivityType          — Full activity type string from Intune audit log
  OldValue              — Previous property values (where available)
  NewValue              — New property values after the change
  AuditEventID          — Unique audit event ID from Graph API

CONSOLE SUMMARY includes:
  - Total events pulled and filtered
  - Breakdown by action type
  - Unique actors (who made changes)

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- No 429 throttle protection. If Graph API returns HTTP 429 (rate limit), the
  script will log the error and stop paginating. For large tenants or wide date
  ranges, use Get-IntuneAuditReport-ConfigProfileChanges.ps1 instead.
- Maximum audit log lookback supported by Intune: 2 years.
- Client-side filtering: All DeviceConfiguration events are pulled first, then
  filtered by operation type locally.
- This script is completely READ-ONLY. No changes are made to any data.
- Credentials must be filled in before running. They are intentionally left
  empty in the distributed version.
- Output files are timestamped — safe to run multiple times without overwriting.

--------------------------------------------------------------------------------
TROUBLESHOOTING
--------------------------------------------------------------------------------
Problem : Authentication failed
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Confirm the app registration exists and secret has not expired.

Problem : No events returned
Fix     : Check the date range. Confirm profile changes occurred in that period.
          Verify DeviceManagementConfiguration.Read.All is granted with admin
          consent in Azure AD.

Problem : Script stops mid-run / HTTP 429 error in log
Fix     : Tenant volume is too high for this script. Switch to
          Get-IntuneAuditReport-ConfigProfileChanges.ps1 which has built-in
          Retry-After backoff.

Problem : ChangedBy_UPN shows "N/A" or Service Principal name
Fix     : Expected for automated/service-triggered events. No human UPN is
          available in the audit log for those events.

Problem : OldValue / NewValue columns are empty
Fix     : These are only populated where Intune includes modifiedProperties
          in the audit event. Not all operation types carry this data.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Intune Profile Assignment Change Auditor — PowerShell + Graph API

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Track every Intune Configuration Profile assignment change — fast and simple.

This lightweight PowerShell script connects to the Microsoft Graph API and
exports a clean CSV of all profile assignment and lifecycle events from your
Intune audit log. See who assigned, removed, created, or deleted configuration
profiles — across any date range you choose.

No third-party modules required. No user login needed. Fill in your app
credentials, set your date range, and run.

Ideal for smaller tenants, quick audit pulls, and teams that need a no-frills
CSV export without complex setup.

Need enterprise-grade auditing with 429 throttle protection, dual-source actor
resolution, and OS platform detection? See the companion script:
Get-IntuneAuditReport-ConfigProfileChanges.ps1

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Full lifecycle coverage: Create, Delete, Assign, Remove, Patch, SetReference
- Actor identity resolution: UPN → Service Principal → App Name → User ID
- OldValue / NewValue columns for changed property tracking
- Clean timestamped CSV and log — no overwriting previous runs
- READ-ONLY — zero changes made to your environment
- Pure PowerShell 5.1 — no extra modules required
- Lightweight — no retry logic overhead, fast for small tenants

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Modern Workplace Engineers needing quick assignment audit exports
- IT admins tracking who assigned or removed profiles from groups
- Compliance teams running periodic change reviews on smaller tenants
- MSPs needing a simple, portable audit script with no dependencies
- Anyone who wants a fast CSV of Intune profile changes without heavy tooling

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Microsoft Intune, Graph API, PowerShell, Audit Log, Config Profile,
Configuration Profile, Group Assignment, Device Management, Change Auditing,
Compliance, Endpoint Management, Modern Workplace, Azure AD, Entra ID,
MDM, Intune Audit Report, DeviceConfiguration, Intune Automation,
Profile Assignment, Assignment Change

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Rename the script to:
   Get-IntuneAuditReport-ProfileAssignmentChanges.ps1
3. Open in VS Code or Notepad.
4. Fill in $TenantID, $ClientID, $ClientSecret in the CONFIGURATION block.
5. Set your $StartDate and $EndDate (format: YYYY-MM-DD).
6. Run in PowerShell 5.1 or later.
7. Find your CSV and log in the same folder as the script.
8. Open CSV in Excel — filter by ActionLabel or ChangedBy_UPN to focus on
   specific assignment changes.

NOTE: If your tenant has high audit volume and the script stops mid-run,
switch to the ConfigProfileChanges companion script which handles throttling.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script make any changes to my Intune environment?
A: No. It is completely READ-ONLY.

Q: How is this different from the ConfigProfileChanges script?
A: This is the lightweight version — no 429 throttle protection, no OS platform
   column, no modifiedProperties actor fallback. Faster and simpler for small
   tenants. The ConfigProfileChanges script is production-grade for large tenants.

Q: Do I need an Intune or Azure AD Premium license?
A: You need a license that includes Intune audit logs (e.g., Intune Plan 1).
   No Azure AD Premium license is required.

Q: How far back can I pull audit data?
A: Intune retains audit logs for up to 2 years.

Q: Can I schedule this to run automatically?
A: Yes. Use Windows Task Scheduler or Azure Automation with a service principal.

Q: Does this require the Microsoft.Graph PowerShell module?
A: No. Uses direct REST API calls via Invoke-RestMethod only.

Q: The script stopped mid-run. What happened?
A: Likely an HTTP 429 rate limit from Graph API. This script has no retry logic.
   Use the ConfigProfileChanges companion script for large tenants.

================================================================================
  End of README — Get-IntuneAuditReport-ProfileAssignmentChanges.ps1
  Author: Sethu Kumar B
================================================================================
