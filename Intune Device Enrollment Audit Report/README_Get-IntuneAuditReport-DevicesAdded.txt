================================================================================
  README — Get-IntuneAuditReport-DevicesAdded.ps1
================================================================================

SCRIPT NAME
-----------
  Get-IntuneAuditReport-DevicesAdded.ps1

FOLDER NAME
-----------
  Intune-Audit-Reports

================================================================================
PURPOSE
================================================================================
  This script retrieves all device addition and enrollment events from the
  Microsoft Intune audit log for a specified date range. It helps IT
  administrators and security teams track every device that was enrolled,
  assigned, or modified in Intune — including who performed the action,
  what device was affected, and when it happened.

  The script is READ-ONLY. It makes no changes to your tenant.

================================================================================
WHAT THE SCRIPT DOES
================================================================================
  Step 1 — Authenticates to Microsoft Graph API using Client Credentials
           (Azure AD App Registration).

  Step 2 — Queries the Intune audit log server-side, filtered by:
             - Category   : Device
             - Date Range : StartDate to EndDate (configurable)
           Built-in HTTP 429 throttle protection with Retry-After backoff.

  Step 3 — Filters results client-side for these device addition operations:
             - Create          : Device enrolled / added to Intune
             - Patch           : Device record updated / modified
             - SetReference    : Device relationship added (e.g. user assigned)
             - Assign          : Device assigned to a group or profile

  Step 4 — Resolves actor identity from TWO sources:
             Source 1 — actor object fields (priority order):
               userPrincipalName      → human admin via Intune portal
               servicePrincipalName   → automated service / Autopilot / DEM
               applicationDisplayName → app-based action
               userId GUID            → last resort fallback

             Source 2 — modifiedProperties fallback:
               For enrollment events triggered by the Intune enrollment
               service, actor fields are often empty. The script falls back
               to EnrolledByUserPrincipalName or UserPrincipalName from the
               device record's modifiedProperties. The ActionBy_Source column
               tells you which source was used.

  Step 5 — Extracts OS platform from modifiedProperties or activityType.

  Step 6 — Shapes each event into a clean row and exports:
             - CSV file : Full audit data with 16 columns
             - LOG file : Run log with summary, OS breakdown, actor counts

  Output files are saved to the same folder as the script by default.

================================================================================
PREREQUISITES
================================================================================
  1. PowerShell 5.1 or later
  2. An Azure AD App Registration with:
       - Application (not delegated) permissions
       - Admin consent granted
  3. The following details from your App Registration:
       - Tenant ID
       - Client ID
       - Client Secret
  4. Internet access to reach:
       - https://login.microsoftonline.com
       - https://graph.microsoft.com

================================================================================
REQUIRED MICROSOFT GRAPH API PERMISSIONS
================================================================================
  Permission                               Type          Purpose
  ---------------------------------------  ------------  -----------------------
  DeviceManagementManagedDevices.Read.All  Application   Read device audit events

  > Admin consent is required for Application permissions.
  > READ-ONLY permission — the script does not modify any data.

================================================================================
HOW TO RUN THE SCRIPT
================================================================================
  1. Open the script in any text editor or PowerShell ISE / VS Code.

  2. Fill in the CONFIGURATION block at the top of the script:

       $TenantID     = "your-tenant-id"
       $ClientID     = "your-client-id"
       $ClientSecret = "your-client-secret"
       $StartDate    = "2026-03-01"   # Format: YYYY-MM-DD
       $EndDate      = "2026-03-31"   # Format: YYYY-MM-DD

  3. Optionally adjust the throttle setting:

       $MaxRetries   = 3   # Increase if querying very large date ranges

  4. Save the script.

  5. Open PowerShell and run:

       .\Get-IntuneAuditReport-DevicesAdded.ps1

  6. The CSV and log file will be saved in the same folder as the script.

  NOTE: To query a full month, set StartDate to the 1st and EndDate to the
        last day of that month.
  NOTE: Intune audit logs support a maximum lookback period of 2 years.

