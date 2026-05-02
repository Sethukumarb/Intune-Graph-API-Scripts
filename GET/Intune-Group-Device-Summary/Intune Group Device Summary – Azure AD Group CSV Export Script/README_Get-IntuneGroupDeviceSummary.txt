================================================================================
  README — Get-IntuneGroupDeviceSummary.ps1
  Intune Group Device Summary – Azure AD Group CSV Export
  Author: Sethu Kumar B  |  Version: 1.0
================================================================================

────────────────────────────────────────────────────────────────────────────────
  SCRIPT NAME
────────────────────────────────────────────────────────────────────────────────

  Get-IntuneGroupDeviceSummary.ps1

────────────────────────────────────────────────────────────────────────────────
  FOLDER NAME
────────────────────────────────────────────────────────────────────────────────

  Intune-Group-Device-Summary

────────────────────────────────────────────────────────────────────────────────
  PURPOSE
────────────────────────────────────────────────────────────────────────────────

  Exports a detailed device report for all devices in a specified Azure AD /
  Entra ID group. Provide one Group Object ID, and the script fetches every
  device member, matches it to its Intune record, and exports a single CSV
  with 35 columns of device detail — including devices that are in the group
  but not enrolled in Intune, clearly flagged in the output.

────────────────────────────────────────────────────────────────────────────────
  WHAT THE SCRIPT DOES
────────────────────────────────────────────────────────────────────────────────

  Step 1 — Fetches all device members of the Azure AD group:
             GET /beta/groups/{groupId}/members/microsoft.graph.device
           Returns only device-type members. User members are automatically
           skipped server-side — no manual filtering required.
           Handles pagination via @odata.nextLink automatically.

  Step 2 — For each Azure AD device member, finds the matching Intune managed
           device record using the Azure AD Device ID:
             GET /beta/deviceManagement/managedDevices
                 ?$filter=azureADDeviceId eq '{aadDeviceId}'
           Note: $select is intentionally omitted — combining $filter and
           $select on the Intune managedDevices endpoint causes HTTP 400.

  Step 3 — Fetches the full $entity record per Intune device:
             GET /beta/deviceManagement/managedDevices/{id}
           Required because usersLoggedOn is excluded from list responses
           and is only available on the individual entity endpoint.

  Step 4 — Resolves the Last Logon userId GUID to a UPN:
             GET /beta/users/{userId}?$select=userPrincipalName

  Special cases handled:
    — Device in group but NOT enrolled in Intune:
      Included in CSV as a placeholder row with ManagedDeviceName set to
      "NOT ENROLLED IN INTUNE". Azure AD Device ID is preserved.
    — Duplicate Intune records (same AAD Device ID maps to multiple Intune
      records): All records are exported and logged as duplicates.
    — User members in the group: Skipped automatically at the API level.
    — Missing Azure AD Device ID on a member: Logged and skipped with a
      NOT ENROLLED placeholder row.

  CSV columns exported (35 columns):

    IDENTITY   : DeviceName, ManagedDeviceName, FQDN, SerialNumber,
                 Manufacturer, Model, ChassisType, BIOSVersion, WiFiMacAddress

    OS         : OperatingSystem, OSVersion, OSFriendlyName, SKUFamily

    USERS      : PrimaryUserDisplayName, PrimaryUserEmail,
                 PrimaryUserEmailAddress, EnrolledByEmail,
                 LastLogonEmail, LastLogonDateTime

    ENROLLMENT : EnrolledDateTime, EnrollmentType, EnrollmentProfileName,
                 JoinType, AutopilotEnrolled, AzureADRegistered, AADRegistered

    MANAGEMENT : ManagementState, ManagementAgent, ComplianceState,
                 OwnerType, DeviceRegistrationState, LastSyncDateTime

    ENTRA ID   : AzureADDeviceId, AzureActiveDirectoryDeviceId

    SECURITY   : IsEncrypted

  Output files saved to the script folder (or custom $OutputFolder):
    — IntuneGroupDeviceSummary_<GroupName>_<timestamp>.csv
    — <GroupName>_<timestamp>.log

  Final console summary shows:
    — Group Name and Group ID
    — Total device members in group
    — Total records exported
    — Count of devices not enrolled in Intune
    — Count of duplicate Intune records detected

────────────────────────────────────────────────────────────────────────────────
  PREREQUISITES
────────────────────────────────────────────────────────────────────────────────

  - PowerShell 5.1 or later (no additional modules required)
  - An Azure AD App Registration with a Client Secret
  - Admin consent granted for required Graph API permissions (see below)
  - The Object ID of the target Azure AD / Entra ID group
  - Network access to:
      https://login.microsoftonline.com   (OAuth2 token endpoint)
      https://graph.microsoft.com         (Graph API — beta endpoint)

