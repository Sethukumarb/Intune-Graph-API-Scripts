================================================================================
  README - Get-DeviceInventoryBySerial.ps1
  Author : Sethu Kumar B
================================================================================

SCRIPT NAME
-----------
Get-DeviceInventoryBySerial.ps1

FOLDER NAME
-----------
Get-DeviceInventoryBySerial

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Pulls a complete cross-system inventory for a list of device serial numbers.

For each serial number, reports all linked records across three systems:
  - Microsoft Intune (managed device records)
  - Windows Autopilot (device identity records)
  - Azure AD / Entra ID (device objects)

Detects duplicate records in each system per serial. Read-only — no changes
made anywhere.

Use this script before device refresh, re-imaging, re-enrollment, or any
cleanup operation where you need a full picture of what exists for a device
across all three systems.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Reads serial numbers from inputserialnumber.txt (same folder as script).
   Blank lines and # comment lines are ignored.

2. Authenticates to Microsoft Graph API using Azure AD app credentials
   (client credentials flow — no user sign-in required).

3. Bulk pulls ALL Windows managed devices from Intune (server-side filtered
   by operatingSystem = Windows). Indexes by serial number for fast lookup.

4. Bulk pulls ALL Autopilot device identities (beta endpoint, no $select).
   Indexes by serial number.

5. For each input serial number:
   a. Looks up all matching Intune records — flags duplicates if more than one.
   b. Looks up all matching Autopilot records — flags duplicates if more than one.
   c. Looks up Azure AD device objects using azureADDeviceId from Intune records.
      Handles multiple Azure AD objects per device ID (Entra duplicates).

6. Builds one CSV row per record per system per serial.
   Verdict column on every row clearly states what was found or missing.

7. Exports timestamped CSV, log file, and PowerShell transcript to $PSScriptRoot.

8. Prints a full console summary with counts per system and duplicate flags.

