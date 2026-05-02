================================================================================
  README - Export-AutopilotDevices.ps1
================================================================================

SCRIPT NAME
-----------
Export-AutopilotDevices.ps1

FOLDER NAME
-----------
Export-AutopilotDevices

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Exports all Windows Autopilot device identities from Microsoft Intune via the
Microsoft Graph API (beta endpoint) to a CSV file. Designed for IT admins who
need a full inventory of Autopilot-registered devices without logging in
interactively. Uses app-only authentication (client credentials), supports
large environments via automatic pagination, and wipes all credentials from
memory after execution.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Authenticates to Microsoft Graph API using Client Credentials (no user login)
2. Fetches ALL Autopilot device identities from:
   https://graph.microsoft.com/beta/deviceManagement/windowsAutopilotDeviceIdentities
3. Handles OData pagination automatically (no device count limit)
4. Exports the following fields to a timestamped CSV file:
   - SerialNumber
   - AutopilotID
   - AzureADObjectID
   - GroupTag
   - DeploymentProfile
5. Writes a full structured log file (INFO / WARN / ERROR levels)
6. Captures a full transcript of the console session for audit
7. Securely wipes all credentials (TenantID, ClientID, ClientSecret, AccessToken)
   from memory after the script completes or fails

OUTPUT FILES
   - CSV        : <ScriptRoot>\AutopilotDevices_<timestamp>.csv
   - Log        : <ScriptRoot>\Logs\AutopilotExport_<timestamp>.log
   - Transcript : <ScriptRoot>\Logs\AutopilotExport_<timestamp>_Transcript.log

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- Windows PowerShell 5.1 or PowerShell 7+
- An Azure AD App Registration with a Client Secret
- Appropriate Microsoft Graph API permissions (see below)
- Network access to:
    login.microsoftonline.com
    graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH PERMISSIONS
--------------------------------------------------------------------------------
Permission                              Type        Purpose
---------------------------------------+-----------+---------------------------
DeviceManagementServiceConfig.Read.All  Application Read Autopilot device data

  > Application permission (not delegated) — no user sign-in required.
  > Must be granted Admin Consent in Azure AD.

HOW TO CONFIGURE:
  1. Go to Azure Portal > Azure Active Directory > App Registrations
  2. Create or select your App Registration
  3. Go to API Permissions > Add Permission > Microsoft Graph > Application
  4. Add: DeviceManagementServiceConfig.Read.All
  5. Click "Grant Admin Consent"
  6. Under Certificates & Secrets, create a Client Secret and copy the value

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1: Open the script file in a text editor or VS Code
Step 2: Fill in the three required values at the top of the script:

    $TenantID     = "your-tenant-id-here"
    $ClientID     = "your-client-id-here"
    $ClientSecret = "your-client-secret-here"

Step 3: Open PowerShell (Run as Administrator recommended)
Step 4: Navigate to the script folder:

    cd "C:\Path\To\Export-AutopilotDevices"

Step 5: Run the script:

    .\Export-AutopilotDevices.ps1

  > If execution policy blocks the script, run first:
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console: Timestamped log entries showing progress (token fetch, pagination, export)

CSV file example (AutopilotDevices_20251201_143022.csv):

  SerialNumber   | AutopilotID          | AzureADObjectID      | GroupTag | DeploymentProfile
  ---------------|----------------------|----------------------|----------+------------------
  ABC1234567     | xxxxxxxx-xxxx-xxxx.. | yyyyyyyy-yyyy-yyyy.. | Sales    | True
  XYZ9876543     | xxxxxxxx-xxxx-xxxx.. | yyyyyyyy-yyyy-yyyy.. | IT       | False

Log file: Full timestamped audit trail saved to .\Logs\

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Credentials are NEVER written to any log or transcript file
- ClientSecret is converted to SecureString immediately on load and disposed after use
- AccessToken is overwritten with garbage characters before being nulled
- GC.Collect() is called post-run to clear memory references
- The beta Graph endpoint is used — Microsoft may update or deprecate it
- Always test in a non-production tenant first
- Store the script file securely — it requires credential input before running

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
ISSUE: "Token request failed"
FIX  : Verify TenantID, ClientID, and ClientSecret are correct.
       Ensure Admin Consent is granted for the Graph permission.

