================================================================================
  README — Get-UserDevices.ps1
  Intune User Device Lookup – Per-User CSV Export
  Author: Sethu Kumar B  |  Version: 1.0
================================================================================

────────────────────────────────────────────────────────────────────────────────
  SCRIPT NAME
────────────────────────────────────────────────────────────────────────────────

  Get-UserDevices.ps1

────────────────────────────────────────────────────────────────────────────────
  FOLDER NAME
────────────────────────────────────────────────────────────────────────────────

  Intune-User-Device-Lookup

────────────────────────────────────────────────────────────────────────────────
  PURPOSE
────────────────────────────────────────────────────────────────────────────────

  Looks up all devices associated with one or more users in Microsoft Intune
  and Azure AD. Reads a list of email addresses from a text file, queries both
  Intune and Azure AD for each user, and exports a separate CSV file per user
  containing all their devices — deduplicated and clearly labelled by source.

────────────────────────────────────────────────────────────────────────────────
  WHAT THE SCRIPT DOES
────────────────────────────────────────────────────────────────────────────────

  1. Reads email addresses (one per line) from users.txt in the script folder.

  2. Connects to Microsoft Graph using App Registration credentials
     (Client ID + Client Secret + Tenant ID).

  3. For each user email address:

       a) Queries Intune /managedDevices — returns devices where the user is
          the primary user (matched by userPrincipalName or emailAddress).

       b) Queries Azure AD /users/{id}/registeredDevices — returns devices
          linked to the user's Azure AD / Entra ID profile, including devices
          that may not be Intune-enrolled.

       c) Combines both result sets and deduplicates by DeviceName + DeviceSource.

       d) Exports a per-user CSV file named:
            <email>-Devices.csv
            (@ replaced with _at_ for filesystem safety)
            Example: john.doe_at_contoso.com-Devices.csv

       e) If no devices are found, a placeholder CSV is still created
          so no user is silently skipped.

  4. Each CSV row includes:
       — UserEmail           : The email address queried
       — DeviceSource        : "Intune (Managed Device)" or
                               "Azure AD (Registered Device)"
       — DeviceName          : Device display name
       — IntuneDeviceId      : Intune managed device ID (blank for AAD-only)
       — AzureADDeviceId     : Azure AD device ID
       — AzureADObjectId     : Azure AD directory object ID
       — UserPrincipalName   : User UPN from the device record
       — SerialNumber        : Serial number (Intune only; blank for AAD-only)
       — OperatingSystem     : OS reported by Intune or Azure AD

  5. Writes two log files to the script folder:
       — Get-UserDevices-Transcript.log  : Full PowerShell transcript
       — Get-UserDevices-Actions.log     : Timestamped action log (key events,
                                          warnings, and errors)

  6. Optional OS filter (-TargetOS) limits results to a specific platform.
     Default is Windows. Pass an empty string to return all platforms.

────────────────────────────────────────────────────────────────────────────────
  PREREQUISITES
────────────────────────────────────────────────────────────────────────────────

  - PowerShell 5.1 or later
  - Microsoft Graph PowerShell SDK installed:
      Install-Module Microsoft.Graph -Scope CurrentUser
  - An Azure AD App Registration with a Client Secret
  - Admin consent granted for required Graph API permissions (see below)
  - A users.txt file in the same folder as the script (one email per line)
  - Network access to:
      https://login.microsoftonline.com   (OAuth2 token endpoint)
      https://graph.microsoft.com         (Graph API — v1.0 endpoint)

────────────────────────────────────────────────────────────────────────────────
  REQUIRED MICROSOFT GRAPH API PERMISSIONS
────────────────────────────────────────────────────────────────────────────────

  All permissions are APPLICATION type (not Delegated).
  Admin consent must be granted in the Azure portal.

  Permission                                   Reason
  ─────────────────────────────────────────── ──────────────────────────────────
  DeviceManagementManagedDevices.Read.All      Query Intune managed devices
  Device.Read.All                              Query Azure AD registered devices
  User.Read.All                                Resolve user by email / UPN

  NOTE: This script is READ-ONLY. It does not modify, wipe, or take any action
  on users or devices. A read-only App Registration is strongly recommended.