────────────────────────────────────────────────────────────────────────────────
  REQUIRED MICROSOFT GRAPH API PERMISSIONS
────────────────────────────────────────────────────────────────────────────────

  All permissions are APPLICATION type (not Delegated).
  Admin consent must be granted in the Azure portal.

  Permission                                   Reason
  ─────────────────────────────────────────── ──────────────────────────────────
  DeviceManagementManagedDevices.Read.All      Read Intune device records
  User.Read.All                                Resolve Last Logon userId to UPN
  GroupMember.Read.All                         Read group membership
  Device.Read.All                              Read Azure AD device objects

  NOTE: This script is READ-ONLY. It does not modify, wipe, or take any action
  on devices or groups. A read-only App Registration is strongly recommended.

────────────────────────────────────────────────────────────────────────────────
  HOW TO RUN THE SCRIPT
────────────────────────────────────────────────────────────────────────────────

  Step 1 — Find your Azure AD Group Object ID:
              Azure Portal → Groups → [Your Group] → Overview → Object ID
              Supports: Security Groups, Microsoft 365 Groups,
                        Dynamic Device Groups

  Step 2 — Open the script and fill in the CONFIGURATION region at the top:

              $TenantID     = "your-tenant-id"
              $ClientID     = "your-client-id"
              $ClientSecret = "your-client-secret"
              $GroupId      = "your-group-object-id"

  Step 3 — (Optional) Set a custom output folder:

              $OutputFolder = "C:\Reports\IntuneGroups"
              Leave as $PSScriptRoot to save next to the script.

  Step 4 — Open PowerShell and run:

              .\Get-IntuneGroupDeviceSummary.ps1

  Step 5 — Wait for completion. Progress is shown on-screen per device.
            Find the CSV and log file in the output folder.

────────────────────────────────────────────────────────────────────────────────
  EXPECTED OUTPUT
────────────────────────────────────────────────────────────────────────────────

  CSV Report:
    IntuneGroupDeviceSummary_<GroupName>_<timestamp>.csv
    One row per device. 35 columns. UTF-8 encoded.
    Devices not enrolled in Intune appear as placeholder rows with
    ManagedDeviceName = "NOT ENROLLED IN INTUNE".
    Ready to open in Excel or import into Power BI.

  Log File:
    <GroupName>_<timestamp>.log
    Timestamped record of every step — group name, each device processed,
    Intune matches found, UPN resolutions, warnings, and errors.
    Saved in the script folder ($PSScriptRoot) regardless of $OutputFolder.

  Console Summary (printed at end of run):
    — Group Name and Group ID
    — Total device members found in group
    — Total records exported to CSV
    — Devices not enrolled in Intune (with device names listed)
    — Duplicate Intune records detected

────────────────────────────────────────────────────────────────────────────────
  IMPORTANT NOTES
────────────────────────────────────────────────────────────────────────────────

  - Uses the /beta Graph API endpoint throughout. Beta endpoints may change
    without notice. Microsoft does not guarantee beta endpoint stability
    for production use.

  - $filter and $select cannot be combined on the Intune managedDevices
    collection endpoint — this causes HTTP 400. The script intentionally
    omits $select when filtering by azureADDeviceId.

  - The full $entity fetch (Step 3) is required per device because
    usersLoggedOn is not returned by the list endpoint. This means the
    script makes 2-3 Graph API calls per device member.

  - A 200ms delay is applied between device lookups to respect Graph API
    throttling limits and avoid HTTP 429 responses.

  - For large groups (500+ devices), run time will increase proportionally
    due to the per-device entity fetch and UPN resolution calls.

  - Devices in the group that are not enrolled in Intune are NOT silently
    skipped — they appear in the CSV as placeholder rows and are listed
    separately in the console summary and log file.

  - The group must contain device objects. If the group contains only user
    objects, zero device members will be found and the script will exit.

  - Supports all platforms — Windows, macOS, iOS, Android. No OS filter.

  - OSFriendlyName is resolved for Windows (e.g. "Win11 23H2") and
    macOS (e.g. "macOS 15 Sequoia"). Other platforms show raw OS version.

────────────────────────────────────────────────────────────────────────────────
  TROUBLESHOOTING TIPS
