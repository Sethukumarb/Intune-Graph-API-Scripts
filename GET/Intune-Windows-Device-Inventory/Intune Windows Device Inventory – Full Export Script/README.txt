================================================================================
  README — Get-WindowsDeviceInventory.ps1
  Intune Windows Device Full Inventory Export
  Author: Sethu Kumar B  |  Version: 1.2
================================================================================

────────────────────────────────────────────────────────────────────────────────
  SCRIPT NAME
────────────────────────────────────────────────────────────────────────────────

  Get-WindowsDeviceInventory.ps1

────────────────────────────────────────────────────────────────────────────────
  FOLDER NAME
────────────────────────────────────────────────────────────────────────────────

  Intune-Windows-Device-Inventory

────────────────────────────────────────────────────────────────────────────────
  PURPOSE
────────────────────────────────────────────────────────────────────────────────

  Exports a complete inventory of all Windows devices managed in Microsoft
  Intune via the Microsoft Graph API. Designed for IT administrators who need
  a detailed, audit-ready snapshot of their entire Windows device fleet — with
  a single CSV output containing 50+ fields per device.

────────────────────────────────────────────────────────────────────────────────
  WHAT THE SCRIPT DOES
────────────────────────────────────────────────────────────────────────────────

  1. Authenticates to Microsoft Graph using App Registration credentials
     (Client ID + Client Secret + Tenant ID).

  2. Fetches ALL Windows managed devices from the Intune /beta endpoint,
     paginated at up to 1,000 records per page.

  3. Enriches each device with Last Logged On User data using parallel
     PowerShell Runspaces (PS 5.1 compatible — no PS 7 required).

  4. Shapes each device record into a clean, labelled row with 50+ columns:

       — Identity        : DeviceName, SerialNumber, IntuneDeviceID, AzureAD DeviceID
       — OS Details      : Friendly OS name (e.g. "Windows 11 23H2"), version, build
       — Hardware        : Manufacturer, Model, RAM, Total/Free Storage,
                          CPU Architecture, WiFi MAC, Ethernet MAC
       — User Info       : Primary User UPN, Display Name, AAD Object ID,
                          Last Logged On User, Enrolled By
       — Enrollment      : Type, Join Type, Autopilot status, Enrolled Date
       — Compliance      : Compliance state, Grace period expiry
       — Management      : Management state, agent, certificate expiry
       — Security        : Encryption, Device Guard, VBS, Credential Guard,
                          Partner Threat State
       — Exchange / EAS  : EAS activation, access state
       — Timestamps      : Last Sync Date, Days Since Last Sync
       — Notes           : Device Notes field from Intune

  5. Exports a single UTF-8 CSV file named:
       Windows_Device_Inventory_[YYYYMMDD_HHmmss].csv

  6. Writes a matching .log file (same timestamp) with full run output,
     including per-step progress, summary counts, and any errors.

  7. Prints a final console summary:
       — OS breakdown (Windows 10 vs Windows 11)
       — Compliance counts (Compliant / Non-Compliant / Unknown)
       — Encryption counts
       — Enrollment counts (Autopilot, AAD Joined, Hybrid Joined)

────────────────────────────────────────────────────────────────────────────────
  PREREQUISITES
────────────────────────────────────────────────────────────────────────────────

  - PowerShell 5.1 or later (no additional modules required)
  - An Azure AD App Registration with a Client Secret
  - Admin consent granted for required Graph API permissions (see below)
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
  DeviceManagementManagedDevices.Read.All      Fetch device inventory + logon data
  DeviceManagementConfiguration.Read.All       Read enrollment profile info
  Device.Read.All                              Read AAD device join type details

  NOTE: This script is READ-ONLY. It does not modify, wipe, or take any action
  on devices. A read-only App Registration is strongly recommended.

────────────────────────────────────────────────────────────────────────────────
  HOW TO RUN THE SCRIPT
────────────────────────────────────────────────────────────────────────────────

  Step 1 — Open the script in any text editor (Notepad, VS Code, ISE).

  Step 2 — Fill in your credentials at the top of the script:

              $TenantID     = "your-tenant-id"
              $ClientID     = "your-client-id"
              $ClientSecret = "your-client-secret"

  Step 3 — (Optional) Set a custom output folder:

              $OutputFolder = "C:\Reports\Intune"
              Leave blank to save next to the script.

  Step 4 — (Optional) Adjust performance settings:

              $MaxParallelJobs = 10   # Increase for large fleets (max: 20)
              $PageSize        = 1000 # Leave at 1000 (Graph API maximum)

  Step 5 — Open PowerShell and run:

              .\Get-WindowsDeviceInventory.ps1

  Step 6 — Wait for completion. Progress is shown on-screen.
            The CSV and log file are saved to the output folder.

