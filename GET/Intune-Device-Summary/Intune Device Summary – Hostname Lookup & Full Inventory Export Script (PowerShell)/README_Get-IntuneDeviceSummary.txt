================================================================================
  README — Get-IntuneDeviceSummary.ps1
  Intune Device Summary – Hostname Lookup & Full Inventory Export
  Author: Sethu Kumar B  |  Version: 1.2
================================================================================

────────────────────────────────────────────────────────────────────────────────
  SCRIPT NAME
────────────────────────────────────────────────────────────────────────────────

  Get-IntuneDeviceSummary.ps1

────────────────────────────────────────────────────────────────────────────────
  FOLDER NAME
────────────────────────────────────────────────────────────────────────────────

  Intune-Device-Summary

────────────────────────────────────────────────────────────────────────────────
  PURPOSE
────────────────────────────────────────────────────────────────────────────────

  Exports a detailed Intune device summary in two modes — either for a specific
  list of hostnames from a text file, or for all devices in Intune with an
  optional OS filter. Uses the Graph API beta endpoint with full $entity fetches
  to guarantee every field is returned, including Last Logged On User.

────────────────────────────────────────────────────────────────────────────────
  WHAT THE SCRIPT DOES
────────────────────────────────────────────────────────────────────────────────

  The script runs in one of two modes, chosen at runtime:

  ── MODE 1: FILE MODE (Hostname Lookup) ──────────────────────────────────────

    Reads Hostnames.txt from the same folder as the script (one hostname per
    line). For each hostname:

    Step 1 — Searches Intune by deviceName:
               GET /beta/deviceManagement/managedDevices?$filter=deviceName eq '<name>'
             $select intentionally omitted — combining $filter and $select on
             the Intune managedDevices endpoint causes HTTP 400 Bad Request.

    Step 2 — Fetches the full $entity record per matched device:
               GET /beta/deviceManagement/managedDevices/{id}
             Required because usersLoggedOn is excluded from list responses.
             This guarantees all 35 fields are populated.

    Step 3 — Resolves Last Logon userId GUID to UPN:
               GET /beta/users/{userId}?$select=userPrincipalName

    Special cases:
      — Hostname not found in Intune → placeholder row with ManagedDeviceName
        set to "NOT FOUND". Listed in console summary at end of run.
      — Multiple Intune records for same hostname (duplicate) → all records
        exported and DUPLICATE warning logged to console.
      — No OS filter in file mode — device returned regardless of platform.

  ── MODE 2: ALL MODE (Full Inventory) ────────────────────────────────────────

    Pulls all devices from Intune (paginated), applies client-side OS filter,
    then fetches full $entity per device.

    Step 1 — Pulls all managed devices (no $filter, no $select):
               GET /beta/deviceManagement/managedDevices?$top=100
             Paginated via @odata.nextLink until all records are retrieved.

    Step 2 — Applies OS filter client-side:
               Valid values: All, Windows, macOS, iOS, Android, Linux
               Default: Windows

    Step 3 — Fetches full $entity per device (same as File Mode Step 2).

    Step 4 — Resolves Last Logon userId GUID to UPN per device.

  ── Both Modes ───────────────────────────────────────────────────────────────

    Exports a single CSV file named:
      All_IntuneDeviceSummary_<OSLabel|ByHostname>_<timestamp>.csv

    35 columns per device row (see CSV Columns section below).

────────────────────────────────────────────────────────────────────────────────
  CSV COLUMNS (35 columns)
