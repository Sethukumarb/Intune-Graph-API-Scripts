================================================================================
  README — Get-IntuneAuditReport-AppAssignments.ps1
================================================================================

SCRIPT NAME
-----------
  Get-IntuneAuditReport-AppAssignments.ps1

FOLDER NAME
-----------
  Intune-Audit-Reports

================================================================================
PURPOSE
================================================================================
  This script retrieves all Application-related audit events from the Microsoft
  Intune audit log for a specified date range. It helps IT administrators and
  security teams track every change made to applications managed in Intune —
  including who made the change, what was changed, and when it happened.

  The script is READ-ONLY. It makes no changes to your tenant.

================================================================================
WHAT THE SCRIPT DOES
================================================================================
  Step 1 — Authenticates to Microsoft Graph API using Client Credentials
           (Azure AD App Registration).

  Step 2 — Queries the Intune audit log server-side, filtered by:
             - Category     : Application
             - Date Range   : StartDate to EndDate (configurable)

  Step 3 — Filters results client-side for these lifecycle operations:
             - Create          : App added to Intune
             - Delete          : App removed from Intune
             - Assign          : App assigned to a group
             - RemoveReference : App removed from a group
             - Patch           : App settings or assignment modified
             - SetReference    : Assignment relationship added or updated

  Step 4 — Resolves actor identity (who made the change):
             Priority: UPN > Service Principal > App Display Name > User ID

  Step 5 — Shapes each event into a clean row and exports:
             - CSV file  : Full audit data with 17 columns
             - LOG file  : Run log with summary and event counts

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
  Permission                      Type          Purpose
  ------------------------------  ------------  --------------------------------
  DeviceManagementApps.Read.All   Application   Read Intune app audit events

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

  3. Save the script.

  4. Open PowerShell and run:

       .\Get-IntuneAuditReport-AppAssignments.ps1

  5. The CSV and log file will be saved in the same folder as the script.

  NOTE: To query a full month, set StartDate to the 1st and EndDate to the
        last day of that month.
  NOTE: Intune audit logs support a maximum lookback period of 2 years.

================================================================================
EXPECTED OUTPUT
================================================================================
  Two files are created in the script folder (or $OutputFolder if changed):

  1. CSV FILE
     Name    : IntuneAudit_AppAssignments_[StartDate]_to_[EndDate]_[timestamp].csv
     Columns :
       - EventDateTime         : Date and time of the event (local time)
       - OperationType         : Raw operation (Create, Delete, Assign, etc.)
       - ActionLabel           : Human-readable label (e.g. APP ASSIGNED TO GROUP)
       - AppName               : Display name of the application
       - AppType               : App type (e.g. Win32LobApp, iOSStoreApp)
       - OSPlatform            : Operating system platform (if available)
       - ComponentName         : Intune component that logged the event
       - ChangedBy_UPN         : UPN or identity of the person/app that made the change
       - ChangedBy_Type        : Actor type (User, Service Principal, Application)
       - ChangedBy_DisplayName : Display name of the actor
       - ChangedBy_IPAddress   : IP address of the actor (if available)
       - ChangedBy_AppName     : Application display name (if change was app-initiated)
       - ActivityResult        : Result of the operation (Success / Failure)
       - ActivityType          : Detailed activity type from Intune
       - OldValue              : Previous value(s) before the change
       - NewValue              : New value(s) after the change
       - AuditEventID          : Unique Intune audit event ID

  2. LOG FILE
     Name    : IntuneAudit_AppAssignments_[StartDate]_to_[EndDate]_[timestamp].log
     Content : Step-by-step run log including event counts, actor list,
               affected app list, and final summary.

================================================================================
IMPORTANT NOTES
================================================================================
  - READ-ONLY SCRIPT: No data is created, modified, or deleted in your tenant.
  - CLIENT SECRET SECURITY: Never share or commit your Client Secret to source
    control (e.g. GitHub). Store secrets securely using Azure Key Vault or
    environment variables in production environments.
  - DATE FORMAT: Always use YYYY-MM-DD format for StartDate and EndDate.
  - DATE RANGE LIMIT: Intune audit logs support a maximum lookback of 2 years.
  - LARGE DATE RANGES: Querying several months of data may take a few minutes
    due to pagination. The script handles this automatically.
  - OPERATION TYPE FILTERING: The Graph API does not reliably support filtering
    by multiple activityOperationType values in a single request. The script
    applies server-side filtering on category + date range, then filters
    operation types client-side from the reduced result set.
  - OUTPUT LOCATION: By default, files are saved to $PSScriptRoot (the folder
    containing the script). You can change $OutputFolder in the config block.
  - ENCODING: CSV and log files are saved in UTF-8 encoding.

================================================================================
TROUBLESHOOTING TIPS
================================================================================
  ISSUE   : "Authentication failed" error on startup.
  FIX     : Verify TenantID, ClientID, and ClientSecret are correct. Check that
            the App Registration exists and the Client Secret has not expired.

  ISSUE   : "No events found in the specified date range."
  FIX     : Confirm that application changes occurred in that date range.
            Check the date format (YYYY-MM-DD). Verify the App Registration
            has DeviceManagementApps.Read.All with admin consent.

  ISSUE   : CSV is empty or has very few rows.
  FIX     : Widen the date range. Verify that the correct tenant is being
            queried. Some operations may not generate audit events if no
            changes were made.

  ISSUE   : "Access Denied" or HTTP 403 error.
  FIX     : Ensure admin consent has been granted for
            DeviceManagementApps.Read.All in the Azure portal.

  ISSUE   : Script runs slowly or takes a long time.
  FIX     : This is normal for large date ranges. The script paginates
            through all results automatically. Narrow the date range
            to reduce query time.

  ISSUE   : ChangedBy_UPN shows a GUID instead of a username.
  FIX     : This means the UPN was not available in the audit event.
            The script falls back to User ID automatically. This can happen
            for deleted accounts or certain service-initiated changes.

  ISSUE   : PowerShell execution policy error.
  FIX     : Run the following in PowerShell as Administrator:
            Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

