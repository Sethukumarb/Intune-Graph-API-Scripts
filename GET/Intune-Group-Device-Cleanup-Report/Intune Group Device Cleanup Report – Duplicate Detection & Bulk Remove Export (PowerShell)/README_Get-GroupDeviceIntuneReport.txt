================================================================================
  README — Get-GroupDeviceIntuneReport.ps1
  Intune Group Device Cleanup Report – Duplicate Detection & Bulk Remove Export
  Version: 2.0
================================================================================

────────────────────────────────────────────────────────────────────────────────
  SCRIPT NAME
────────────────────────────────────────────────────────────────────────────────

  Get-GroupDeviceIntuneReport.ps1

────────────────────────────────────────────────────────────────────────────────
  FOLDER NAME
────────────────────────────────────────────────────────────────────────────────

  Intune-Group-Device-Cleanup-Report

────────────────────────────────────────────────────────────────────────────────
  PURPOSE
────────────────────────────────────────────────────────────────────────────────

  Audits an Azure AD / Entra ID group for stale and duplicate device records.
  For every device hostname in the group, the script searches both Intune and
  Azure AD, cross-references all records, elects the single authoritative
  (Unique Active) Intune entry per device, and tells you exactly what to keep
  and what to remove — with a Bulk Remove TXT file ready for direct upload to
  the Entra portal.

  READ-ONLY. No changes are made to the group, devices, or any records.

────────────────────────────────────────────────────────────────────────────────
  WHY THIS SCRIPT EXISTS
────────────────────────────────────────────────────────────────────────────────

  Static Azure AD groups accumulate stale and duplicate device objects over
  time — from re-enrollments, device wipes, Autopilot resets, or manual
  additions. When a group is used for policy assignment or compliance
  reporting, duplicate records cause:

    — Incorrect compliance counts (stale record may show non-compliant)
    — Policy applying to the wrong device object
    — Confusing Intune device lists with multiple entries per hostname
    — Inaccurate group membership counts in Entra portal

  This script identifies exactly which group members are authoritative and
  which are stale — and generates the Bulk Remove file so cleanup takes
  minutes, not hours.

────────────────────────────────────────────────────────────────────────────────
  WHAT THE SCRIPT DOES
────────────────────────────────────────────────────────────────────────────────

  Step 1 — Detects group type (Security Group or Intune Dynamic Device Group).

  Step 2 — Pulls ALL device members from the group (paginated).
           User members are skipped automatically at the API level.

  Step 3 — For each unique device hostname:

       a) Searches Intune for ALL matching managed device records by hostname.
       b) Searches Azure AD for ALL matching device objects by hostname.
       c) Cross-references Intune ↔ Azure AD records using azureADDeviceId.
       d) Elects ONE "Unique Active" Intune record per hostname:
            Primary  → newest enrolledDateTime
            Fallback → most recent lastSyncDateTime
                       (used when enrolled dates are equal or missing)
       e) Assigns a VERDICT and GroupAction to every row.

  Step 4 — Exports THREE output files:

    FILE 1 — Full CSV Report:
      Get-GroupDeviceIntuneReport_[timestamp].csv
      One row per record. 23 columns.
      REVIEW rows appear TWICE — once as "REVIEW — KEEP?" and once as
      "REVIEW — REMOVE?" so you can pick which action to take per device.

    FILE 2 — BulkRemove TXT:
      Get-GroupDeviceIntuneReport_[timestamp]_BulkRemove.txt
      Contains Azure AD Object IDs of definitive REMOVE FROM GROUP entries.
      Upload directly to Entra portal → Group → Members → Bulk Remove.
      REVIEW rows are NOT included — you add those manually after reviewing
      the CSV.

    FILE 3 — Log File:
      Get-GroupDeviceIntuneReport_[timestamp].log
      Full timestamped run log — group info, every device processed,
      verdicts assigned, and final summary counts.

  Step 5 — Prints console summary:
    — Group name and ID
    — Total device members / unique hostnames
    — Verdict breakdown: UNIQUE ACTIVE / KEEP / DELETE / REVIEW / NOT FOUND
    — GroupAction breakdown: KEEP IN GROUP / REMOVE FROM GROUP / REVIEW
    — How-to instructions for using the BulkRemove TXT and reading the CSV

