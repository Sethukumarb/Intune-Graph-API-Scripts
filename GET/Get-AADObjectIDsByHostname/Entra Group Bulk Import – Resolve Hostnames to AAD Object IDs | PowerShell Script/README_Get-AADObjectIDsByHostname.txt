================================================================================
  README - Get-AADObjectIDsByHostname.ps1
  Author : Sethu Kumar B
================================================================================

SCRIPT NAME
-----------
Get-AADObjectIDsByHostname.ps1

FOLDER NAME
-----------
Get-AADObjectIDsByHostname

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Resolves a list of device hostnames to their Azure AD Object IDs and Intune
Device IDs — and produces a ready-to-upload BulkImport TXT file for adding
devices to an Entra ID static group via the Bulk Add Members flow.

Use this script when you need to add a batch of devices to an Entra group
and only have their hostnames. The script does the lookup for you, flags
duplicates, and outputs the Object ID list in the exact format the Entra
portal Bulk Import expects.

Read-only — no changes made to any device, group, or directory object.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Reads hostnames from DeviceList.txt (same folder as script).
   Blank lines are ignored. Hostnames are deduplicated and sorted.

2. Authenticates to Microsoft Graph API using Azure AD app credentials
   (client credentials flow — no user sign-in required).

3. For each hostname:
   a. Searches Azure AD for ALL device objects where displayName eq hostname.
   b. Searches Intune for ALL managed device records where deviceName eq hostname.
   c. Cross-references each Azure AD object to its matching Intune record
      using deviceId / azureADDeviceId.
   d. Flags duplicates if more than one Azure AD object is found per hostname.

4. Builds one CSV row per Azure AD object found per hostname.
   Not-found hostnames get a placeholder row with FoundInAAD = NO.

5. Exports a full 23-column CSV report with all device details.

6. Exports a BulkImport TXT file — one Azure AD Object ID per line —
   ready to upload directly into the Entra portal Bulk Add Members flow.

7. Prints a console summary and saves a timestamped log file.

NO changes are made to any Azure AD, Intune, or Entra group record.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- DeviceList.txt in the same folder as the script (one hostname per line)
- Azure AD App Registration with Tenant ID, Client ID, Client Secret
- Admin consent granted for required Graph API permissions (see below)
- Network access to login.microsoftonline.com and graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission Type : Application (no user sign-in required)

Permission Name                          Required For
----------------------------------------+--------------------------------------
Device.Read.All                          Search Azure AD device objects
DeviceManagementManagedDevices.Read.All  Search Intune managed device records

Admin Consent : Required for both permissions.

--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File name : DeviceList.txt
Location  : Same folder as the script ($PSScriptRoot)

Format:
  - One hostname per line
  - Blank lines are ignored
  - Duplicates are removed automatically

Example:
  WDAP-5k2ChJSOHb
  WDAP-VegpHYqeeM
  WDAP-LT-00142

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1 - Create DeviceList.txt in the script folder.
         Add one hostname per line.

Step 2 - Open Get-AADObjectIDsByHostname.ps1 in any text editor or PS ISE.

Step 3 - Fill in the CONFIGURATION block:

         $TenantID     = "your-tenant-id"
         $ClientID     = "your-client-id"
         $ClientSecret = "your-client-secret"

         Optionally set $OutputFolder to a custom path.
         Leave blank to save all output to the script folder.

Step 4 - Open PowerShell 5.1 or later and run:
         .\Get-AADObjectIDsByHostname.ps1

Step 5 - Review the console summary and generated output files.

Step 6 - Review the CSV for duplicates before using the BulkImport TXT.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console:
  - Per-hostname search results (FOUND / NOT FOUND / DUPLICATE warning)
  - Azure AD Object ID, Intune Device ID, serial, user, last sync per device
  - Summary: clean count, duplicate count, not-found count, total Object IDs

Files (saved to $PSScriptRoot or $OutputFolder if set):
  - Get-AADObjectIDsByHostname_[Timestamp].csv
  - Get-AADObjectIDsByHostname_[Timestamp]_BulkImport.txt
  - Get-AADObjectIDsByHostname_[Timestamp].log

CSV Columns (23):
  Hostname, AADObjectID, AADDeviceID, IntuneDeviceID,
  SerialNumber, PrimaryUser, EnrolledDate, LastSync,
  DaysSinceSync, OS, OSVersion, ComplianceState,
  ManagementState, OwnerType, AccountEnabled, TrustType,
  RegisteredDate, LastActivity,
  IsDuplicate, AADObjectCount, FoundInAAD, FoundInIntune, Notes