================================================================================
EXPECTED OUTPUT
================================================================================
  Two files are created in the script folder (or $OutputFolder if changed):

  1. CSV FILE
     Name    : IntuneAudit_DevicesAdded_[StartDate]_to_[EndDate]_[timestamp].csv
     Columns :
       - EventDateTime      : Date and time of the event (local time)
       - OperationType      : Raw operation (Create, Patch, SetReference, Assign)
       - ActionLabel        : Human-readable label (e.g. DEVICE ENROLLED / ADDED)
       - DeviceName         : Display name of the device
       - DeviceType         : Device type / audit resource type
       - OSPlatform         : Operating system (Windows, iOS, Android, macOS, etc.)
       - ActionBy           : Identity of who performed the action (UPN / SPN / App)
       - ActionBy_Type      : Actor type (User, Service Principal, Application)
       - ActionBy_Source    : Where identity was resolved from (Actor or ModifiedProperties)
       - ActionBy_IPAddress : IP address of the actor (if available)
       - ActionBy_AppName   : Application display name (if app-initiated)
       - ActivityResult     : Result of the operation (Success / Failure)
       - ActivityType       : Detailed activity type from Intune
       - OldValue           : Previous value(s) before the change
       - NewValue           : New value(s) after the change
       - AuditEventID       : Unique Intune audit event ID

  2. LOG FILE
     Name    : IntuneAudit_DevicesAdded_[StartDate]_to_[EndDate]_[timestamp].log
     Content : Step-by-step run log including event counts, OS platform
               breakdown, actor identity source summary, device list (up to 20),
               and actor list.

================================================================================
IMPORTANT NOTES
================================================================================
  - READ-ONLY SCRIPT: No data is created, modified, or deleted in your tenant.

  - CLIENT SECRET SECURITY: Never share or commit your Client Secret to source
    control (e.g. GitHub). Store secrets securely using Azure Key Vault or
    environment variables in production environments.

  - DATE FORMAT: Always use YYYY-MM-DD format for StartDate and EndDate.

  - DATE RANGE LIMIT: Intune audit logs support a maximum lookback of 2 years.

  - ENROLLMENT SERVICE EVENTS: For devices enrolled via Autopilot or the Intune
    enrollment service, the actor fields are often empty because the action is
    service-initiated. The script handles this automatically by reading the
    enrolling user's identity from modifiedProperties. The ActionBy_Source
    column will show "ModifiedProperties (EnrolledByUPN)" for these rows.

  - 429 THROTTLE PROTECTION: If the Graph API returns HTTP 429 (Too Many
    Requests), the script reads the Retry-After header and waits before
    retrying. Up to $MaxRetries retries per page. Increase $MaxRetries for
    very large date ranges.

  - OPERATION TYPE FILTERING: The Graph API does not reliably support filtering
    by multiple activityOperationType values in a single request. Server-side
    filtering is applied on category + date range; operation types are filtered
    client-side.

  - OUTPUT LOCATION: By default, files are saved to $PSScriptRoot (the folder
    containing the script). You can change $OutputFolder in the config block.

  - ENCODING: CSV and log files are saved in UTF-8 encoding.

  - DEVICE LIST IN LOG: The log shows up to 20 unique devices. For the full
    list, refer to the exported CSV.