────────────────────────────────────────────────────────────────────────────────
  VERDICT DEFINITIONS
────────────────────────────────────────────────────────────────────────────────

  INTUNE ROWS:

    UNIQUE ACTIVE  — Elected authoritative Intune record for this hostname.
                     Newest enrollment date. Use this IntuneDeviceID for
                     policy assignment. Mark ★ in console output.

    KEEP           — Only one Intune record exists for this hostname.
                     No duplicate detected.

    DELETE         — Older duplicate Intune record. Use IntuneDevice-Delete.ps1
                     with the IntuneDeviceID to retire this record from Intune.

    REVIEW         — Could not determine which record is newer. Verify manually
                     in Intune before taking action.

  AZURE AD ROWS:

    KEEP (ACTIVE)  — Linked to the UNIQUE ACTIVE Intune record.
                     Last activity within 90 days. Keep in group.

    KEEP           — Only AAD object for this hostname and linked to Intune.

    DELETE         — NOT linked to any Intune record. Orphaned AAD object.
                     Safe to remove from group. AAD Object ID in BulkRemove TXT.

    REVIEW         — Ambiguous. Could be linked to a non-active Intune record,
                     last activity older than 90 days, or not linked to Intune
                     with no duplicates. Verify before acting.

    NOT FOUND      — Hostname not found in Intune or Azure AD at all. Check
                     spelling or verify device is still active.

────────────────────────────────────────────────────────────────────────────────
  GROUPACTION COLUMN
────────────────────────────────────────────────────────────────────────────────

    KEEP IN GROUP      — Clean, authoritative record. Leave in group.
    REMOVE FROM GROUP  — Stale or orphaned. AAD Object ID in BulkRemove TXT.
    REVIEW — KEEP?     — REVIEW row shown as possible keep option.
    REVIEW — REMOVE?   — REVIEW row shown as possible remove option.

  REVIEW rows appear TWICE in the CSV — once per option — so you can read
  both lines side by side and decide which action to take. They are NOT
  automatically added to the BulkRemove TXT. Add manually if needed.

────────────────────────────────────────────────────────────────────────────────
  CSV COLUMNS (23 columns)
────────────────────────────────────────────────────────────────────────────────

  VERDICT                   — See Verdict Definitions above
  VerdictReason             — Plain-text explanation of why this verdict was assigned
  GroupAction               — KEEP IN GROUP / REMOVE FROM GROUP / REVIEW — KEEP? / REVIEW — REMOVE?
  IsUniqueActiveIntuneEntry — YES / NO / N/A — Azure AD row
  Hostname                  — Device display name
  Source                    — "Intune" or "Azure AD"
  SerialNumber              — Serial number (Intune rows; extracted from physicalIds for AAD rows)
  IntuneDeviceID            — Intune managed device ID (Intune rows only)
  AADObjectID               — Azure AD directory object ID (Azure AD rows only)
  AADDeviceID               — Azure AD device ID (GUID linking Intune ↔ AAD)
  PrimaryUser               — Primary user UPN (Intune rows only)
  EnrolledDate              — Intune enrollment date (Intune rows only)
  RegisteredDate            — Azure AD registration date (Azure AD rows only)
  LastSync                  — Last Intune sync date (Intune rows only)
  LastActivity              — Approximate last sign-in date (Azure AD rows only)
  DaysSinceSync             — Days since last Intune sync (Intune rows only)
  ComplianceState           — Compliant / Non-compliant
  ManagementState           — Management state from Intune or Azure AD
  OS                        — Operating system and version
  LinkedToIntune            — Whether AAD object is linked to an Intune record
  LinkedAADObjectID         — AAD Object ID linked to this Intune record
  DuplicateCount_Intune     — Total Intune records found for this hostname
  DuplicateCount_AAD        — Total Azure AD objects found for this hostname