────────────────────────────────────────────────────────────────────────────────
  HOW TO RUN THE SCRIPT
────────────────────────────────────────────────────────────────────────────────

  Step 1 — Install the Microsoft Graph PowerShell SDK (one-time setup):

              Install-Module Microsoft.Graph -Scope CurrentUser

  Step 2 — Create your users.txt file in the same folder as the script.
            One email address per line. Example:

              john.doe@contoso.com
              jane.smith@contoso.com
              helpdesk@contoso.com

  Step 3 — Open the script and fill in your credentials in the param block:

              $TenantId     = "your-tenant-id"
              $ClientId     = "your-client-id"
              $ClientSecret = "your-client-secret"

            OR pass them at runtime (see Step 5 examples).

  Step 4 — (Optional) Change the OS filter default:

              $TargetOS = "Windows"   # Default
              $TargetOS = ""          # Return all platforms
              $TargetOS = "macOS"     # macOS only
              $TargetOS = "iOS"       # iOS only
              $TargetOS = "Android"   # Android only

  Step 5 — Open PowerShell and run:

              # Basic run (uses defaults from param block):
              .\Get-UserDevices.ps1

              # With OS filter override:
              .\Get-UserDevices.ps1 -TargetOS "Windows"

              # All platforms (no OS filter):
              .\Get-UserDevices.ps1 -TargetOS ""

              # Custom input file:
              .\Get-UserDevices.ps1 -InputFile "vip-users.txt"

  Step 6 — Find output CSV files in the same folder as the script,
            one file per user email address.

────────────────────────────────────────────────────────────────────────────────
  EXPECTED OUTPUT
────────────────────────────────────────────────────────────────────────────────

  Per-user CSV files (one per email in users.txt):
    <email>-Devices.csv
    Example: john.doe_at_contoso.com-Devices.csv
    Contains all Intune + Azure AD devices for that user, deduplicated.
    If no devices found, an empty placeholder CSV is still created.

  Transcript log:
    Get-UserDevices-Transcript.log
    Full PowerShell session transcript — everything printed to the console.

  Action log:
    Get-UserDevices-Actions.log
    Timestamped key events: user processed, device found, warnings, errors.
    Easier to read than the full transcript for quick status checks.

  DeviceSource column values in CSV:
    "Intune (Managed Device)"       — Device enrolled in Intune
    "Azure AD (Registered Device)"  — Device in user's Azure AD profile
                                      (may or may not be Intune-enrolled)

────────────────────────────────────────────────────────────────────────────────
  IMPORTANT NOTES
────────────────────────────────────────────────────────────────────────────────

  - Uses the Graph API v1.0 endpoint (stable — not beta).

  - Requires the Microsoft Graph PowerShell SDK. This is different from
    Get-WindowsDeviceInventory.ps1 which uses raw REST calls with no modules.
    Run Install-Module Microsoft.Graph before first use.

  - SerialNumber is only available for Intune managed devices. Azure AD
    registered device records do not include serial numbers.

  - IntuneDeviceId is blank for Azure AD registered devices that are not
    enrolled in Intune.

  - Deduplication is by DeviceName + DeviceSource. A device may appear twice
    if it exists in both Intune and Azure AD under different display names.

  - The @ symbol in email addresses is replaced with _at_ in output filenames
    to keep filenames filesystem-safe and human-readable.

  - If users.txt is empty or missing, the script throws a fatal error and stops.

  - For scheduled/automated runs, store credentials securely rather than
    plain text in the script (Azure Key Vault recommended).

────────────────────────────────────────────────────────────────────────────────
  TROUBLESHOOTING TIPS