================================================================================
TROUBLESHOOTING TIPS
================================================================================
  ISSUE   : "Authentication failed" error on startup.
  FIX     : Verify TenantID, ClientID, and ClientSecret are correct. Check that
            the App Registration exists and the Client Secret has not expired.

  ISSUE   : "No device addition events found in the specified date range."
  FIX     : Confirm that devices were enrolled or added in that date range.
            Check the date format (YYYY-MM-DD). Verify the App Registration
            has DeviceManagementManagedDevices.Read.All with admin consent.

  ISSUE   : "Access Denied" or HTTP 403 error.
  FIX     : Ensure admin consent has been granted for
            DeviceManagementManagedDevices.Read.All in the Azure portal.

  ISSUE   : HTTP 429 errors / throttling warnings in the log.
  FIX     : This is handled automatically. The script waits and retries.
            If it persists, increase $MaxRetries in the config block or
            narrow your date range to reduce the query size.

  ISSUE   : ActionBy shows "Unknown — Intune enrollment service".
  FIX     : This means no user identity was found in either the actor fields
            or the device record's modifiedProperties. This can happen for
            fully automated enrollments where no user identity is recorded
            by Intune. No fix is needed — this is expected behaviour.

  ISSUE   : ActionBy shows a GUID instead of a username.
  FIX     : The UPN was not available in the audit event. The script falls
            back to User ID automatically. This can happen for deleted
            accounts or certain automated actions.

  ISSUE   : OSPlatform shows "N/A" for some rows.
  FIX     : OS platform is not always present in audit events, especially
            for Patch or SetReference operations. This is expected. The
            device name and DeviceType columns still identify the device.

  ISSUE   : Script runs slowly or takes a long time.
  FIX     : Normal for large date ranges. The script paginates automatically.
            Narrow the date range to reduce query time.

  ISSUE   : PowerShell execution policy error.
  FIX     : Run the following in PowerShell as Administrator:
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

================================================================================
GUMROAD LISTING TITLE
================================================================================
  Intune Device Enrollment Audit Report — PowerShell Script (Microsoft Graph API)

================================================================================
GUMROAD PRODUCT DESCRIPTION
================================================================================
  Get a complete audit trail of every device enrolled or added to Microsoft
  Intune — exported to a clean, structured CSV report in minutes.

  This ready-to-run PowerShell script connects to the Microsoft Graph API and
  pulls all device addition events for any date range you choose. It captures
  enrollments, record updates, group assignments, and relationship changes —
  and tells you exactly who performed each action, even for automated
  enrollment service events where standard actor fields are empty.

  Simply fill in your Azure AD credentials and date range, run the script,
  and get your report. No extra modules. No tenant changes. 100% read-only.

  Built-in HTTP 429 throttle protection means the script handles large
  environments reliably without losing data.

================================================================================
KEY FEATURES
================================================================================
  - Full Device Addition Lifecycle Coverage
      Captures Enroll, Record Update, Group Assign, and Relationship Add events.

  - Dual-Source Actor Identity Resolution
      Checks actor fields first, then falls back to modifiedProperties for
      enrollment service events (Autopilot / DEM). ActionBy_Source column
      shows exactly where the identity was resolved from.

  - Built-in 429 Throttle Protection
      Reads the Graph API Retry-After header and retries automatically.
      Safe to run on large tenants and long date ranges.

  - OS Platform Detection
      Extracts Windows, iOS, Android, macOS, Linux, or ChromeOS from
      modifiedProperties or activityType string.

  - Clean 16-Column CSV Output
      Structured report ready for Excel, Power BI, or SIEM tools.

  - Configurable Date Range
      Query any date range up to 2 years back. Simple YYYY-MM-DD format.

  - Detailed Run Log
      Every run produces a timestamped log with event counts, OS platform
      breakdown, actor identity source summary, and device list.

  - No Extra Modules Needed
      Uses only built-in PowerShell and direct Graph API calls via
      Invoke-RestMethod.

  - Read-Only and Safe
      Makes no changes to your tenant. Safe to run in production.

================================================================================
WHO THIS SCRIPT IS FOR
================================================================================
  - IT Administrators managing Microsoft Intune / MEM environments
  - Security and Compliance teams auditing device enrollments
  - Microsoft 365 / Endpoint Management engineers
  - MSPs (Managed Service Providers) managing multiple tenants
  - Anyone who needs a clear audit trail of which devices were added to
    Intune, when, and by whom