────────────────────────────────────────────────────────────────────────────────
  PREREQUISITES
────────────────────────────────────────────────────────────────────────────────

  - PowerShell 5.1 or later (no additional modules required)
  - An Azure AD App Registration with a Client Secret
  - Admin consent granted for required Graph API permissions (see below)
  - The Object ID of the target Azure AD / Entra ID group
  - Network access to:
      https://login.microsoftonline.com   (OAuth2 token endpoint)
      https://graph.microsoft.com         (Graph API — v1.0 and beta endpoints)

────────────────────────────────────────────────────────────────────────────────
  REQUIRED MICROSOFT GRAPH API PERMISSIONS
────────────────────────────────────────────────────────────────────────────────

  All permissions are APPLICATION type (not Delegated).
  Admin consent must be granted in the Azure portal.

  Permission                                   Reason
  ─────────────────────────────────────────── ──────────────────────────────────
  GroupMember.Read.All                         Read group members
  DeviceManagementManagedDevices.Read.All      Search Intune device records
  Device.Read.All                              Search Azure AD device objects

  NOTE: This script is READ-ONLY. It does not modify, delete, wipe, or remove
  any device, user, or group member. All cleanup actions must be performed
  manually using the generated BulkRemove TXT file or a separate script.

────────────────────────────────────────────────────────────────────────────────
  HOW TO RUN THE SCRIPT
────────────────────────────────────────────────────────────────────────────────

  Step 1 — Find your Azure AD Group Object ID:
              Azure Portal → Groups → [Your Group] → Overview → Object ID

  Step 2 — Open the script and fill in the CONFIGURATION region:

              $TenantID     = "your-tenant-id"
              $ClientID     = "your-client-id"
              $ClientSecret = "your-client-secret"
              $GroupID      = "your-group-object-id"

  Step 3 — (Optional) Set a custom output folder:

              $OutputFolder = "C:\Reports\GroupCleanup"
              Leave blank to save next to the script.

  Step 4 — Open PowerShell and run:

              .\Get-GroupDeviceIntuneReport.ps1

  Step 5 — Wait for completion. Progress shown per device on-screen.

  Step 6 — Review the CSV output. Three files will be created:
              — Full CSV report
              — BulkRemove TXT (if any REMOVE FROM GROUP entries found)
              — Log file

  Step 7 — To remove stale members from the group:
              Entra portal → Groups → [Your Group] → Members → Bulk Remove
              Upload the BulkRemove TXT file.
              For REVIEW rows — review the CSV and add Object IDs manually.

────────────────────────────────────────────────────────────────────────────────
  EXPECTED OUTPUT
────────────────────────────────────────────────────────────────────────────────

  CSV Report:
    Get-GroupDeviceIntuneReport_[timestamp].csv
    23 columns. One row per record. REVIEW rows appear twice.
    UTF-8 encoded. Ready for Excel or Power BI.

  BulkRemove TXT:
    Get-GroupDeviceIntuneReport_[timestamp]_BulkRemove.txt
    One Azure AD Object ID per line — definitive REMOVE FROM GROUP only.
    Upload directly to Entra portal Bulk Remove.
    Not created if no REMOVE FROM GROUP entries found.

  Log File:
    Get-GroupDeviceIntuneReport_[timestamp].log
    Full timestamped run transcript — group info, per-device results,
    verdict assignments, and final summary.

────────────────────────────────────────────────────────────────────────────────
  IMPORTANT NOTES