────────────────────────────────────────────────────────────────────────────────

  PROBLEM          : "Input file not found" error
  SOLUTION         : Create users.txt in the same folder as the script.
                     Ensure the filename matches the -InputFile parameter.

  PROBLEM          : "No email addresses found" error
  SOLUTION         : Check users.txt is not empty and has one email per line.
                     Remove blank lines or extra spaces.

  PROBLEM          : Connect-MgGraph fails / authentication error
  SOLUTION         : Verify TenantId, ClientId, ClientSecret are correct.
                     Confirm the App Registration is not expired or disabled.
                     Confirm admin consent is granted for all three permissions.

  PROBLEM          : CSV created but empty (only placeholder row)
  SOLUTION         : The user has no devices matching the OS filter.
                     Try running with -TargetOS "" to return all platforms.
                     Confirm the email in users.txt exactly matches the UPN
                     or mail attribute in Azure AD (case-insensitive).

  PROBLEM          : Module not found — Microsoft.Graph
  SOLUTION         : Run: Install-Module Microsoft.Graph -Scope CurrentUser
                     Then re-run the script.

  PROBLEM          : Script returns Azure AD devices but no Intune devices
  SOLUTION         : The user's devices may be Azure AD registered but not
                     Intune-enrolled. Check DeviceSource column in the CSV.
                     This is expected behaviour — both sources are shown.

  PROBLEM          : Duplicate devices appear in CSV
  SOLUTION         : Deduplication is by DeviceName + DeviceSource. If the same
                     physical device has different display names in Intune vs
                     Azure AD, it appears as two rows. This is by design.

  PROBLEM          : Transcript or action log not created
  SOLUTION         : Confirm the script has write permission to its own folder.
                     Run PowerShell as Administrator if needed.

================================================================================
  GUMROAD LISTING
================================================================================

────────────────────────────────────────────────────────────────────────────────
  GUMROAD LISTING TITLE
────────────────────────────────────────────────────────────────────────────────

  Intune User Device Lookup – Per-User CSV Export Script (PowerShell)

────────────────────────────────────────────────────────────────────────────────
  GUMROAD PRODUCT DESCRIPTION
────────────────────────────────────────────────────────────────────────────────

  Need to know exactly which devices a user has in Intune and Azure AD?
  This PowerShell script does it in bulk — give it a list of email addresses
  and it returns a separate, ready-to-use CSV for every user.

  No manual portal clicks. No copying and pasting. Just drop your email list
  into users.txt, run the script, and get one CSV per user with every device
  they own — from both Intune and Azure AD — combined and deduplicated.

  Built for IT helpdesk, compliance teams, and sysadmins who need quick,
  accurate device lookups for multiple users at once.

  ✅ What you get:
  — Ready-to-run PowerShell script (Get-UserDevices.ps1)
  — Full README with setup instructions, permissions guide, and troubleshooting
  — One CSV per user — named after their email address
  — Devices from both Intune and Azure AD in a single output
  — DeviceSource column clearly labels where each record came from
  — Optional OS filter (Windows / macOS / iOS / Android / all)
  — Full PowerShell transcript + action log for every run
  — Empty placeholder CSV created when no devices found (no silent failures)

────────────────────────────────────────────────────────────────────────────────
  KEY FEATURES
────────────────────────────────────────────────────────────────────────────────

  - Bulk user lookup — process as many users as needed from a single text file
  - Queries both Intune managed devices AND Azure AD registered devices per user
  - Combines and deduplicates results across both sources automatically
  - DeviceSource column clearly identifies Intune vs Azure AD origin
  - One CSV file per user, named after their email address
  - Optional OS filter: Windows, macOS, iOS, Android, or all platforms
  - Placeholder CSV created for users with no devices (no silent skips)
  - Full PowerShell transcript saved for audit and troubleshooting
  - Timestamped action log for quick status review
  - Uses stable Graph API v1.0 endpoint (not beta)
  - Works on PowerShell 5.1 and later
  - Clean, readable filenames (@ replaced with _at_ in output file names)

────────────────────────────────────────────────────────────────────────────────
  WHO THIS SCRIPT IS FOR
────────────────────────────────────────────────────────────────────────────────

  - IT Helpdesk staff looking up devices for specific users
  - IT Administrators auditing device ownership across a user list
  - Security teams checking which devices a departing employee had
  - Compliance teams verifying device enrollment for a group of users
  - Sysadmins preparing for hardware refresh or device reassignment
  - Consultants running user-specific device audits for clients
  - Anyone who needs to answer "what devices does this user have?" — fast

