================================================================================
  README - Get-IntuneAuditReport-DevicesDeleted.ps1
  Author : Sethu Kumar B
================================================================================

SCRIPT NAME
-----------
Get-IntuneAuditReport-DevicesDeleted.ps1

FOLDER NAME
-----------
Get-IntuneAuditReport-DevicesDeleted

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Retrieves all device deletion events from the Intune audit log for a specified
date range via the Microsoft Graph API.

Use this script to investigate who deleted devices from Intune, when, and
from which platform — with full actor identity resolution and throttle-safe
pagination. Produces a timestamped CSV and log file for audit or compliance
review. No changes are made to any device or record.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Authenticates to Microsoft Graph API using Azure AD app credentials
   (client credentials flow — no user sign-in required).

2. Pulls all Device category audit events within the specified date range
   using server-side OData filtering on activityDateTime.
   Built-in 429 Retry-After backoff protects against Graph API throttling.

3. Filters client-side for deletion operations:
     Delete           — device record deleted from Intune
     RemoveReference  — device relationship removed (user unassigned,
                        device removed from group, etc.)

4. Resolves actor identity using two sources:
     Source 1 — actor object fields (priority order):
       userPrincipalName       → human admin via Intune portal
       servicePrincipalName    → automated service action
       applicationDisplayName  → app-based action
       userId GUID             → last resort fallback

     Source 2 — modifiedProperties fallback:
       For events triggered internally by the Intune service where actor
       fields are empty, identity is resolved from:
         UserPrincipalName
         EnrolledByUserPrincipalName

5. Extracts OS platform from modifiedProperties (OperatingSystem field)
   or parses it from the activityType string as a fallback.

6. Shapes each event into a clean CSV row with 17 columns.

7. Sorts results by EventDateTime descending (most recent first).

8. Exports timestamped CSV and log file to $PSScriptRoot.

9. Prints a full summary to console:
     - Total events pulled vs deletion events found
     - Breakdown by operation type (Delete / RemoveReference)
     - OS platform breakdown
     - Actor breakdown (user vs service/app)
     - Unique deleted devices (first 20 shown; full list in CSV)
     - Unique actors who performed deletions

NO changes are made to any Intune device or audit record.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Azure AD App Registration with:
    - Tenant ID
    - Client ID
    - Client Secret
- Admin consent granted for required Graph API permission (see below)
- Network access to:
    - login.microsoftonline.com
    - graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission Type : Application (no user sign-in required)
Permission Name : DeviceManagementManagedDevices.Read.All
Admin Consent   : Required

Note: A read-only app registration is sufficient and recommended.

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1 - Open the script file:
         Get-IntuneAuditReport-DevicesDeleted.ps1

Step 2 - Fill in your credentials and date range in the CONFIGURATION block:

         $TenantID     = "your-tenant-id"
         $ClientID     = "your-client-id"
         $ClientSecret = "your-client-secret"
         $StartDate    = "2026-03-01"   (YYYY-MM-DD format)
         $EndDate      = "2026-03-31"   (YYYY-MM-DD format)

Step 3 - Open PowerShell 5.1 or later.

Step 4 - Navigate to the script folder:
         cd "C:\Path\To\Get-IntuneAuditReport-DevicesDeleted"

Step 5 - Run the script:
         .\Get-IntuneAuditReport-DevicesDeleted.ps1

Step 6 - Review the console summary and the generated CSV and log files.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console:
  - Step-by-step progress with colour-coded log messages
  - Summary: deletion counts, OS breakdown, actor breakdown
  - First 20 unique deleted device names
  - First 20 unique actor identities

Files (saved to same folder as the script):
  - IntuneAudit_DevicesDeleted_[StartDate]_to_[EndDate]_[Timestamp].csv
  - IntuneAudit_DevicesDeleted_[StartDate]_to_[EndDate]_[Timestamp].log

CSV Columns (17):
  EventDateTime, OperationType, ActionLabel,
  DeviceName, DeviceType, OSPlatform,
  DeletedBy, DeletedBy_Type, DeletedBy_Source,
  DeletedBy_IPAddress, DeletedBy_AppName,
  ActivityResult, ActivityType,
  OldValue, NewValue, AuditEventID