================================================================================
SUGGESTED TAGS / KEYWORDS
================================================================================
  Intune, Microsoft Intune, PowerShell, Microsoft Graph API, Audit Log,
  Device Enrollment, Intune Audit Report, Endpoint Management, MEM, MDM,
  DeviceManagement, Azure AD, Compliance, IT Automation, CSV Report,
  Device Addition, Autopilot, Windows Enrollment, iOS Enrollment,
  Android Enrollment, PowerShell Script, Read-Only Report, 429 Throttling

================================================================================
BUYER INSTRUCTIONS
================================================================================
  1. Download and extract the ZIP file after purchase.
  2. Open Get-IntuneAuditReport-DevicesAdded.ps1 in a text editor.
  3. Fill in your Tenant ID, Client ID, and Client Secret in the
     CONFIGURATION block at the top of the script.
  4. Set your desired StartDate and EndDate (YYYY-MM-DD format).
  5. Optionally adjust $MaxRetries (default: 3) for large environments.
  6. Run the script in PowerShell 5.1 or later.
  7. Find your CSV and log file in the same folder as the script.

  REQUIREMENT: An Azure AD App Registration with
  DeviceManagementManagedDevices.Read.All (Application permission, admin
  consent granted) is required before running this script.

================================================================================
COMMON QUESTIONS / FAQ
================================================================================
  Q: Does this script make any changes to my Intune environment?
  A: No. This is a 100% read-only script. It only reads audit data and exports
     it to a CSV file. Nothing in your tenant is modified.

  Q: Do I need to install any extra PowerShell modules?
  A: No. The script uses only built-in PowerShell and calls the Microsoft
     Graph API directly using Invoke-RestMethod.

  Q: What PowerShell version do I need?
  A: PowerShell 5.1 or later. Works on Windows PowerShell and PowerShell 7+.

  Q: What Azure AD permission is required?
  A: DeviceManagementManagedDevices.Read.All — Application permission with
     admin consent. You will need an App Registration in Azure AD.

  Q: How far back can I query audit logs?
  A: Microsoft Intune retains audit logs for up to 2 years.

  Q: Why does ActionBy show "Unknown — Intune enrollment service" for some rows?
  A: For fully automated enrollments (e.g. zero-touch Autopilot), Intune does
     not always record a user identity in either the actor fields or the device
     record. This is expected behaviour from Intune — not a script issue.

  Q: What is the ActionBy_Source column?
  A: It tells you where the actor identity was resolved from. "Actor (UPN)"
     means it came directly from the audit event's actor fields.
     "ModifiedProperties (EnrolledByUPN)" means the script found the identity
     in the device record's property changes — common for enrollment events.

  Q: What does the script do when it hits a 429 throttling error?
  A: It reads the Retry-After header from the Graph API response, waits that
     many seconds (plus a small random jitter), then retries the same page.
     This happens automatically — you do not need to do anything.

  Q: Can I change where the output files are saved?
  A: Yes. Change the $OutputFolder variable in the CONFIGURATION block to any
     valid folder path on your machine.

  Q: Does this work in multi-tenant MSP environments?
  A: Yes. Update TenantID, ClientID, and ClientSecret for each tenant and
     run the script separately per tenant.

  Q: What if I get an HTTP 403 error?
  A: Admin consent has not been granted. Go to Azure portal > Azure AD >
     App Registrations > your app > API Permissions and click
     "Grant admin consent".

  Q: How is this different from the Intune App Assignments audit script?
  A: That script focuses on application changes (category: Application).
     This script focuses on device additions and enrollments (category: Device).
     Both can be used together for a complete Intune audit picture.

================================================================================
  Script by  : Sethu Kumar B
  Version    : 1.2
  Last Update: 2026-04-10
  READ-ONLY  : No changes are made to your tenant.
================================================================================