────────────────────────────────────────────────────────────────────────────────

  PROBLEM          : "GroupId is not configured" error
  SOLUTION         : Set $GroupId in the CONFIGURATION region of the script.
                     Copy the Object ID from Azure Portal → Groups → Overview.

  PROBLEM          : "No device members found in group" warning
  SOLUTION         : Verify the Group ID is correct. Confirm the group contains
                     device members (not only user members). Dynamic device
                     groups may take time to populate after rule changes.

  PROBLEM          : Authentication fails / token not acquired
  SOLUTION         : Verify TenantID, ClientID, ClientSecret are correct.
                     Check the App Registration is not expired or disabled.

  PROBLEM          : HTTP 400 on managedDevices query
  SOLUTION         : Already handled in script. Do not add $select when using
                     $filter on the managedDevices endpoint.

  PROBLEM          : HTTP 429 Too Many Requests (throttling)
  SOLUTION         : The script includes a 200ms delay per device. For very
                     large groups, increase the Start-Sleep value in the script
                     (e.g. change 200 to 500 milliseconds).

  PROBLEM          : Many rows show "NOT ENROLLED IN INTUNE"
  SOLUTION         : Those devices are in the Azure AD group but not enrolled
                     in Intune MDM. This is expected for Azure AD registered
                     (BYOD) devices or devices pending enrollment.

  PROBLEM          : LastLogonEmail is blank for some devices
  SOLUTION         : The device may have no usersLoggedOn data in Intune, or
                     the userId GUID could not be resolved to a UPN. Check the
                     log file for UPN resolve warnings on those devices.

  PROBLEM          : Duplicate rows in CSV for same device
  SOLUTION         : The device has multiple Intune records with the same
                     Azure AD Device ID. This is logged as a DUPLICATE warning.
                     Check Intune for stale or duplicate device records and
                     retire the older entry.

  PROBLEM          : Script runs slowly on large groups
  SOLUTION         : Each device requires 2-3 Graph API calls. A group with
                     500 devices may take 10-20 minutes. This is expected.
                     Do not reduce the 200ms delay below 100ms — risk of 429.

  PROBLEM          : OSFriendlyName shows "Unknown Build (XXXXX)"
  SOLUTION         : The OS build number is not in the mapping table. This may
                     be a newer Windows Insider or preview build. The raw
                     OSVersion column still contains the full version string.

================================================================================
  GUMROAD LISTING
================================================================================

────────────────────────────────────────────────────────────────────────────────
  GUMROAD LISTING TITLE
────────────────────────────────────────────────────────────────────────────────

  Intune Group Device Summary – Azure AD Group CSV Export Script (PowerShell)

────────────────────────────────────────────────────────────────────────────────
  GUMROAD PRODUCT DESCRIPTION
────────────────────────────────────────────────────────────────────────────────

  Need a device report scoped to a specific Azure AD group? This PowerShell
  script takes one Group Object ID and exports a complete device inventory for
  every device in that group — enrolled in Intune or not.

  Point it at any Security Group, Microsoft 365 Group, or Dynamic Device Group.
  It fetches every device member, matches it to Intune, pulls the full device
  record, and exports a clean CSV with 35 columns per device.

  Devices in the group but not enrolled in Intune are clearly flagged —
  not silently dropped — so you get a true picture of group membership vs
  Intune coverage.

  No modules to install. Works on PowerShell 5.1. No PS 7 required.

  ✅ What you get:
  — Ready-to-run PowerShell script (Get-IntuneGroupDeviceSummary.ps1)
  — Full README with setup instructions, permissions guide, and troubleshooting
  — CSV with 35 columns: identity, OS, users, enrollment, management, security
  — NOT ENROLLED placeholder rows for non-Intune devices in the group
  — Duplicate Intune record detection and logging
  — Last Logon User resolved from GUID to UPN automatically
  — Friendly OS name mapping (Windows versions + macOS names)
  — Named log file per run for full audit trail
  — Console summary: member count, exported count, not-enrolled count

────────────────────────────────────────────────────────────────────────────────
  KEY FEATURES
────────────────────────────────────────────────────────────────────────────────

  - Scoped to one Azure AD group — any group type supported
  - Works with Security Groups, Microsoft 365 Groups, Dynamic Device Groups
  - Supports all platforms — Windows, macOS, iOS, Android (no OS filter)
  - User members in the group are automatically skipped at the API level
  - Devices not enrolled in Intune are flagged, not silently dropped
  - Full $entity fetch per device — includes Last Logon User data
  - Last Logon User GUID resolved to UPN automatically
  - Friendly OS name: Windows version names + macOS release names
  - Duplicate Intune record detection with warning logging
  - 200ms throttle between device calls to avoid Graph API rate limits
  - Named CSV and log file per run (group name + timestamp in filename)
  - No additional modules required — PowerShell 5.1 compatible
  - Uses /beta endpoint for maximum field coverage