────────────────────────────────────────────────────────────────────────────────

  IDENTITY:
    DeviceName                   — Intune device name
    ManagedDeviceName            — Managed device name (or "NOT FOUND")
    FQDN                         — Fully qualified domain name
    SerialNumber                 — Device serial number
    Manufacturer                 — Hardware manufacturer
    Model                        — Hardware model
    ChassisType                  — Chassis type (Desktop, Laptop, etc.)
    BIOSVersion                  — BIOS/UEFI version string
    WiFiMacAddress               — Wi-Fi MAC address

  OS:
    OperatingSystem              — OS platform (Windows, macOS, iOS, etc.)
    OSVersion                    — Raw OS version string
    OSFriendlyName               — Human-readable OS name (e.g. "Win11 23H2",
                                   "macOS 15 Sequoia")
    SKUFamily                    — Windows SKU family

  USERS:
    PrimaryUserDisplayName       — Primary user display name
    PrimaryUserEmail             — Primary user UPN
    PrimaryUserEmailAddress      — Primary user email address
    EnrolledByEmail              — UPN of user who enrolled the device
    LastLogonEmail               — UPN of last logged on user (resolved from GUID)
    LastLogonDateTime            — Timestamp of last logon

  ENROLLMENT:
    EnrolledDateTime             — Date device was enrolled in Intune
    EnrollmentType               — Enrollment type (e.g. windowsAutoEnrollment)
    EnrollmentProfileName        — Enrollment profile name if applicable
    JoinType                     — Azure AD join type
    AutopilotEnrolled            — Whether device is Autopilot enrolled
    AzureADRegistered            — Azure AD registered flag
    AADRegistered                — AAD registered flag

  MANAGEMENT:
    ManagementState              — Intune management state
    ManagementAgent              — Management agent type
    ComplianceState              — Compliant / Non-compliant / Unknown
    OwnerType                    — Company or Personal
    DeviceRegistrationState      — Device registration state
    LastSyncDateTime             — Last Intune sync timestamp

  ENTRA ID:
    AzureADDeviceId              — Azure AD Device ID (GUID)
    AzureActiveDirectoryDeviceId — Azure Active Directory Device ID

  SECURITY:
    IsEncrypted                  — Whether device is encrypted

────────────────────────────────────────────────────────────────────────────────
  PREREQUISITES
────────────────────────────────────────────────────────────────────────────────

  - PowerShell 5.1 or later (no additional modules required)
  - An Azure AD App Registration with a Client Secret
  - Admin consent granted for required Graph API permissions (see below)
  - For File Mode: a Hostnames.txt file in the same folder as the script
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
  DeviceManagementManagedDevices.Read.All      Read Intune managed device records
  User.Read.All                                Resolve Last Logon userId to UPN

  NOTE: This script is READ-ONLY. It does not modify, wipe, or take any action
  on devices. A read-only App Registration is strongly recommended.

────────────────────────────────────────────────────────────────────────────────
  HOW TO RUN THE SCRIPT
────────────────────────────────────────────────────────────────────────────────

  Step 1 — Open the script and fill in the CONFIGURATION region:

              $TenantID     = "your-tenant-id"
              $ClientID     = "your-client-id"
              $ClientSecret = "your-client-secret"

  Step 2 — (Optional) Configure defaults in the CONFIGURATION region:

              $InputFile    = path to Hostnames.txt (default: script folder)
              $OSFilter     = "Windows"  (All / Windows / macOS / iOS /
                                          Android / Linux)
              $OutputFolder = path for CSV output (default: script folder)

  Step 3 — For File Mode: create Hostnames.txt in the same folder as the
            script. One hostname per line. Example:

              DESKTOP-ABC123
              LAPTOP-XYZ789
              WS-FINANCE-01

  Step 4 — Open PowerShell and run:

              .\Get-IntuneDeviceSummary.ps1

  Step 5 — If Hostnames.txt exists in the script folder, File Mode starts
            automatically. Otherwise the script prompts:

              [1] Load hostnames from a .txt file
              [2] Pull ALL devices from Intune

            Enter 1 or 2 and follow the on-screen prompts.

  Step 6 — Find the CSV in the output folder when complete.

  ── Runtime examples ─────────────────────────────────────────────────────────

    Auto File Mode (Hostnames.txt present in script folder):
      .\Get-IntuneDeviceSummary.ps1

    Interactive File Mode (prompted):
      .\Get-IntuneDeviceSummary.ps1
      → Enter 1
      → Enter full path to .txt file

    All Devices — Windows only (default):
      .\Get-IntuneDeviceSummary.ps1
      → Enter 2

    All Devices — All platforms:
      Set $OSFilter = "All" in script, then run → Enter 2

────────────────────────────────────────────────────────────────────────────────
  EXPECTED OUTPUT