BulkImport TXT:
  One Azure AD Object ID per line. Upload directly to Entra portal.
  If duplicates exist, all Object IDs are included — review CSV first.

--------------------------------------------------------------------------------
HOW TO USE THE BULKIMPORT TXT
--------------------------------------------------------------------------------
1. Open the Entra portal (entra.microsoft.com).
2. Navigate to: Groups → your target group → Members.
3. Click "Bulk Add Members".
4. Upload the _BulkImport.txt file generated by this script.
5. Review the preview and confirm.

IMPORTANT: If any hostname returned duplicate Azure AD objects, all their
Object IDs are included in the BulkImport TXT. Review the CSV IsDuplicate
column and manually remove any unwanted Object IDs from the TXT before
uploading.

--------------------------------------------------------------------------------
CSV NOTES COLUMN VALUES
--------------------------------------------------------------------------------
OK - single entry, linked to Intune
  Clean result. One AAD object found, linked to an Intune record.

DUPLICATE - N AAD objects share this hostname
  More than one Azure AD object found. All included in CSV and BulkImport TXT.
  Review before uploading.

AAD object exists but no matching Intune record found
  Device is in Azure AD but not managed by Intune, or azureADDeviceId
  does not match (e.g. stale or unmanaged device).

Hostname not found in Azure AD - cannot add to group
  No Azure AD object found for this hostname. FoundInAAD = NO.
  Device cannot be added to an Entra group — investigate separately.

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Script is READ-ONLY. No changes made to any group, device, or directory.

- The BulkImport TXT contains raw Azure AD Object IDs — one per line.
  This is the exact format required by the Entra portal Bulk Add Members.

- A 200ms delay is added between hostname lookups to reduce throttling risk.

- If $OutputFolder is left blank, all output files are saved to the same
  folder as the script ($PSScriptRoot). The folder is created automatically
  if it does not exist.

- Serial number is extracted from the Azure AD physicalIds array
  ([SerialNumber] tag). Falls back to Intune serialNumber if not present
  in Azure AD. Falls back to empty if neither is available.

- DaysSinceSync shows "Never" if the device has never synced with Intune.

- AccountEnabled and TrustType from Azure AD are included to help identify
  stale or non-compliant objects before bulk import.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Problem : Authentication fails immediately
Fix     : Verify TenantID, ClientID, ClientSecret. Check secret expiry
          in the Azure AD portal.

Problem : All hostnames return NOT FOUND in Azure AD
Fix     : Confirm Device.Read.All admin consent is granted.
          Confirm hostnames match the displayName in Azure AD exactly
          (case-insensitive, but spacing and special characters must match).

Problem : FoundInIntune = NO for devices that exist in Intune
Fix     : Confirm DeviceManagementManagedDevices.Read.All admin consent
          is granted. Also check if the device is enrolled — unmanaged
          Azure AD registered devices will not appear in Intune.

Problem : Duplicate rows in CSV and BulkImport TXT
Fix     : Expected behaviour — the script surfaces all AAD objects per
          hostname. Review IsDuplicate = YES rows in the CSV, identify
          the correct Object ID, and remove unwanted IDs from the TXT
          before uploading to Entra.

Problem : BulkImport TXT upload fails in Entra portal
Fix     : Ensure the TXT file contains only Object IDs — one per line,
          no headers, no blank lines, UTF-8 encoding. The script produces
          this format automatically. Re-check for any manual edits that
          may have introduced formatting issues.

Problem : Notes column shows "AAD object exists but no matching Intune record"
Fix     : The device may be Azure AD registered but not Intune enrolled.
          Or the azureADDeviceId on the Intune record does not match the
          deviceId on the Azure AD object (stale cross-reference).
          The Object ID is still valid for group membership — Intune linkage
          is informational only.

Problem : CSV not created
Fix     : Check $OutputFolder path and write permissions.
          Review the log file for the exact error.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Entra Group Bulk Import – Resolve Hostnames to AAD Object IDs | PowerShell Script

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Turn a list of device hostnames into a ready-to-upload Entra group Bulk Import
file — in one script run.