--------------------------------------------------------------------------------
OPERATION TYPE VALUES
--------------------------------------------------------------------------------
Delete           - Device record was deleted from Intune
RemoveReference  - Device relationship was removed (e.g. user unassigned,
                   device removed from a group)

--------------------------------------------------------------------------------
DELETEDBY_SOURCE VALUES
--------------------------------------------------------------------------------
Actor (UPN)                                       - Resolved from actor.userPrincipalName
Actor (Service Principal)                         - Resolved from actor.servicePrincipalName
Actor (Application)                               - Resolved from actor.applicationDisplayName
Actor (User ID)                                   - Only a GUID was available; UPN not present
ModifiedProperties (UserPrincipalName)            - Resolved from modifiedProperties fallback
ModifiedProperties (EnrolledByUserPrincipalName)  - Resolved from modifiedProperties fallback
Not available                                     - Identity could not be resolved

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Maximum audit log lookback supported by Intune: 2 years.

- This script is READ-ONLY. No changes are made to any device or audit record.

- The Graph API v1.0 endpoint is used for audit events. This is stable
  and preferred over the beta endpoint for audit log queries.

- For environments with a large number of Device category events in the
  date range, the script may take several minutes to page through all results.
  Reduce the date range if performance is a concern.

- OldValue column is the most useful column for Delete events — it contains
  device properties that existed before deletion (serial number, OS version,
  compliance state, etc.).

- Actor identity may show "Unknown — Intune service" for events triggered
  automatically by the Intune service (e.g. stale device cleanup policies).
  This is expected behaviour, not a script limitation.

- $MaxRetries (default: 3) controls how many times a page fetch is retried
  on HTTP 429. Increase this value for heavily throttled environments.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Problem : Authentication fails immediately
Fix     : Verify TenantID, ClientID, and ClientSecret are correct.
          Confirm the app secret has not expired in Azure AD.

Problem : 0 events returned for a known date range
Fix     : Check admin consent is granted for
          DeviceManagementManagedDevices.Read.All.
          Confirm the date range format is YYYY-MM-DD.
          Intune audit logs only go back 2 years maximum.

Problem : 0 deletion events found but you expect some
Fix     : The script filters for Delete and RemoveReference operations.
          Verify that the deletions occurred within the specified date range.
          Check the Intune portal audit log manually for the same period
          to confirm events exist.

Problem : DeletedBy shows "Unknown — Intune service" for many records
Fix     : This is expected for system-triggered deletions (e.g. auto-retire,
          stale device cleanup). The Intune service does not populate actor
          fields for these events. This is a Microsoft API behaviour.

Problem : OldValue column is empty for some records
Fix     : Not all audit events populate modifiedProperties. This depends on
          how the deletion was triggered (portal, API, automation, policy).

Problem : HTTP 429 errors in the log
Fix     : The script handles this automatically using Retry-After backoff.
          If throttling is severe, increase $MaxRetries or reduce the date
          range to retrieve fewer events per run.

Problem : CSV not created
Fix     : Verify write permission to the script folder.
          Check the log file for the exact error message.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Intune Audit – Device Deletion Report | Microsoft Graph API PowerShell Script

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Know exactly who deleted devices from Intune — and when.

This PowerShell script connects to the Microsoft Graph API and retrieves all
device deletion events from the Intune audit log for any date range you
specify (up to 2 years back). It captures both outright deletions and device
relationship removals, resolves the identity of whoever triggered each event,
and exports a clean timestamped CSV ready for audit review, compliance
reporting, or incident investigation.

Built for environments where device deletions need to be tracked and
accountable — whether triggered by an admin, an automated service, or an
internal Intune policy.

What you get:
- Production-ready PowerShell script (PS 5.1 compatible)
- Server-side date range filtering — only pulls what you need
- Dual-source actor identity resolution (actor fields + modifiedProperties)
- OS platform detection per deletion event
- Built-in 429 Retry-After throttle protection with configurable retries
- 17-column CSV export with full event details
- Timestamped log file for every run
- Console summary: counts, OS breakdown, actor breakdown, device list
- This README with setup instructions, troubleshooting, and Graph permissions

