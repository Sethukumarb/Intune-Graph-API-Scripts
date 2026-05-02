================================================================================
  README - Get-UserDetailsByUPN.ps1
  Author : Sethu Kumar B
================================================================================

SCRIPT NAME
-----------
Get-UserDetailsByUPN.ps1

FOLDER NAME
-----------
Get-UserDetailsByUPN

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Fetches full user profile details from Azure AD / Entra ID via Microsoft
Graph API using User Principal Name (UPN) as the sole lookup key.

Use this script to bulk-resolve a list of UPNs to their full Entra ID profile
details — display name, department, job title, office location, account status,
company, usage location, address fields, and user GUID — in a single run.

Read-only — no changes made to any user, directory, or system.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Reads UPNs from UPNs.txt (same folder as script).
   Blank lines and # comment lines are ignored.
   Lines missing @ are skipped with a WARN.

2. Authenticates to Microsoft Graph API using Azure AD app credentials
   (client credentials flow — no user sign-in required).

3. For each UPN:
   - Queries Graph API v1.0 with exact $filter=userPrincipalName eq lookup.
   - Uses ConsistencyLevel: eventual + $count=true for reliable filter
     behaviour across all account types (member, guest, external).
   - Post-validates the match with PowerShell -ieq (case-insensitive exact).
   - On HTTP 429 throttle: reads Retry-After header, waits, retries once.
   - Marks result as FOUND, NOT FOUND, or ERROR per UPN.

4. Exports a 16-column CSV with full profile details per UPN.

5. Saves a timestamped log file alongside the CSV.

NO changes are made to any user object or directory record.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- UPNs.txt in the same folder as the script (one UPN per line)
- Azure AD App Registration with Tenant ID, Client ID, Client Secret
- Admin consent granted for required Graph API permission (see below)
- Network access to login.microsoftonline.com and graph.microsoft.com

--------------------------------------------------------------------------------
REQUIRED MICROSOFT GRAPH API PERMISSIONS
--------------------------------------------------------------------------------
Permission Type : Application (no user sign-in required)

Permission Name    Required For
-------------------+------------------------------------------------------------
User.Read.All      Search and read Azure AD / Entra ID user profiles

Admin Consent : Required.

--------------------------------------------------------------------------------
INPUT FILE FORMAT
--------------------------------------------------------------------------------
File name : UPNs.txt
Location  : Same folder as the script ($PSScriptRoot)

Format:
  - One UPN per line
  - Lines starting with # are treated as comments and ignored
  - Blank lines are ignored
  - Lines missing @ are skipped with a warning

Example:
  # Finance team devices
  john.doe@contoso.com
  jane.smith@contoso.com
  # admin@contoso.com   <- skipped

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1 - Create UPNs.txt in the script folder. Add one UPN per line.

Step 2 - Open Get-UserDetailsByUPN.ps1 in any text editor or PS ISE.

Step 3 - Fill in the CONFIGURATION block:

         $TenantID     = "your-tenant-id"
         $ClientID     = "your-client-id"
         $ClientSecret = "your-client-secret"

Step 4 - Open PowerShell 5.1 or later and run:
         .\Get-UserDetailsByUPN.ps1

Step 5 - Review the console output and generated CSV and log files.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console:
  - Per-UPN lookup result (FOUND / NOT FOUND / ERROR)
  - Display name, email, department shown inline for found users
  - Summary: total, found, not found, error counts

Files (saved to same folder as script):
  - UserDetailsByUPN_[Timestamp].csv
  - UserDetailsByUPN_[Timestamp].log

CSV Columns (16):
  InputUPN, LookupStatus,
  DisplayName, UserPrincipalName, Mail,
  Department, JobTitle, OfficeLocation,
  AccountEnabled,
  CompanyName, UsageLocation,
  Country, State, City, StreetAddress,
  UserId

--------------------------------------------------------------------------------
LOOKUP STATUS VALUES
--------------------------------------------------------------------------------
FOUND      - UPN matched in Entra ID. Full profile details exported.
NOT FOUND  - No user found for this UPN. All detail columns set to N/A.
ERROR      - Graph API error during lookup. All detail columns set to N/A.

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Script uses Graph API v1.0 (stable endpoint, not beta).

- ConsistencyLevel: eventual + $count=true is required for $filter on
  userPrincipalName to work reliably across member, guest, and external
  account types. The script sets these automatically.

- Post-validation with -ieq ensures no partial or near-match is returned
  even if the Graph API returns an unexpected result.

- 429 throttle handling: script reads the Retry-After response header,
  waits the specified time, and retries the request once automatically.

- 100ms delay between UPN lookups reduces throttling risk for large batches.

- All output columns default to "N/A" for NOT FOUND and ERROR rows so the
  CSV column structure remains consistent throughout.

- The script does not deduplicate input UPNs. If the same UPN appears
  multiple times in UPNs.txt, it will be looked up multiple times.
  Remove duplicates from the input file before running if needed.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Problem : Authentication fails immediately
Fix     : Verify TenantID, ClientID, ClientSecret. Check secret expiry
          in the Azure AD portal.