────────────────────────────────────────────────────────────────────────────────

  - READ-ONLY script. No changes made to the group, devices, or any records.
    All cleanup must be performed manually using the generated output files.

  - Uses both /beta (Intune managedDevices) and v1.0 (group members, AAD
    devices) Graph API endpoints.

  - $filter and $select cannot be combined on the Intune managedDevices
    endpoint — this causes HTTP 400. The script intentionally omits $select
    when filtering by hostname.

  - A 300ms delay is applied between hostname lookups to respect Graph API
    throttling limits and avoid HTTP 429 responses.

  - REVIEW rows appear TWICE in the CSV — this is intentional. One row shows
    the "KEEP?" option and the other shows the "REMOVE?" option so you can
    make an informed decision per device.

  - REVIEW rows are deliberately excluded from the BulkRemove TXT. Add them
    manually only after reviewing the CSV and confirming the action.

  - The Unique Active election is based on enrolledDateTime (primary) and
    lastSyncDateTime (fallback). If both dates are identical or missing,
    the first record in the result set is elected and the row is marked REVIEW.

  - AAD object serial numbers are extracted from the physicalIds array
    ([SerialNumber] prefix). If not present, [OrderID] is used as fallback.

  - The script handles both Security Groups and Dynamic Device Groups.
    For Dynamic Device Groups the group type is detected and logged.

────────────────────────────────────────────────────────────────────────────────
  TROUBLESHOOTING TIPS
────────────────────────────────────────────────────────────────────────────────

  PROBLEM          : "GroupID is not set" error
  SOLUTION         : Set $GroupID in the CONFIGURATION region of the script.
                     Copy the Object ID from Azure Portal → Groups → Overview.

  PROBLEM          : "No device members found in group" error
  SOLUTION         : Verify the Group ID is correct. Confirm the group contains
                     device members. Dynamic groups may take time to populate.

  PROBLEM          : Authentication fails
  SOLUTION         : Verify TenantID, ClientID, ClientSecret. Check App
                     Registration is active and admin consent is granted.

  PROBLEM          : Many rows showing NOT FOUND
  SOLUTION         : Device was removed from Intune/AAD but still in the group.
                     These are safe to remove using the BulkRemove TXT or
                     manually via Entra portal.

  PROBLEM          : Many REVIEW rows in output
  SOLUTION         : REVIEW means the script cannot determine the status with
                     confidence. Open Entra portal and Intune for those devices
                     and check enrollment dates and last sync times manually.

  PROBLEM          : BulkRemove TXT not created
  SOLUTION         : No definitive REMOVE FROM GROUP entries were found. The
                     group may already be clean, or all removable entries were
                     flagged as REVIEW (requiring manual decision).

  PROBLEM          : HTTP 429 Too Many Requests
  SOLUTION         : The script includes a 300ms delay per hostname. For very
                     large groups, increase the Start-Sleep value in the script
                     (e.g. change 300 to 600 milliseconds).

  PROBLEM          : Script is slow on large groups
  SOLUTION         : Each hostname requires 2 Graph searches (Intune + AAD).
                     A group with 500 unique hostnames may take 15-30 minutes.
                     This is expected. Do not reduce the 300ms delay.

  PROBLEM          : Duplicate rows in CSV for same device
  SOLUTION         : Expected for REVIEW rows — they appear twice intentionally.
                     For non-REVIEW duplicates, check DuplicateCount_Intune
                     and DuplicateCount_AAD columns for that hostname.

  PROBLEM          : IsUniqueActiveIntuneEntry = YES on multiple rows
  SOLUTION         : Only one Intune row per hostname will have YES. If you see
                     two YES rows for the same hostname, check for hostnames
                     that are shared across multiple physical devices.

================================================================================
  GUMROAD LISTING
================================================================================

────────────────────────────────────────────────────────────────────────────────
  GUMROAD LISTING TITLE
────────────────────────────────────────────────────────────────────────────────

  Intune Group Device Cleanup Report – Duplicate Detection & Bulk Remove Export (PowerShell)