ISSUE: "Page fetch failed" or empty CSV
FIX  : Check that the App Registration has DeviceManagementServiceConfig.Read.All
       and that Intune is licensed and active in your tenant.

ISSUE: Script execution blocked
FIX  : Run: Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

ISSUE: CSV is empty but no error shown
FIX  : Your tenant may have zero enrolled Autopilot devices. Verify in
       Intune > Devices > Windows > Windows Enrollment > Devices.

ISSUE: "Access Denied" (403) from Graph
FIX  : Admin Consent may not have been granted. Re-grant in Azure AD portal.

ISSUE: Log folder not created
FIX  : Run PowerShell as Administrator so the script can create the Logs folder.

================================================================================
  GUMROAD LISTING DETAILS
================================================================================

GUMROAD LISTING TITLE
---------------------
Export Windows Autopilot Devices to CSV — PowerShell Graph API Script

GUMROAD PRODUCT DESCRIPTION
-----------------------------
Automate your Windows Autopilot inventory export with this production-ready
PowerShell script. Connect to Microsoft Graph API using secure app-only
authentication and export all Autopilot device identities from Microsoft Intune
directly to a clean, timestamped CSV file — no manual work, no browser required.

Perfect for IT administrators, Microsoft 365 consultants, and Intune engineers
who need a fast, reliable, and auditable way to pull Autopilot device data at
scale.

Built with enterprise security in mind: credentials are never logged, secrets
are handled as SecureStrings, and all credential variables are wiped from memory
after every run.

KEY FEATURES
------------
- App-only authentication (no interactive user login required)
- Full OData pagination support — handles any number of devices
- Exports: SerialNumber, AutopilotID, AzureADObjectID, GroupTag, DeploymentProfile
- Timestamped CSV, structured log file, and full session transcript
- Secure credential wipe after every run (SecureString + GC cleanup)
- No third-party modules required — pure PowerShell + REST API
- Clean, well-commented code — easy to read and customize

WHO THIS SCRIPT IS FOR
----------------------
- IT Administrators managing Windows Autopilot in Microsoft Intune
- Microsoft 365 / Endpoint Management Consultants
- System Engineers needing automated device inventory exports
- MSPs managing multiple Intune tenants
- Organizations preparing for Autopilot audits or migrations

SUGGESTED TAGS / KEYWORDS
--------------------------
PowerShell, Microsoft Intune, Windows Autopilot, Graph API, CSV Export,
Device Inventory, Endpoint Management, Microsoft 365, Automation,
IT Admin Tools, Azure AD, Client Credentials, Intune Script,
Autopilot Devices, Device Management

BUYER INSTRUCTIONS
------------------
1. Download and extract the ZIP file
2. Open Export-AutopilotDevices.ps1 in any text editor or VS Code
3. Fill in your TenantID, ClientID, and ClientSecret at the top of the script
4. Run the script from PowerShell
5. CSV and logs are saved automatically in the same folder as the script
6. Full setup steps are included in this README.txt file

COMMON QUESTIONS / FAQ
-----------------------
Q: Do I need to install any PowerShell modules?
A: No. The script uses only built-in PowerShell cmdlets and direct REST API calls.

Q: Does this work with PowerShell 5.1 and PowerShell 7?
A: Yes. Compatible with both Windows PowerShell 5.1 and PowerShell 7+.

Q: Is my Client Secret stored anywhere?
A: No. The secret is converted to a SecureString immediately and wiped from
   memory after the token is obtained. It is never written to any file.

Q: Can this export devices from multiple tenants?
A: One tenant per run. To export from multiple tenants, update the credential
   variables and run again for each tenant.

Q: What if I have thousands of Autopilot devices?
A: The script handles pagination automatically. All devices are fetched
   regardless of count.

Q: Does this use the stable or beta Graph endpoint?
A: It uses the beta endpoint (graph.microsoft.com/beta) which provides full
   Autopilot device data. Monitor Microsoft's Graph changelog for any updates.

================================================================================
  Author  : Sethu Kumar B
  Version : 3.0
  Date    : December 2025
================================================================================
