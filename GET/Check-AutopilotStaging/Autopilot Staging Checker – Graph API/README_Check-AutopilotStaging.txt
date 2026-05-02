================================================================================
  README - Check-AutopilotStaging.ps1
  Author : Sethu Kumar B
================================================================================

SCRIPT NAME
-----------
Check-AutopilotStaging.ps1

FOLDER NAME
-----------
Check-AutopilotStaging

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Read-only safety check for the Windows Autopilot staging queue in Microsoft
Intune via the Microsoft Graph API (beta endpoint).

Use this script BEFORE re-importing devices to confirm that no stale staging
records remain in importedWindowsAutopilotDeviceIdentities. Stale records
cause error 806 / ZtdDeviceAlreadyAssigned during re-import.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Authenticates to Microsoft Graph API using Azure AD app credentials
   (client credentials flow - no user sign-in required).

2. Fetches ALL records from the Autopilot staging endpoint with pagination
   support (handles environments with 1000+ staged devices).

3. Parses each record for:
   - Serial number
   - Import status (unknown / pending / complete / error / completedWithError)
   - Error code and error name (if applicable)
   - Device registration ID
   - Created date/time
   - Group tag

4. Displays colour-coded console output per record:
   - GREEN  = complete
   - YELLOW = pending / unknown
   - RED    = error / completedWithError

5. Prints a staging summary (count by status category).

6. Warns if any records are present that could block re-import.

7. Exports all results to a timestamped CSV file in the script directory.

8. Writes a timestamped log file alongside the CSV.

NO changes are made to any device or Autopilot record. This is a read-only
operation.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- TLS 1.2 enabled (script sets this automatically)
- Azure AD App Registration with:
    - Client ID
    - Client Secret
    - Tenant ID
- Admin consent granted for required Graph API permission (see below)
- Network access to:
    - login.microsoftonline.com
    - graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission Type : Application (no user sign-in required)
Permission Name : DeviceManagementServiceConfig.ReadWrite.All
Admin Consent   : Required

Note: ReadWrite permission is required by the beta staging endpoint even
though this script performs read operations only.

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1 - Open the script file:
         Check-AutopilotStaging.ps1

Step 2 - Fill in your credentials in the CONFIGURATION block at the top:

         $TenantID     = "your-tenant-id"
         $ClientID     = "your-client-id"
         $ClientSecret = "your-client-secret"

Step 3 - Open PowerShell 5.1 or later.

Step 4 - Navigate to the script folder:
         cd "C:\Path\To\Check-AutopilotStaging"

Step 5 - Run the script:
         .\Check-AutopilotStaging.ps1

Step 6 - Review the console output and check the generated CSV and log files.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console:
  - Colour-coded status per device (serial number + import status + error info)
  - Staging summary (count by status)
  - Warning message if any records are present
  - File paths for CSV and log

Files (saved to same folder as the script):
  - AutopilotStagingCheck_YYYYMMDD_HHmmss.csv
  - AutopilotStagingCheck_YYYYMMDD_HHmmss.log

CSV Columns:
  SerialNumber, ImportedDeviceID, GroupTag, ImportStatus,
  ErrorCode, ErrorName, RegistrationID, CreatedDateTime

--------------------------------------------------------------------------------
IMPORT STATUS VALUES
--------------------------------------------------------------------------------
unknown            - Record exists but not yet processed
pending            - Queued, processing has not started
complete           - Successfully imported into Autopilot
error              - Import failed (check ErrorCode and ErrorName)
completedWithError - Partial success with errors

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- This script is READ-ONLY. No changes are made to any Autopilot records.

- A non-empty staging queue does NOT always mean re-import will fail.
  Records with status "complete" may still auto-purge by Graph after some time.
  However, any record present is a potential blocker.

- Wait for Graph to auto-purge staging records, OR manually delete stale
  records via Intune admin center before re-importing.

- The beta Graph endpoint is used as the v1.0 endpoint does not expose
  the staging queue.

- Run this script as a scheduled check before any bulk Autopilot re-import
  or hash upload operation.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Problem : Authentication fails (exit 1 immediately)
Fix     : Verify TenantID, ClientID, and ClientSecret are correct.
          Confirm the app registration exists and the secret has not expired.

Problem : 0 records returned but you expect staged devices
Fix     : Check that admin consent is granted for
          DeviceManagementServiceConfig.ReadWrite.All.
          Confirm devices were recently imported via hash upload.