────────────────────────────────────────────────────────────────────────────────
  GUMROAD PRODUCT DESCRIPTION
────────────────────────────────────────────────────────────────────────────────

  Is your Azure AD device group full of stale records, duplicate enrollments,
  and orphaned objects? This PowerShell script audits your group in minutes —
  tells you exactly what to keep and what to remove, and hands you a Bulk
  Remove file ready to upload straight into the Entra portal.

  Point it at any Azure AD Security Group or Dynamic Device Group. It searches
  Intune and Azure AD for every device in the group, cross-references all
  records, elects the single authoritative Intune entry per device, and exports
  a verdict-tagged CSV with 23 columns — plus a Bulk Remove TXT file with the
  Object IDs of everything that should go.

  No modules to install. READ-ONLY — nothing is changed until you upload the
  Bulk Remove file yourself. Works on PowerShell 5.1.

  ✅ What you get:
  — Ready-to-run PowerShell script (Get-GroupDeviceIntuneReport.ps1)
  — Full README with setup guide, verdict definitions, and troubleshooting
  — Full CSV report: 23 columns, VERDICT, GroupAction, cross-reference data
  — BulkRemove TXT: Object IDs ready for Entra portal Bulk Remove upload
  — REVIEW rows shown twice in CSV (KEEP? and REMOVE?) for human review
  — Unique Active election per hostname (newest enrollment wins)
  — Orphaned AAD objects flagged and included in Bulk Remove automatically
  — Timestamped log file for full audit trail
  — Console summary: verdict counts, GroupAction counts, next-step instructions

────────────────────────────────────────────────────────────────────────────────
  KEY FEATURES
────────────────────────────────────────────────────────────────────────────────

  - Detects stale, duplicate, and orphaned device records in any Azure AD group
  - Supports Security Groups, Microsoft 365 Groups, Dynamic Device Groups
  - Searches BOTH Intune and Azure AD per hostname — full cross-reference
  - Elects ONE Unique Active Intune record per device (newest enrolled date)
  - VERDICT per row: UNIQUE ACTIVE / KEEP / KEEP (ACTIVE) / DELETE / REVIEW
  - GroupAction per row: KEEP IN GROUP / REMOVE FROM GROUP / REVIEW
  - REVIEW rows appear twice in CSV — one KEEP? and one REMOVE? option
  - BulkRemove TXT — definitive removes only, upload direct to Entra portal
  - REVIEW rows excluded from Bulk Remove — human decision required
  - NOT FOUND detection — hostnames in group missing from Intune and AAD
  - Serial number extracted from AAD physicalIds array automatically
  - 300ms throttle between lookups — Graph API rate limit safe
  - 23-column CSV with full duplicate counts, linked record IDs, days since sync
  - READ-ONLY — no changes made until you act on the output files
  - No additional modules required — PowerShell 5.1 compatible

────────────────────────────────────────────────────────────────────────────────
  WHO THIS SCRIPT IS FOR
────────────────────────────────────────────────────────────────────────────────

  - IT Administrators cleaning up stale device records in Intune groups
  - Engineers managing Autopilot or MDM enrollment group hygiene
  - Security teams auditing group membership accuracy for policy compliance
  - Compliance teams ensuring policy applies to the correct device objects
  - Helpdesk teams investigating duplicate Intune records for a device
  - Consultants performing Intune tenant health checks for clients
  - Anyone who has ever seen 2-3 records for the same device in a group
    and needed to know which one to keep and which ones to remove

────────────────────────────────────────────────────────────────────────────────
  SUGGESTED TAGS / KEYWORDS