Problem : All UPNs return NOT FOUND
Fix     : Confirm User.Read.All admin consent is granted.
          Confirm UPNs are in the correct format (user@domain.com).
          Confirm the users exist in the tenant being queried.

Problem : Some UPNs return NOT FOUND unexpectedly
Fix     : Check for trailing spaces, typos, or wrong domain suffix in
          UPNs.txt. The lookup is an exact match — any deviation returns
          NOT FOUND.

Problem : Lines skipped with "not a valid UPN format - missing @"
Fix     : The input line does not contain @. Correct the UPN format in
          UPNs.txt.

Problem : 429 throttle errors persisting after retry
Fix     : The script retries once automatically. If throttling persists
          across many UPNs, add a longer Start-Sleep between lookups or
          split the input file into smaller batches.

Problem : Mail column shows N/A for found users
Fix     : Not all Entra ID accounts have a mail attribute set. The
          UserPrincipalName column will still contain the UPN. Mail
          is a separate attribute and may be empty by design.

Problem : CSV not created
Fix     : Check write permissions to the script folder ($PSScriptRoot).
          Review the log file for the exact error message.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Entra ID User Details by UPN – Bulk Lookup Report | PowerShell Script

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Resolve a list of UPNs to full Entra ID user profiles in one script run.

This PowerShell script reads a text file of User Principal Names, queries
Microsoft Graph API for each one using an exact UPN match, and exports a
clean 16-column CSV with display name, department, job title, office location,
account status, company, usage location, address, and user GUID.

Built for IT admins and endpoint engineers who regularly need to pull user
profile details in bulk — for audits, offboarding checks, helpdesk lookups,
or any workflow where you have a list of UPNs and need the full profile behind
each one.

What you get:
- Production-ready PowerShell script (PS 5.1 compatible)
- UPN input via simple text file — supports # comments and blank lines
- Exact UPN match with ConsistencyLevel: eventual for reliable results
- -ieq post-validation — no partial or near-match false positives
- 429 throttle handling with Retry-After auto-retry
- 16-column CSV covering full profile, location, account state, and GUID
- FOUND / NOT FOUND / ERROR status per UPN row
- Timestamped CSV and log file per run
- This README with setup, troubleshooting, and Graph permissions

No external modules. No interactive sign-in. PS 5.1 compatible.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Exact UPN lookup — $filter=userPrincipalName eq with -ieq post-validation
- ConsistencyLevel: eventual + $count=true — reliable across all account types
  including member, guest, and external accounts
- 429 Retry-After handling — reads header, waits, retries once automatically
- 16-column CSV — profile, department, location, address, account state, GUID
- FOUND / NOT FOUND / ERROR per row — every input UPN accounted for
- N/A defaults on all columns for non-found rows — consistent CSV structure
- # comment support in input file — annotate your UPN lists
- 100ms pacing between lookups — reduces throttling on large batches
- Timestamped output files — safe to run multiple times without overwriting
- Read-only — no changes made to any user or directory object
- No external modules — pure PowerShell 5.1 with Invoke-RestMethod

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- IT Admins bulk-resolving UPNs to user profiles for audit or compliance
- Endpoint Engineers checking user account status before device assignment
- Service Desk leads pulling department and job title for ticket routing
- HR / IT teams verifying user profile completeness during onboarding audits
- Anyone who has a list of UPNs and needs the full Entra ID profile behind each

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Entra ID, Azure AD, UPN, User Principal Name, User Details, PowerShell,
Microsoft Graph API, User.Read.All, Bulk User Lookup, User Profile,
Department, Job Title, AccountEnabled, Endpoint Management, Modern Workplace,
Graph v1.0, ConsistencyLevel, Intune, User Audit, Offboarding

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Get-UserDetailsByUPN.ps1 in any text editor or PowerShell ISE.
3. Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION block.
4. Ensure your Azure AD App Registration has admin consent for:
     User.Read.All (required)
5. Create UPNs.txt in the same folder — one UPN per line.
6. Run from PowerShell 5.1 or later.
7. Review the generated CSV and log file in the script folder.
8. See TROUBLESHOOTING TIPS if you encounter any issues.

For questions or support, contact the author via the Gumroad product page.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script modify any user accounts?
A: No. Fully read-only. GET requests only.

Q: Does it work for guest accounts?
A: Yes. ConsistencyLevel: eventual + $count=true ensures $filter works
   reliably for member, guest, and external account types.

Q: Can I look up a single UPN?
A: Yes. Put one UPN in UPNs.txt and run normally.

Q: Why does the Mail column show N/A for some found users?
A: Mail is a separate attribute from UPN and may not be set on all accounts.
   The UserPrincipalName column will always be populated for FOUND rows.

Q: What if the same UPN appears twice in the input file?
A: It will be looked up twice and appear twice in the CSV. Remove duplicates
   from UPNs.txt before running if this is a concern.

Q: What PowerShell version is required?
A: PowerShell 5.1 or later. No external modules required.

Q: Why use ConsistencyLevel: eventual?
A: Required for advanced Graph API filter queries ($filter with $count).
   Without it, $filter on userPrincipalName may fail or return incomplete
   results for certain account types in large tenants.

================================================================================
  End of README - Get-UserDetailsByUPN.ps1
  Author : Sethu Kumar B
================================================================================