Problem : CSV not created
Fix     : Verify the script has write permission to its folder.
          Check the log file for the exact error message.

Problem : Error 806 / ZtdDeviceAlreadyAssigned still occurs after clean staging
Fix     : The device may already be registered in Autopilot (not staging).
          Use the Intune portal to check existing Autopilot device records
          and delete the duplicate before re-importing.

Problem : "Page fetch failed" in console
Fix     : Intermittent Graph API throttling. Re-run the script. If the issue
          persists, check network access to graph.microsoft.com.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Autopilot Staging Checker – Microsoft Graph API PowerShell Script

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Avoid failed Autopilot imports before they happen.

This PowerShell script connects to the Microsoft Graph API and performs a
complete read-only audit of your Windows Autopilot staging queue
(importedWindowsAutopilotDeviceIdentities). It checks every record currently
sitting in the staging endpoint, reports their import status, error codes, and
flags any stale records that could trigger error 806 or
ZtdDeviceAlreadyAssigned during your next re-import.

Run it in under a minute before any Autopilot hash upload or re-import
operation. No changes are made — it only reads and reports.

What you get:
- Production-ready PowerShell script (PS 5.1 compatible)
- Colour-coded console output per device
- Timestamped CSV export with full staging details
- Timestamped log file for audit trail
- Handles large environments with built-in pagination (1000+ records)
- This README with setup instructions, troubleshooting, and Graph permissions

Built for IT admins and Endpoint Engineers who manage Windows Autopilot
at scale and need a fast, reliable pre-import safety check.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Read-only - no changes made to any device or Autopilot record
- Full pagination - handles environments with 1000+ staged devices
- Colour-coded console output (green/yellow/red per status)
- Staging summary with counts by status category
- Clear warning when records are present that may block re-import
- Timestamped CSV and log files saved to script directory
- Uses $PSScriptRoot - works from any folder without path changes
- Client credentials auth - no interactive sign-in required
- PowerShell 5.1 compatible - no external modules needed

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Endpoint Engineers managing Windows Autopilot deployments
- IT Admins handling device re-imports or Autopilot hash uploads
- Modern Workplace teams troubleshooting error 806 / ZtdDeviceAlreadyAssigned
- Anyone who needs a fast, read-only staging queue audit before bulk imports

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Intune, Windows Autopilot, PowerShell, Microsoft Graph API, Autopilot Staging,
importedWindowsAutopilotDeviceIdentities, Error 806, ZtdDeviceAlreadyAssigned,
Endpoint Management, Modern Workplace, Device Import, Graph Beta,
Autopilot Troubleshooting, Intune Automation, DeviceManagementServiceConfig

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Check-AutopilotStaging.ps1 in any text editor or PowerShell ISE.
3. Fill in your TenantID, ClientID, and ClientSecret in the CONFIGURATION block.
4. Ensure your Azure AD App Registration has admin consent for:
   DeviceManagementServiceConfig.ReadWrite.All (Application permission).
5. Run the script from PowerShell 5.1 or later.
6. Review the console output and the generated CSV and log files.
7. See the TROUBLESHOOTING TIPS section if you encounter any issues.

For questions or support, contact the author via the Gumroad product page.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script delete or modify any Autopilot records?
A: No. It is fully read-only. It only reads and reports staging records.

Q: Why does it need ReadWrite permission if it is read-only?
A: The Graph beta staging endpoint requires ReadWrite permission by design,
   even for GET operations. This is a Microsoft API requirement, not the script.

Q: Can I run this in a large environment with thousands of devices?
A: Yes. The script uses pagination ($top=1000 per page) to retrieve all records
   regardless of total count.

Q: How long before Graph auto-purges staging records?
A: Microsoft does not publish a guaranteed SLA. In practice, records with
   "complete" status are typically purged within minutes to a few hours.
   For "error" or "pending" records, manual deletion may be required.

Q: What PowerShell version is required?
A: PowerShell 5.1 or later. No external modules required.

Q: Can this be run as a scheduled task or automation?
A: Yes. It uses client credentials (non-interactive) and exits automatically.
   Store credentials securely (e.g., Azure Key Vault) before scheduling.

================================================================================
  End of README - Check-AutopilotStaging.ps1
  Author : Sethu Kumar B
================================================================================