────────────────────────────────────────────────────────────────────────────────

  CSV file:
    All_IntuneDeviceSummary_ByHostname_[timestamp].csv   (File Mode)
    All_IntuneDeviceSummary_Windows_[timestamp].csv      (All Mode, Windows)
    All_IntuneDeviceSummary_All_[timestamp].csv          (All Mode, all OS)

    35 columns per row. UTF-8 encoded.
    NOT FOUND rows included for hostnames not in Intune (File Mode).
    Ready to open in Excel or import into Power BI.

  Console output:
    Live progress per device — match found, entity fetched, UPN resolved.
    DUPLICATE warnings for hostnames with multiple Intune records.
    NOT FOUND list printed at end of run (File Mode).
    Final summary: mode, total records, output path.

  NOTE: This script does not write a separate log file. All output is to the
  console only. To capture a log, run with PowerShell transcript:
    Start-Transcript -Path "C:\Logs\run.log"
    .\Get-IntuneDeviceSummary.ps1
    Stop-Transcript

────────────────────────────────────────────────────────────────────────────────
  IMPORTANT NOTES
────────────────────────────────────────────────────────────────────────────────

  - Uses the /beta Graph API endpoint. Beta endpoints may change without notice.
    Microsoft does not guarantee beta endpoint stability for production use.

  - $filter and $select cannot be combined on the Intune managedDevices
    collection endpoint — this causes HTTP 400. The script intentionally omits
    $select in all query URIs.

  - The full $entity fetch per device (Step 2) is required because usersLoggedOn
    is excluded from list endpoint responses regardless of $select usage.
    This means each device in File Mode requires 2 Graph API calls minimum
    (search + entity fetch), plus a 3rd call if Last Logon User is present.

  - In All Mode, $top=100 is used for pagination (not 1000) to stay within
    Graph API limits when combined with the per-device entity fetches that follow.

  - OS filter in All Mode is applied client-side (after all records are fetched),
    not server-side. All devices are downloaded first, then filtered locally.

  - File Mode applies no OS filter — devices are returned regardless of platform.
    If a hostname exists in both a Windows and macOS Intune record, both rows
    will be exported.

  - A 200ms delay is applied between device lookups in File Mode and a 100ms
    delay in All Mode to respect Graph API throttling limits.

  - Hostnames in Hostnames.txt are normalised to UPPERCASE and deduplicated
    before processing. Blank lines are ignored.

  - This script does not produce a separate log file. For scheduled or automated
    runs, wrap the script in Start-Transcript / Stop-Transcript.

────────────────────────────────────────────────────────────────────────────────
  TROUBLESHOOTING TIPS
────────────────────────────────────────────────────────────────────────────────

  PROBLEM          : Authentication fails / token not acquired
  SOLUTION         : Verify TenantID, ClientID, ClientSecret are correct.
                     Check App Registration is not expired or disabled.
                     Confirm admin consent is granted for both permissions.

  PROBLEM          : File not found error for Hostnames.txt
  SOLUTION         : Create Hostnames.txt in the same folder as the script.
                     Or choose mode 1 at the prompt and enter the full path
                     to your .txt file when asked.

  PROBLEM          : Hostname shows as NOT FOUND in CSV
  SOLUTION         : Confirm the hostname exists in Intune. Check spelling —
                     hostname matching is case-insensitive in Graph but the
                     value must exactly match the deviceName in Intune.
                     The device may have been retired or deleted from Intune.

  PROBLEM          : LastLogonEmail is blank for some devices
  SOLUTION         : The device may have no usersLoggedOn data in Intune, or
                     the userId GUID could not be resolved to a UPN.
                     Check that User.Read.All permission is granted.

  PROBLEM          : HTTP 400 Bad Request on device query
  SOLUTION         : Already handled in v1.1+. Do not add $select when using
                     $filter on the managedDevices endpoint.

  PROBLEM          : DUPLICATE warning for a hostname
  SOLUTION         : The hostname matches multiple Intune records. This happens
                     after re-enrollment, device wipe, or Autopilot reset.
                     All matching records are exported. Use EnrolledDateTime
                     to identify the current active record.

  PROBLEM          : All Mode takes a very long time
  SOLUTION         : All Mode fetches a full $entity per device. A tenant with
                     5,000 Windows devices may take 30-60 minutes. This is
                     expected. For large fleet exports, consider using
                     Get-WindowsDeviceInventory.ps1 which uses parallel
                     runspace processing for significantly faster throughput.

  PROBLEM          : OSFriendlyName shows "Unknown Build (XXXXX)"
  SOLUTION         : The build number is not in the mapping table. This may be
                     a newer Windows Insider or preview build. The raw OSVersion
                     column still contains the full version string.

  PROBLEM          : CSV opens garbled in Excel
  SOLUTION         : Open Excel → Data → From Text/CSV → select UTF-8 encoding.