────────────────────────────────────────────────────────────────────────────────
  SUGGESTED TAGS / KEYWORDS
────────────────────────────────────────────────────────────────────────────────

  Intune, Microsoft Intune, PowerShell, Graph API, User Device Lookup,
  Intune User Devices, Azure AD Devices, Device Report, Per-User CSV,
  IT Admin, Microsoft Endpoint Manager, Helpdesk Tool, Device Audit,
  Entra ID, Registered Devices, Managed Devices, Bulk User Lookup,
  PowerShell Script, IT Tools, Offboarding, Device Ownership

────────────────────────────────────────────────────────────────────────────────
  BUYER INSTRUCTIONS
────────────────────────────────────────────────────────────────────────────────

  After purchase you will receive a ZIP file containing:
    — Get-UserDevices.ps1
    — README.txt (this file)

  Quick start:
    1. Install the Microsoft Graph SDK:
         Install-Module Microsoft.Graph -Scope CurrentUser
    2. Create an Azure AD App Registration with a Client Secret.
    3. Grant the three Graph API permissions listed in this README.
    4. Grant admin consent in the Azure portal.
    5. Create users.txt in the same folder as the script.
       Add one email address per line.
    6. Open the script and fill in TenantId, ClientId, ClientSecret.
    7. Run: .\Get-UserDevices.ps1
    8. Find one CSV per user in the same folder as the script.

  Need help? The README includes a full permissions guide, parameter
  reference, and step-by-step troubleshooting for common issues.

────────────────────────────────────────────────────────────────────────────────
  COMMON QUESTIONS / FAQ
────────────────────────────────────────────────────────────────────────────────

  Q: Does this script make any changes to users or devices?
  A: No. It is 100% read-only. It only reads device data — it does not modify,
     wipe, retire, or take any action on users or devices.

  Q: Do I need PowerShell 7?
  A: No. The script runs on PowerShell 5.1 and later.

  Q: Do I need to install any modules?
  A: Yes — the Microsoft Graph PowerShell SDK is required. Install it once:
       Install-Module Microsoft.Graph -Scope CurrentUser

  Q: How many users can I process at once?
  A: As many as you need. Add one email per line in users.txt. The script
     loops through all of them and creates a separate CSV for each.

  Q: What is the difference between "Intune (Managed Device)" and
     "Azure AD (Registered Device)" in the DeviceSource column?
  A: "Intune (Managed Device)" means the device is enrolled in Intune and
     managed by MDM policy. "Azure AD (Registered Device)" means the device
     is registered in Azure AD / Entra ID but may not be Intune-enrolled —
     for example, a BYOD device that is workplace-joined but not fully managed.

  Q: Can I filter by operating system?
  A: Yes. Use the -TargetOS parameter. Examples:
       .\Get-UserDevices.ps1 -TargetOS "Windows"
       .\Get-UserDevices.ps1 -TargetOS "macOS"
       .\Get-UserDevices.ps1 -TargetOS ""   (all platforms)

  Q: What if a user has no devices?
  A: A placeholder CSV is still created for that user so no email is
     silently skipped. The action log records a WARN entry for that user.

  Q: Can I use a different input file name?
  A: Yes. Use the -InputFile parameter:
       .\Get-UserDevices.ps1 -InputFile "vip-users.txt"

  Q: Can I schedule this script to run automatically?
  A: Yes. Use Windows Task Scheduler or a CI/CD pipeline. For scheduled runs,
     store credentials securely (Azure Key Vault recommended) rather than
     plain text in the script.

  Q: How is this different from Get-WindowsDeviceInventory.ps1?
  A: Get-WindowsDeviceInventory.ps1 exports a full fleet-wide inventory of
     ALL Windows devices in Intune — regardless of user.
     Get-UserDevices.ps1 looks up devices for specific users from a list,
     queries both Intune AND Azure AD, and exports one CSV per user.
     They are complementary tools — use both for complete coverage.

================================================================================
  END OF README
================================================================================