────────────────────────────────────────────────────────────────────────────────
  EXPECTED OUTPUT
────────────────────────────────────────────────────────────────────────────────

  File 1 — CSV Report:
    Windows_Device_Inventory_[timestamp].csv
    One row per Windows device. 50+ columns. UTF-8 encoded.
    Ready to open in Excel or import into Power BI / reporting tools.

  File 2 — Log File:
    Windows_Device_Inventory_[timestamp].log
    Full timestamped run log — all console output mirrored to disk.
    Useful for auditing, troubleshooting, and scheduling automation.

  Console Summary (printed at end of run):
    - Total devices
    - Windows 10 vs Windows 11 count
    - Compliant / Non-Compliant / Unknown counts
    - Encrypted / Not Encrypted counts
    - Autopilot / AAD Joined / Hybrid Joined counts

────────────────────────────────────────────────────────────────────────────────
  IMPORTANT NOTES
────────────────────────────────────────────────────────────────────────────────

  - Uses the /beta Graph API endpoint. Beta endpoints may change without notice.
    Microsoft does not guarantee beta endpoint stability for production use.

  - $filter and $select cannot be combined on the managedDevices collection
    endpoint — this causes HTTP 400. The script intentionally omits $select
    to avoid this known Graph API limitation.

  - The enrolledByUserId field is only available via the beta endpoint.
    It is not returned by the v1.0 endpoint.

  - Last Logged On User requires a separate per-device API call. This is why
    parallel runspaces are used — to keep run time acceptable for large fleets.

  - $MaxParallelJobs controls runspace thread count. Keep at 10 (default) for
    safety. Maximum recommended: 20. Higher values may trigger Graph API
    throttling (HTTP 429).

  - The script stores credentials as plain text in the script file. For
    production/scheduled use, store secrets in Azure Key Vault or use
    Windows Credential Manager.

────────────────────────────────────────────────────────────────────────────────
  TROUBLESHOOTING TIPS
────────────────────────────────────────────────────────────────────────────────

  PROBLEM          : Authentication fails / token not acquired
  SOLUTION         : Verify TenantID, ClientID, ClientSecret are correct.
                     Check App Registration is not expired or disabled.

  PROBLEM          : 0 devices returned
  SOLUTION         : Confirm admin consent is granted for all three permissions.
                     Verify devices are enrolled in Intune (not just AAD joined).

  PROBLEM          : HTTP 400 Bad Request on device query
  SOLUTION         : Already handled in v1.1+. Do not add $select to the
                     collection URI — it conflicts with $filter on this endpoint.

  PROBLEM          : HTTP 429 Too Many Requests (throttling)
  SOLUTION         : Reduce $MaxParallelJobs (try 5). Add a Start-Sleep delay
                     between pages if running on very large fleets (10,000+).

  PROBLEM          : CSV opens garbled in Excel (encoding issue)
  SOLUTION         : Open Excel → Data → From Text/CSV → select UTF-8 encoding.

  PROBLEM          : LastLoggedOn_UserID shows "LOOKUP ERROR" for some devices
  SOLUTION         : Device may be stale or token expired mid-run. This is
                     non-fatal — all other fields for that device are still
                     exported correctly.

  PROBLEM          : Script hangs / very slow
  SOLUTION         : Large fleets (5,000+ devices) may take 10–30 minutes.
                     The last-logon enrichment step is the longest. Increase
                     $MaxParallelJobs (max 20) to speed it up.

================================================================================
  GUMROAD LISTING
================================================================================

────────────────────────────────────────────────────────────────────────────────
  GUMROAD LISTING TITLE
────────────────────────────────────────────────────────────────────────────────

  Intune Windows Device Inventory – Full CSV Export Script (PowerShell)

────────────────────────────────────────────────────────────────────────────────
  GUMROAD PRODUCT DESCRIPTION
────────────────────────────────────────────────────────────────────────────────

  Stop building device reports manually. This PowerShell script connects to
  Microsoft Intune via the Graph API and exports a complete Windows device
  inventory to a clean, ready-to-use CSV — in minutes, not hours.

  One script. One CSV. Every Windows device in your Intune tenant, with
  over 50 fields per device — hardware specs, OS versions, compliance state,
  encryption status, enrollment type, user info, last sync date, and more.

  No extra modules to install. Works on PowerShell 5.1. No PS 7 required.

  ✅ What you get:
  — Ready-to-run PowerShell script (Get-WindowsDeviceInventory.ps1)
  — Full README with setup instructions, permissions guide, and troubleshooting
  — CSV output with 50+ columns per device
  — Automatic .log file for every run (full audit trail)
  — Parallel processing for fast results on large fleets
  — Run summary printed to console: OS, compliance, encryption, enrollment counts

  Perfect for monthly IT audits, compliance reviews, hardware refresh planning,
  and executive reporting. Drop the CSV straight into Excel or Power BI.