================================================================================
  GUMROAD LISTING
================================================================================

────────────────────────────────────────────────────────────────────────────────
  GUMROAD LISTING TITLE
────────────────────────────────────────────────────────────────────────────────

  Intune Device Summary – Hostname Lookup & Full Inventory Export Script (PowerShell)

────────────────────────────────────────────────────────────────────────────────
  GUMROAD PRODUCT DESCRIPTION
────────────────────────────────────────────────────────────────────────────────

  Two scripts in one. Give it a list of hostnames and get a detailed Intune
  record for each device — or pull your entire Intune inventory in one run.
  Either way, you get a clean, complete CSV with 35 columns per device,
  including Last Logged On User resolved from GUID to UPN automatically.

  Built on the Graph API beta endpoint with full $entity fetches per device —
  the same data you see in Graph Explorer, exported to CSV in one command.

  No modules to install. Works on PowerShell 5.1. No PS 7 required.

  ✅ What you get:
  — Ready-to-run PowerShell script (Get-IntuneDeviceSummary.ps1)
  — Full README with setup guide, column definitions, and troubleshooting
  — File Mode: per-hostname lookup from a .txt file
  — All Mode: full Intune inventory with OS filter
  — 35-column CSV: identity, OS, users, enrollment, management, security
  — Friendly OS names: Windows version names + macOS release names
  — Last Logged On User resolved from GUID to UPN automatically
  — NOT FOUND placeholder rows — no hostname silently skipped
  — DUPLICATE detection with warning for re-enrolled devices
  — Interactive mode selector if no Hostnames.txt is present

────────────────────────────────────────────────────────────────────────────────
  KEY FEATURES
────────────────────────────────────────────────────────────────────────────────

  - Two input modes: hostname .txt file OR full Intune inventory pull
  - Full $entity fetch per device — all 35 fields guaranteed including
    usersLoggedOn (excluded from list endpoint responses)
  - Last Logged On User GUID resolved to UPN automatically
  - Friendly OS name mapping: Windows versions + macOS release names
  - NOT FOUND placeholder rows for hostnames not in Intune
  - DUPLICATE detection — multiple records per hostname all exported
  - OS filter for All Mode: All / Windows / macOS / iOS / Android / Linux
  - No OS filter in File Mode — returns device regardless of platform
  - Hostnames normalised to UPPERCASE and deduplicated before processing
  - Throttle delays: 200ms (File Mode), 100ms (All Mode)
  - No additional modules required — PowerShell 5.1 compatible
  - Uses /beta endpoint for maximum field coverage
  - Interactive prompt if Hostnames.txt not found — no hard failure

────────────────────────────────────────────────────────────────────────────────
  WHO THIS SCRIPT IS FOR
────────────────────────────────────────────────────────────────────────────────

  - IT Helpdesk staff looking up specific devices by hostname in Intune
  - IT Administrators exporting a full or filtered Intune device inventory
  - Security teams checking compliance, encryption, and user details per device
  - Engineers investigating re-enrollment or duplicate Intune records
  - Compliance teams needing detailed per-device records for audit
  - Consultants delivering targeted or full Intune device reports for clients
  - Anyone who needs to go from a hostname list to a complete Intune device
    report without clicking through the portal device by device

────────────────────────────────────────────────────────────────────────────────
  SUGGESTED TAGS / KEYWORDS