When you need to add devices to an Entra ID static group and only have their
computer names, this PowerShell script does the resolution for you. It searches
Azure AD and Intune for each hostname, cross-references the records, flags
duplicates, and outputs two files: a full detail CSV and a BulkImport TXT
with one Azure AD Object ID per line — exactly what the Entra portal Bulk
Add Members flow expects.

No manual Object ID lookups. No clicking through the portal per device.
Drop in your hostname list, run the script, upload the TXT.

What you get:
- Production-ready PowerShell script (PS 5.1 compatible)
- Hostname input via simple text file — no parameters, no prompts
- Azure AD search + Intune cross-reference per hostname
- Duplicate detection — all AAD objects per hostname surfaced and flagged
- 23-column CSV with compliance state, last sync, serial, primary user
- Ready-to-upload BulkImport TXT for Entra portal Bulk Add Members
- Not-found hostnames clearly flagged in CSV with Notes column
- Timestamped CSV, BulkImport TXT, and log file per run
- This README with setup, troubleshooting, and Graph permissions

No external modules. No interactive sign-in. PS 5.1 compatible.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Resolves hostnames to Azure AD Object IDs via Graph API v1.0
- Cross-references each AAD object to its Intune managed device record
- Duplicate detection — flags and includes all AAD objects per hostname
- BulkImport TXT output — one Object ID per line, ready for Entra portal
- 23-column CSV with full device context per resolved object
- Serial number extracted from AAD physicalIds array with Intune fallback
- DaysSinceSync calculated per device for quick stale-device identification
- Notes column explains every row result (OK / DUPLICATE / NOT FOUND)
- AccountEnabled and TrustType included for pre-import object health check
- 200ms pacing between lookups — reduces throttling risk
- $OutputFolder configurable — or defaults to script folder
- Read-only — no changes made to any group, device, or directory object
- No external modules — pure PowerShell 5.1

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- Intune / Endpoint Engineers adding device batches to Entra static groups
- IT Admins who need Azure AD Object IDs from a hostname list quickly
- Modern Workplace teams managing device group membership at scale
- Anyone using the Entra portal Bulk Add Members flow for device groups

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Azure AD, Entra ID, Object ID, Bulk Import, Static Group, Hostname Lookup,
PowerShell, Microsoft Graph API, Device.Read.All, Intune, Group Membership,
Endpoint Management, Modern Workplace, AAD Object ID, Bulk Add Members,
deviceManagement, Cross-reference, Duplicate Detection, Entra Group

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Get-AADObjectIDsByHostname.ps1 in any text editor or PowerShell ISE.
3. Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION block.
4. Optionally set $OutputFolder. Leave blank to save to the script folder.
5. Ensure your Azure AD App Registration has admin consent for:
     Device.Read.All                         (required)
     DeviceManagementManagedDevices.Read.All (required)
6. Create DeviceList.txt in the same folder — one hostname per line.
7. Run from PowerShell 5.1 or later.
8. Review the CSV for duplicates before using the BulkImport TXT.
9. Upload the _BulkImport.txt to Entra portal → Groups → Bulk Add Members.
10. See TROUBLESHOOTING TIPS if you encounter any issues.

For questions or support, contact the author via the Gumroad product page.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script add devices to any group?
A: No. Fully read-only. It only resolves and reports Object IDs.
   You upload the BulkImport TXT to Entra manually.

Q: What format does the Entra Bulk Add Members upload expect?
A: One Azure AD Object ID per line, UTF-8 encoded, no headers.
   The _BulkImport.txt file produced by this script matches this format.

Q: What if a hostname has two Azure AD objects?
A: Both Object IDs are included in the CSV (IsDuplicate = YES) and in the
   BulkImport TXT. Review the CSV to identify the correct object, then
   manually remove the unwanted ID from the TXT before uploading.

Q: Can I use this for user objects or only devices?
A: Devices only. The script searches Azure AD devices endpoint and the
   Intune managedDevices endpoint. User objects are not in scope.

Q: What does FoundInIntune = NO mean?
A: The device has an Azure AD object but no matching Intune managed device
   record. The Object ID is still valid for Entra group membership.

Q: How many hostnames can I process at once?
A: No hard limit in the script. Each hostname makes two API calls
   (AAD + Intune). For large batches (200+ hostnames) run during off-peak
   hours to reduce throttling risk.

Q: What PowerShell version is required?
A: PowerShell 5.1 or later. No external modules required.

================================================================================
  End of README - Get-AADObjectIDsByHostname.ps1
  Author : Sethu Kumar B
================================================================================