────────────────────────────────────────────────────────────────────────────────
  WHO THIS SCRIPT IS FOR
────────────────────────────────────────────────────────────────────────────────

  - IT Administrators managing Intune with Azure AD group-based policies
  - Security teams auditing device compliance for a specific department or role
  - Helpdesk teams reporting on devices in a specific group
  - Engineers checking Intune enrollment coverage for a device group
  - Compliance teams needing group-scoped device reports for audits
  - Consultants delivering device inventory reports scoped to client groups
  - Anyone who needs to answer "what devices are in this group and what is
    their Intune status?" — without clicking through the portal

────────────────────────────────────────────────────────────────────────────────
  SUGGESTED TAGS / KEYWORDS
────────────────────────────────────────────────────────────────────────────────

  Intune, Microsoft Intune, PowerShell, Graph API, Azure AD Group,
  Entra ID Group, Group Device Report, Device Inventory, Intune Group Export,
  Dynamic Device Group, Security Group, IT Admin, Device Audit, CSV Export,
  Microsoft Endpoint Manager, Compliance Report, Device Enrollment,
  Not Enrolled, PowerShell Script, IT Tools, Group Membership Report

────────────────────────────────────────────────────────────────────────────────
  BUYER INSTRUCTIONS
────────────────────────────────────────────────────────────────────────────────

  After purchase you will receive a ZIP file containing:
    — Get-IntuneGroupDeviceSummary.ps1
    — README.txt (this file)

  Quick start:
    1. Create an Azure AD App Registration with a Client Secret.
    2. Grant the four Graph API permissions listed in this README.
    3. Grant admin consent in the Azure portal.
    4. Find your Group Object ID:
         Azure Portal → Groups → [Your Group] → Overview → Object ID
    5. Open the script and fill in TenantID, ClientID, ClientSecret, GroupId.
    6. Run: .\Get-IntuneGroupDeviceSummary.ps1
    7. Find the CSV and log file in the same folder as the script.

  Need help? The README includes a full permissions guide and step-by-step
  troubleshooting for every common issue.

────────────────────────────────────────────────────────────────────────────────
  COMMON QUESTIONS / FAQ
────────────────────────────────────────────────────────────────────────────────

  Q: Does this script make any changes to my devices or groups?
  A: No. It is 100% read-only. It only reads data — it does not modify, wipe,
     retire, or change any device, user, or group.

  Q: Do I need PowerShell 7?
  A: No. The script runs on PowerShell 5.1 and later.

  Q: Do I need to install any modules?
  A: No. The script uses only built-in PowerShell cmdlets and direct REST API
     calls. No module installation required.

  Q: What group types are supported?
  A: Security Groups, Microsoft 365 Groups, and Dynamic Device Groups.
     The group must contain device objects (not only users).

  Q: What happens to devices in the group that are not enrolled in Intune?
  A: They appear in the CSV as placeholder rows with ManagedDeviceName set to
     "NOT ENROLLED IN INTUNE". They are also listed separately in the console
     summary and log file so nothing is silently missed.

  Q: Can I run this for multiple groups?
  A: The script processes one group per run. To report on multiple groups,
     run the script once per group — each run produces its own named CSV
     and log file, so outputs do not overwrite each other.

  Q: Does it work for macOS, iOS, and Android devices too?
  A: Yes. There is no OS filter — all platforms in the group are exported.
     OSFriendlyName is resolved for Windows and macOS. Other platforms
     show the raw OS version string.

  Q: How long does it take for a large group?
  A: Each device requires 2-3 Graph API calls. A group of 500 devices may
     take 10-20 minutes. A 200ms delay is built in between calls to avoid
     throttling — do not remove it.

  Q: Why does the script use the /beta endpoint instead of v1.0?
  A: The beta endpoint returns more fields, including usersLoggedOn,
     autopilotEnrolled, joinType, and enrollmentProfileName, which are not
     available on the v1.0 managedDevices endpoint.

  Q: How is this different from Get-WindowsDeviceInventory.ps1?
  A: Get-WindowsDeviceInventory.ps1 exports ALL Windows devices fleet-wide.
     Get-IntuneGroupDeviceSummary.ps1 is scoped to one Azure AD group,
     supports all platforms, and flags devices not enrolled in Intune.
     They serve different reporting needs and complement each other.

  Q: How is this different from Get-UserDevices.ps1?
  A: Get-UserDevices.ps1 looks up devices per user from an email list.
     Get-IntuneGroupDeviceSummary.ps1 looks up all device members of a
     specific Azure AD group — useful for department, role, or policy groups.

================================================================================
  END OF README
================================================================================