────────────────────────────────────────────────────────────────────────────────

  Intune, Microsoft Intune, PowerShell, Graph API, Device Summary,
  Hostname Lookup, Intune Export, Device Inventory, Managed Devices,
  IT Admin, Microsoft Endpoint Manager, Device Report, CSV Export,
  Last Logon User, Compliance Report, Encryption, Enrollment Details,
  Windows 10, Windows 11, macOS, Intune Beta API, PowerShell Script,
  IT Tools, Device Audit, Entity Fetch

────────────────────────────────────────────────────────────────────────────────
  BUYER INSTRUCTIONS
────────────────────────────────────────────────────────────────────────────────

  After purchase you will receive a ZIP file containing:
    — Get-IntuneDeviceSummary.ps1
    — README.txt (this file)

  Quick start:
    1. Create an Azure AD App Registration with a Client Secret.
    2. Grant the two Graph API permissions listed in this README.
    3. Grant admin consent in the Azure portal.
    4. Open the script and fill in TenantID, ClientID, ClientSecret.
    5. For File Mode: create Hostnames.txt next to the script with one
       hostname per line.
    6. Run: .\Get-IntuneDeviceSummary.ps1
    7. If Hostnames.txt is present, File Mode starts automatically.
       Otherwise, select mode 1 or 2 at the interactive prompt.
    8. Find the CSV in the same folder as the script.

────────────────────────────────────────────────────────────────────────────────
  COMMON QUESTIONS / FAQ
────────────────────────────────────────────────────────────────────────────────

  Q: Does this script make any changes to my devices?
  A: No. It is 100% read-only. It only reads device data — it does not modify,
     wipe, retire, or take any action on devices.

  Q: Do I need PowerShell 7?
  A: No. The script runs on PowerShell 5.1 and later.

  Q: Do I need to install any modules?
  A: No. The script uses only built-in PowerShell cmdlets and direct REST API
     calls. No module installation required.

  Q: What is the difference between File Mode and All Mode?
  A: File Mode looks up specific devices by hostname from a .txt file and
     returns those devices regardless of OS platform. All Mode pulls your
     entire Intune inventory (or a filtered subset by OS) in one run.

  Q: Why does the script fetch each device individually instead of using $select?
  A: The Intune managedDevices list endpoint does not return usersLoggedOn
     regardless of $select usage — it is only available on the individual
     device entity endpoint. The per-device entity fetch is required to get
     the Last Logged On User and guarantee all 35 fields are populated.

  Q: Can I filter by OS in File Mode?
  A: No. File Mode returns the device regardless of platform. OS filter only
     applies in All Mode.

  Q: What happens if a hostname has multiple Intune records?
  A: All records are exported to the CSV and a DUPLICATE warning is printed
     to the console. Use the EnrolledDateTime column to identify the current
     active record. To clean up duplicates in a group, use the companion
     script Get-GroupDeviceIntuneReport.ps1.

  Q: How is this different from Get-WindowsDeviceInventory.ps1?
  A: Get-WindowsDeviceInventory.ps1 is optimised for large fleet exports —
     it uses parallel runspace processing and is significantly faster for
     full Windows inventory pulls (5,000+ devices).
     Get-IntuneDeviceSummary.ps1 adds File Mode (hostname lookup) and
     supports all OS platforms, but processes devices sequentially.
     For targeted lookups or smaller fleets, use this script.
     For fast full Windows fleet exports, use Get-WindowsDeviceInventory.ps1.

  Q: Does the script write a log file?
  A: No. All output is to the console only. To capture a log file for
     scheduled runs, wrap the script in PowerShell transcript:
       Start-Transcript -Path "C:\Logs\run.log"
       .\Get-IntuneDeviceSummary.ps1
       Stop-Transcript

  Q: Can I schedule this script to run automatically?
  A: Yes. Use Windows Task Scheduler or a CI/CD pipeline. For scheduled runs
     set $InputFile, $OSFilter, and $OutputFolder in the script so no
     interactive prompts appear. Store credentials securely (Azure Key Vault
     recommended) rather than plain text in the script.

================================================================================
  END OF README
================================================================================