================================================================================
GUMROAD LISTING TITLE
================================================================================
  Intune App Audit Report — PowerShell Script (Microsoft Graph API)

================================================================================
GUMROAD PRODUCT DESCRIPTION
================================================================================
  Track every application change in your Microsoft Intune environment with this
  ready-to-run PowerShell script.

  Whether an app was added, removed, assigned to a group, or modified — this
  script captures the full audit trail and exports it to a clean, structured
  CSV report in minutes.

  Simply fill in your Azure AD credentials and date range, run the script, and
  get a complete picture of all Intune application activity — including who made
  the change, what was changed, and when.

  No third-party modules required. No data is modified. 100% read-only.

================================================================================
KEY FEATURES
================================================================================
  - Full App Lifecycle Coverage
      Captures Create, Delete, Assign, Remove, Modify, and assignment
      relationship events — nothing is missed.

  - Smart Actor Resolution
      Identifies who made each change: User UPN, Service Principal,
      App Display Name, or User ID — with fallback priority logic.

  - Clean 17-Column CSV Output
      Structured report ready for Excel, Power BI, or SIEM tools.

  - Configurable Date Range
      Query any date range up to 2 years back. Easy YYYY-MM-DD format.

  - Detailed Run Log
      Every run produces a timestamped log with event counts, affected apps,
      and actor summary.

  - No Extra Modules Needed
      Uses only built-in PowerShell and direct Graph API calls via
      Invoke-RestMethod.

  - Read-Only and Safe
      Makes no changes to your tenant. Safe to run in production.

  - Handles Pagination Automatically
      Follows all @odata.nextLink pages — works with large tenants.

================================================================================
WHO THIS SCRIPT IS FOR
================================================================================
  - IT Administrators managing Microsoft Intune environments
  - Security and Compliance teams auditing application changes
  - Microsoft 365 / Endpoint Management engineers
  - MSPs (Managed Service Providers) managing multiple tenants
  - Anyone who needs a quick, clear audit trail of Intune app activity

================================================================================
SUGGESTED TAGS / KEYWORDS
================================================================================
  Intune, Microsoft Intune, PowerShell, Microsoft Graph API, Audit Log,
  App Assignment, Intune Audit Report, Endpoint Management, MEM, MDM,
  DeviceManagement, Azure AD, Compliance, IT Automation, CSV Report,
  Application Lifecycle, Intune Apps, PowerShell Script, Read-Only Report

================================================================================
BUYER INSTRUCTIONS
================================================================================
  1. Download and extract the ZIP file after purchase.
  2. Open Get-IntuneAuditReport-AppAssignments.ps1 in a text editor.
  3. Fill in your Tenant ID, Client ID, and Client Secret in the
     CONFIGURATION block at the top of the script.
  4. Set your desired StartDate and EndDate (YYYY-MM-DD format).
  5. Run the script in PowerShell 5.1 or later.
  6. Find your CSV and log file in the same folder as the script.

  REQUIREMENT: An Azure AD App Registration with
  DeviceManagementApps.Read.All (Application permission, admin consent granted)
  is required before running this script.

================================================================================
COMMON QUESTIONS / FAQ
================================================================================
  Q: Does this script make any changes to my Intune environment?
  A: No. This is a 100% read-only script. It only reads audit data and exports
     it to a CSV file. Nothing in your tenant is modified.

  Q: Do I need to install any extra PowerShell modules?
  A: No. The script uses only built-in PowerShell commands and calls the
     Microsoft Graph API directly using Invoke-RestMethod.

  Q: What PowerShell version do I need?
  A: PowerShell 5.1 or later. Works on Windows PowerShell and PowerShell 7+.

  Q: What Azure AD permission is required?
  A: DeviceManagementApps.Read.All — Application permission with admin consent.
     You will need to create an App Registration in Azure AD if you do not
     already have one.

  Q: How far back can I query audit logs?
  A: Microsoft Intune retains audit logs for up to 2 years.

  Q: Can I query a full month of data?
  A: Yes. Set StartDate to the 1st and EndDate to the last day of the month.
     For example: StartDate = "2026-03-01", EndDate = "2026-03-31".

  Q: Why does ChangedBy_UPN show a GUID for some rows?
  A: The UPN is not always available in the audit event — this can happen for
     deleted accounts or service-initiated changes. The script falls back to
     User ID automatically in these cases.

  Q: Can I change where the output files are saved?
  A: Yes. Change the $OutputFolder variable in the CONFIGURATION block to any
     valid folder path on your machine.

  Q: Does this work in multi-tenant MSP environments?
  A: Yes. Update the TenantID, ClientID, and ClientSecret values for each
     tenant and run the script separately per tenant.

  Q: What if I get an HTTP 403 error?
  A: This means admin consent has not been granted for the App Registration.
     Go to Azure portal > Azure AD > App Registrations > your app >
     API Permissions and click "Grant admin consent".

================================================================================
  Script by  : Sethu Kumar B
  Version    : 1.1
  Last Update: 2026-04-10
  READ-ONLY  : No changes are made to your tenant.
================================================================================