No external modules required. No interactive sign-in. Run it from any
PowerShell 5.1 environment.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Captures Delete and RemoveReference operations from Intune audit log
- Server-side OData filtering — only retrieves Device category events
  for the specified date range (efficient, not full log dumps)
- Full pagination — handles large environments with 1000+ audit events
- Dual-source actor resolution — identifies human admins, service principals,
  apps, and falls back to modifiedProperties for Intune-triggered events
- OS platform detection per event (Windows, macOS, iOS, Android, etc.)
- 429 Retry-After backoff — throttle-safe for production environments
- Sorted output — most recent deletions appear first in CSV
- DeletedBy_Source column — shows exactly where identity was resolved from
- OldValue column — captures device properties as they existed before deletion
- Read-only — no changes made to any Intune record
- $PSScriptRoot output — works from any folder without path changes
- No external modules — pure PowerShell 5.1 with Invoke-RestMethod

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Endpoint Engineers investigating unexpected device deletions
- IT Security teams auditing device lifecycle for compliance
- Modern Workplace admins generating deletion reports for management
- SOC analysts investigating potential unauthorised device removals
- Anyone who needs an accountable, exportable record of Intune device deletions

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Microsoft Intune, Audit Log, Device Deletion, PowerShell,
Microsoft Graph API, DeviceManagementManagedDevices, Endpoint Management,
Modern Workplace, Device Lifecycle, Compliance Report, Actor Resolution,
Intune Automation, Deleted Devices, Audit Report, Graph API PowerShell,
Delete Audit, RemoveReference, Identity Resolution

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Get-IntuneAuditReport-DevicesDeleted.ps1 in any text editor
   or PowerShell ISE.
3. Fill in your TenantID, ClientID, ClientSecret, StartDate, and EndDate
   in the CONFIGURATION block at the top of the script.
4. Ensure your Azure AD App Registration has admin consent for:
   DeviceManagementManagedDevices.Read.All (Application permission).
5. Run the script from PowerShell 5.1 or later.
6. Review the console summary and the generated CSV and log files in the
   same folder as the script.
7. See the TROUBLESHOOTING TIPS section if you encounter any issues.

For questions or support, contact the author via the Gumroad product page.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script delete or modify any Intune records?
A: No. It is fully read-only. It only reads audit events and exports a report.

Q: How far back can I query audit events?
A: Intune audit logs support a maximum lookback of 2 years.

Q: Why does DeletedBy show "Unknown — Intune service" for some records?
A: System-triggered events (auto-retire, stale device cleanup, policy-based
   removal) do not populate actor fields in the Graph API response. This is
   a Microsoft API behaviour, not a script limitation.

Q: Can I run this for a single day?
A: Yes. Set StartDate and EndDate to the same date.
   Example: $StartDate = "2026-04-10"  $EndDate = "2026-04-10"

Q: What does RemoveReference mean vs Delete?
A: Delete = the device record was permanently removed from Intune.
   RemoveReference = a relationship was removed (e.g. primary user unassigned,
   device removed from a group) without deleting the device record itself.

Q: Can I run this on a schedule for monthly reports?
A: Yes. It uses client credentials (non-interactive) and exits cleanly.
   Store credentials securely (e.g. Azure Key Vault or encrypted file)
   before scheduling via Task Scheduler or Azure Automation.

Q: What PowerShell version is required?
A: PowerShell 5.1 or later. No external modules required.

Q: Can I adjust the throttle retry behaviour?
A: Yes. Change $MaxRetries in the CONFIGURATION block. Default is 3.
   The script reads the Retry-After header from each 429 response and waits
   accordingly, plus a random 1-5 second jitter to avoid thundering herd.

================================================================================
  End of README - Get-IntuneAuditReport-DevicesDeleted.ps1
  Author : Sethu Kumar B
================================================================================