────────────────────────────────────────────────────────────────────────────────
  KEY FEATURES
────────────────────────────────────────────────────────────────────────────────

  - Exports 50+ fields per device in a single CSV run
  - Parallel runspace processing — fast even on fleets of 5,000+ devices
  - Works on PowerShell 5.1 (no PS 7, no extra modules needed)
  - Friendly OS name mapping (e.g. "Windows 11 23H2" instead of raw build)
  - Last Logged On User enrichment via parallel Graph API calls
  - Enrollment type, join type, Autopilot status — all decoded to readable labels
  - Device Guard, VBS, Credential Guard, and encryption fields included
  - Days Since Last Sync calculated automatically
  - Full run log saved alongside the CSV for auditing and scheduling
  - Console summary at end of run with OS, compliance, and encryption counts
  - Uses /beta endpoint for maximum field coverage (including enrolledByUserId)
  - Configurable output folder, page size, and parallel thread count

────────────────────────────────────────────────────────────────────────────────
  WHO THIS SCRIPT IS FOR
────────────────────────────────────────────────────────────────────────────────

  - IT Administrators managing Microsoft Intune environments
  - System Engineers running compliance audits or device reviews
  - Security teams tracking encryption and compliance posture
  - IT Managers preparing hardware refresh or OS upgrade reports
  - Consultants needing fast, repeatable Intune device inventory exports
  - Anyone who wants a clean, complete Intune device report without clicking
    through the Intune portal screen by screen

────────────────────────────────────────────────────────────────────────────────
  SUGGESTED TAGS / KEYWORDS
────────────────────────────────────────────────────────────────────────────────

  Intune, Microsoft Intune, PowerShell, Graph API, Windows Device Inventory,
  Device Report, Intune Export, Intune CSV, Managed Devices, MDM Report,
  IT Admin, Microsoft Endpoint Manager, Device Audit, Compliance Report,
  Windows 10, Windows 11, Azure AD, Device Management, Intune Automation,
  PowerShell Script, IT Tools

────────────────────────────────────────────────────────────────────────────────
  BUYER INSTRUCTIONS
────────────────────────────────────────────────────────────────────────────────

  After purchase you will receive a ZIP file containing:
    — Get-WindowsDeviceInventory.ps1
    — README.txt (this file)

  Quick start:
    1. Create an Azure AD App Registration with a Client Secret.
    2. Grant the three Graph API permissions listed in this README.
    3. Grant admin consent in the Azure portal.
    4. Open the script and fill in TenantID, ClientID, ClientSecret.
    5. Run: .\Get-WindowsDeviceInventory.ps1
    6. Find your CSV and log file in the same folder as the script.

  Need help with App Registration setup? The README includes a full
  permissions list and step-by-step troubleshooting guide.

────────────────────────────────────────────────────────────────────────────────
  COMMON QUESTIONS / FAQ
────────────────────────────────────────────────────────────────────────────────

  Q: Does this script make any changes to my devices?
  A: No. It is 100% read-only. It only reads device data — it does not modify,
     wipe, retire, or take any action on devices.

  Q: Do I need PowerShell 7?
  A: No. The script runs on PowerShell 5.1 and later. No upgrade required.

  Q: Do I need to install any modules (e.g. Microsoft.Graph)?
  A: No. The script uses only built-in PowerShell cmdlets and direct REST API
     calls. No module installation required.

  Q: How long does it take to run?
  A: Depends on fleet size. A 500-device fleet typically takes 2–5 minutes.
     A 5,000-device fleet may take 15–30 minutes (most time is the per-device
     last-logon enrichment step).

  Q: Can I schedule this script to run automatically?
  A: Yes. Use Windows Task Scheduler or a CI/CD pipeline. For scheduled runs,
     store credentials securely (Azure Key Vault recommended) rather than
     plain text in the script.

  Q: Can I filter for specific devices (e.g. non-compliant only)?
  A: The script exports all Windows devices. Post-export filtering can be done
     in Excel or Power BI using the ComplianceState column.

  Q: Can I add more columns to the CSV?
  A: Yes. Modify the Shape-DeviceRecord function to include additional fields
     returned by the Graph API. All raw device properties are available in the
     $Device object inside that function.

  Q: Does this work for macOS or iOS devices too?
  A: This version is Windows-only. The Graph API filter is set to
     operatingSystem eq 'Windows'. Separate scripts are available for
     macOS and iOS/Android inventories.

  Q: What if some fields show "N/A"?
  A: N/A means the field was not populated for that device in Intune.
     This is normal — for example, IMEI and MEID are empty for laptops,
     and EAS fields are empty for non-Exchange-connected devices.

================================================================================
  END OF README
================================================================================