────────────────────────────────────────────────────────────────────────────────

  Intune, Microsoft Intune, PowerShell, Graph API, Azure AD Group,
  Entra ID, Device Cleanup, Duplicate Device, Stale Device, Bulk Remove,
  Group Hygiene, Orphaned Device, Device Audit, Intune Duplicate,
  Dynamic Device Group, Security Group, Enrollment Cleanup, MDM Cleanup,
  IT Admin, Microsoft Endpoint Manager, PowerShell Script, IT Tools,
  Intune Cleanup, AAD Device, Device Report

────────────────────────────────────────────────────────────────────────────────
  BUYER INSTRUCTIONS
────────────────────────────────────────────────────────────────────────────────

  After purchase you will receive a ZIP file containing:
    — Get-GroupDeviceIntuneReport.ps1
    — README.txt (this file)

  Quick start:
    1. Create an Azure AD App Registration with a Client Secret.
    2. Grant the three Graph API permissions listed in this README.
    3. Grant admin consent in the Azure portal.
    4. Find your Group Object ID:
         Azure Portal → Groups → [Your Group] → Overview → Object ID
    5. Open the script and fill in TenantID, ClientID, ClientSecret, GroupID.
    6. Run: .\Get-GroupDeviceIntuneReport.ps1
    7. Open the CSV — review VERDICT and GroupAction columns.
    8. Upload the BulkRemove TXT to Entra portal → Group → Members → Bulk Remove.
    9. For REVIEW rows — check the CSV and add Object IDs manually if removing.

  Nothing is changed by running the script. All cleanup is in your hands.

────────────────────────────────────────────────────────────────────────────────
  COMMON QUESTIONS / FAQ
────────────────────────────────────────────────────────────────────────────────

  Q: Does this script remove anything from the group automatically?
  A: No. It is 100% read-only. The BulkRemove TXT file is generated for you
     to upload manually. Nothing is changed until you take action yourself.

  Q: Do I need PowerShell 7?
  A: No. The script runs on PowerShell 5.1 and later.

  Q: Do I need to install any modules?
  A: No. The script uses only built-in PowerShell cmdlets and direct REST API
     calls. No module installation required.

  Q: Why do REVIEW rows appear twice in the CSV?
  A: REVIEW means the script cannot make a confident decision. Two rows are
     written — one labelled "REVIEW — KEEP?" and one labelled "REVIEW — REMOVE?"
     — so you can see both options side by side and choose what to do.

  Q: Why are REVIEW rows not in the BulkRemove TXT?
  A: Because the script is not confident enough to auto-remove them. You must
     review those rows in the CSV and add the Object IDs to the Bulk Remove
     manually if you decide to remove them.

  Q: What is "Unique Active" and why does it matter?
  A: When a device has been re-enrolled or re-imaged, multiple Intune records
     may exist for the same hostname. Only one should be used for policy
     assignment and compliance. The Unique Active record is the one with the
     newest enrollment date — it is the authoritative current record.

  Q: Can I run this on multiple groups?
  A: One group per run. Each run produces its own timestamped output files so
     they never overwrite each other. Run the script once per group.

  Q: What happens to devices in the group that are not in Intune or Azure AD?
  A: They are flagged as NOT FOUND in the CSV with a REVIEW — KEEP? GroupAction.
     These are typically devices that were deleted from Intune/AAD but whose
     object ID is still in the static group.

  Q: Does it work for Dynamic Device Groups?
  A: Yes. The script detects the group type and logs it. Dynamic groups are
     supported. Note that for Dynamic groups, the group membership is managed
     by rules — removing a device object from the group may cause it to
     re-join if the rule still matches.

  Q: How is this different from Get-IntuneGroupDeviceSummary.ps1?
  A: Get-IntuneGroupDeviceSummary.ps1 exports a device inventory for a group —
     what devices are in the group and what their Intune details are.
     Get-GroupDeviceIntuneReport.ps1 is a CLEANUP tool — it finds duplicates
     and orphans, elects the authoritative record per device, and generates
     the Bulk Remove file. Use both together for full group visibility and
     hygiene.

================================================================================
  END OF README
================================================================================