NO changes are made to any Intune, Autopilot, or Azure AD record.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- inputserialnumber.txt in the same folder as the script
  (one serial number per line; # comments and blank lines ignored)
- Azure AD App Registration with Tenant ID, Client ID, Client Secret
- Admin consent granted for required Graph API permissions (see below)
- Network access to login.microsoftonline.com and graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission Type : Application (no user sign-in required)

Permission Name                              Required For
--------------------------------------------+-----------------------------------
DeviceManagementManagedDevices.Read.All      Intune managed device records
DeviceManagementServiceConfig.Read.All       Autopilot device identity records
Device.Read.All                              Azure AD device object lookup
                                             (OPTIONAL — script handles
                                              missing permission gracefully;
                                              Azure AD lookup shows
                                              NO PERMISSION in CSV verdict)

Admin Consent : Required for all permissions above.

--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File name : inputserialnumber.txt
Location  : Same folder as the script ($PSScriptRoot)

Format:
  - One serial number per line
  - Lines starting with # are treated as comments and ignored
  - Blank lines are ignored

Example:
  # Lab devices refresh batch 1
  ABC123456
  DEF789012
  # GHI345678   <- this line is skipped

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1 - Create inputserialnumber.txt in the script folder.
         Add one serial number per line.

Step 2 - Open Get-DeviceInventoryBySerial.ps1 in any text editor or PS ISE.

Step 3 - Fill in the CONFIGURATION block:

         $TenantID     = "your-tenant-id"
         $ClientID     = "your-client-id"
         $ClientSecret = "your-client-secret"

Step 4 - Open PowerShell 5.1 or later and navigate to the script folder:
         cd "C:\Path\To\Get-DeviceInventoryBySerial"

Step 5 - Run the script:
         .\Get-DeviceInventoryBySerial.ps1

Step 6 - Review console output and generated files.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console:
  - Step-by-step progress per serial number
  - Duplicate warnings (WARN in yellow) when multiple records found
  - Summary counts per system (Intune / Autopilot / Azure AD)

Files (saved to same folder as script):
  - DeviceInventory_[Timestamp].csv
  - DeviceInventory_[Timestamp].log
  - DeviceInventory_Transcript_[Timestamp].log

CSV Columns (25):
  SerialNumber, RecordType, RecordIndex,
  DeviceName, Manufacturer, Model,
  OSPlatform, OSVersion,
  IntuneDeviceID, AzureADDeviceID,
  AutopilotDeviceID, GroupTag,
  EnrollmentState, ComplianceState, ManagementState,
  PrimaryUserUPN, LastSyncDateTime, EnrollmentDate,
  ProfileStatus, ProfileName,
  AzureADObjectID, AzureADDisplayName,
  AzureADIsManaged, AzureADIsCompliant,
  Verdict

--------------------------------------------------------------------------------
VERDICT VALUES
--------------------------------------------------------------------------------
Intune:
  FOUND - 1 Intune record
  FOUND - DUPLICATE (N of M Intune records)
  NOT FOUND in Intune

Autopilot:
  FOUND - 1 Autopilot record
  FOUND - DUPLICATE (N of M Autopilot records)
  NOT FOUND in Autopilot

Azure AD:
  Azure AD - FOUND - 1 object
  Azure AD - FOUND - DUPLICATE (N of M Azure AD objects)
  Azure AD - NOT FOUND in Azure AD
  Azure AD - NO PERMISSION - Device.Read.All not granted
  Azure AD - no device ID available (device may not be in Intune)

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Script is READ-ONLY. No changes made to any record in any system.

- Intune pull is filtered to Windows devices only (server-side).
  iOS, Android, and macOS devices are excluded from the bulk pull.
  If you need cross-platform inventory, remove the operatingSystem filter
  from the $IntuneUri variable in the script.

- Autopilot endpoint uses the beta Graph API. No $select is used
  because $select with $top causes HTTP 500 on this endpoint.

- Azure AD lookup uses v1.0 Graph API. The Device.Read.All permission
  is optional — if not granted, the script continues and marks Azure AD
  rows as NO PERMISSION rather than failing.

- A 200ms delay is added between Azure AD lookups per device to reduce
  the chance of Graph API throttling.

- $MaxRetries (default: 5) controls how many times a page fetch is retried
  on HTTP 429. The script reads the Retry-After header and waits before
  retrying, plus random 1-10 second jitter.

- The PowerShell transcript captures full console output including all
  Write-Host and Write-Log output for each run.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Problem : Authentication fails immediately
Fix     : Verify TenantID, ClientID, ClientSecret are correct.
          Confirm the app secret has not expired.

Problem : Input file not found error
Fix     : Confirm inputserialnumber.txt exists in the same folder as
          the script. The filename must match exactly (case-sensitive
          on some systems).

Problem : All serials return NOT FOUND in Intune
Fix     : Confirm DeviceManagementManagedDevices.Read.All admin consent
          is granted. Verify the serials are Windows devices — the script
          filters to Windows only by default.

Problem : All Azure AD rows show NO PERMISSION
Fix     : Grant Device.Read.All Application permission with admin consent
          to the Azure AD App Registration. Or leave it — the script
          handles this gracefully and continues.

Problem : Duplicate records found in Intune or Autopilot
Fix     : This is expected output — the script is detecting what already
          exists. Duplicates should be cleaned up via the Intune portal
          or a separate cleanup script before re-enrollment.

Problem : HTTP 429 errors in log
Fix     : The script handles 429 automatically with Retry-After backoff.
          If persistent, increase $MaxRetries or run during off-peak hours.

Problem : Autopilot records show N/A for many fields
Fix     : Expected. The Autopilot endpoint returns limited fields compared
          to Intune. ProfileName requires a deployed profile assigned to
          the device to populate.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Device Inventory by Serial – Intune + Autopilot + Azure AD | PowerShell Script

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Get a complete picture of any device across Intune, Autopilot, and Azure AD
— from a simple list of serial numbers.

This PowerShell script takes a text file of serial numbers and builds a full
cross-system inventory report in one run. For each serial, it checks all three
Microsoft endpoint systems, flags duplicate records, and exports a clean
timestamped CSV — ready for device refresh planning, pre-enrollment cleanup,
or lifecycle audits.

No manual portal lookups. No clicking through Intune one device at a time.
Just drop in your serial numbers, run the script, get the report.

What you get:
- Production-ready PowerShell script (PS 5.1 compatible)
- Input via simple text file — no parameters, no prompts
- Bulk pull from Intune and Autopilot with full pagination
- Per-serial lookup across all three systems in one pass
- Duplicate detection for Intune, Autopilot, and Azure AD
- Azure AD permission handled gracefully — no script failure if not granted
- 25-column CSV with Verdict column per row
- Timestamped CSV, log file, and full PS transcript per run
- 429 Retry-After backoff — throttle-safe for large environments
- This README with setup instructions, troubleshooting, and Graph permissions

No external modules required. No interactive sign-in. PS 5.1 compatible.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Cross-system inventory: Intune + Autopilot + Azure AD in one report
- Serial number input via text file — supports comments and blank lines
- Bulk pull strategy — one API call per system, not one per device
- Duplicate detection in all three systems with clear Verdict labels
- Windows-filtered Intune pull — reduces payload in mixed-platform tenants
- Azure AD lookup optional — graceful NO PERMISSION handling
- Full pagination with 429 Retry-After backoff and jitter
- 25-column CSV with RecordType and Verdict per row
- PowerShell transcript captured per run for full audit trail
- $PSScriptRoot output — works from any folder without path changes
- No external modules — pure PowerShell 5.1

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Endpoint Engineers preparing for device refresh or re-enrollment
- IT Admins investigating duplicate device records across Microsoft systems
- Modern Workplace teams running pre-imaging or decommission audits
- Anyone who needs a fast, complete inventory of specific devices before
  making changes in Intune, Autopilot, or Azure AD

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Autopilot, Azure AD, Entra ID, Device Inventory, Serial Number,
PowerShell, Microsoft Graph API, Duplicate Devices, Device Lifecycle,
Endpoint Management, Modern Workplace, Device Audit, Pre-enrollment Cleanup,
Graph API PowerShell, DeviceManagementManagedDevices, windowsAutopilotDeviceIdentities,
Device.Read.All, Cross-system Inventory

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Get-DeviceInventoryBySerial.ps1 in any text editor or PowerShell ISE.
3. Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION block.
4. Create inputserialnumber.txt in the same folder — one serial per line.
5. Ensure your Azure AD App Registration has admin consent for:
     DeviceManagementManagedDevices.Read.All (required)
     DeviceManagementServiceConfig.Read.All  (required)
     Device.Read.All                         (optional)
6. Run from PowerShell 5.1 or later.
7. Review the console summary and generated CSV, log, and transcript files.
8. See TROUBLESHOOTING TIPS if you encounter any issues.

For questions or support, contact the author via the Gumroad product page.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script make any changes to devices?
A: No. Fully read-only. It only reads and reports.

Q: How many serial numbers can I process at once?
A: No hard limit in the script. Bulk pull strategy means API calls scale
   with tenant size, not input count. Tested on large environments.
   For very large input lists (500+), consider splitting into batches.

Q: Why is Device.Read.All optional?
A: Azure AD lookup is useful but not always permitted in all organisations.
   The script continues and marks Azure AD rows as NO PERMISSION rather
   than failing, so you still get Intune and Autopilot data.

Q: Does this work for non-Windows devices?
A: The Intune pull is filtered to Windows only by default. To include other
   platforms, remove the operatingSystem filter from the $IntuneUri variable.
   Autopilot is Windows-only by design (Microsoft limitation).

Q: What is the RecordIndex column?
A: Shows "1 of 1" for clean records. Shows "1 of 3", "2 of 3", "3 of 3"
   when duplicates are found — so you can see exactly how many records
   exist per serial in each system.

Q: What PowerShell version is required?
A: PowerShell 5.1 or later. No external modules required.

Q: Why does the script use the beta endpoint for Autopilot?
A: The Autopilot device identities endpoint
   (windowsAutopilotDeviceIdentities) is only available on the beta
   Graph API. The v1.0 endpoint does not expose this resource.

================================================================================
  End of README - Get-DeviceInventoryBySerial.ps1
  Author : Sethu Kumar B
================================================================================
