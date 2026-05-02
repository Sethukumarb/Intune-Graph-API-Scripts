================================================================================
  README - Get-UserEmailByUsername.ps1
  Author : Sethu Kumar B
================================================================================

SCRIPT NAME
-----------
Get-UserEmailByUsername.ps1

FOLDER NAME
-----------
Get-UserEmailByUsername

--------------------------------------------------------------------------------
PURPOSE
--------------------------------------------------------------------------------
Resolves email addresses and full user profile details from Azure AD / Entra ID
for a list of usernames — accepting sAMAccountName prefix, full UPN, or display
name as input.

Use this script when you have a mixed list of usernames in any format and need
to resolve each one to their UPN, email, department, job title, and other
profile attributes from Entra ID.

Read-only — no changes made to any user, directory, or system.

--------------------------------------------------------------------------------
WHAT THE SCRIPT DOES
--------------------------------------------------------------------------------
1. Reads usernames from Usernames.txt (same folder as script).
   Blank lines and # comment lines are ignored.

2. Authenticates to Microsoft Graph API using Azure AD app credentials
   (client credentials flow — no user sign-in required).

3. For each username — two-pass exact lookup:

   Pass 1 — Exact UPN match
     $filter=userPrincipalName eq 'username'
     Handles full UPN (john.doe@contoso.com) and UPN-prefix (john.doe).
     Post-validated with PowerShell -ieq (case-insensitive exact match).

   Pass 2 — Exact displayName match
     $filter=displayName eq 'username'
     Handles display names (e.g. "John Doe", "Sethu Kumar B").
     Requires ConsistencyLevel: eventual — applied automatically.
     Post-validated with PowerShell -ieq.

   Both passes use $count=true + ConsistencyLevel: eventual for reliable
   Graph filter behaviour across all account types (member, guest, external).
   Script stops at the first pass that returns a validated result.

4. Returns result per username:
   FOUND          — one exact match, full profile exported
   MULTIPLE MATCH — more than one user shares the exact input; all rows exported
   NOT FOUND      — no match on either pass
   ERROR          — Graph API error during lookup

5. Exports a 17-column CSV with full profile details per username.

6. Saves a timestamped log file alongside the CSV.

NO changes are made to any user object or directory record.

--------------------------------------------------------------------------------
PREREQUISITES
--------------------------------------------------------------------------------
- PowerShell 5.1 or later
- Usernames.txt in the same folder as the script (one username per line)
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
File name : Usernames.txt
Location  : Same folder as the script ($PSScriptRoot)

Format:
  - One username per line — any mix of formats accepted
  - Lines starting with # are treated as comments and ignored
  - Blank lines are ignored

Accepted input formats (any combination in the same file):
  john.doe                  <- sAMAccountName / UPN prefix
  john.doe@contoso.com      <- full UPN
  John Doe                  <- display name (exact, any case)
  sethu kumar b             <- display name, lowercase — still matches

Example Usernames.txt:
  # Helpdesk ticket batch - April 2026
  john.doe
  jane.smith@contoso.com
  Sethu Kumar B
  # admin@contoso.com    <- this line skipped

Case behaviour:
  "sethu kumar b"  matches Display Name "Sethu Kumar B"  -> FOUND
  "Sethu Kumar"    does NOT match "Sethu Kumar B"         -> NOT FOUND
  Characters must be identical — only case is flexible.

--------------------------------------------------------------------------------
HOW TO RUN THE SCRIPT
--------------------------------------------------------------------------------
Step 1 - Create Usernames.txt in the script folder. Add one username per line.

Step 2 - Open Get-UserEmailByUsername.ps1 in any text editor or PS ISE.

Step 3 - Fill in the CONFIGURATION block:

         $TenantID     = "your-tenant-id"
         $ClientID     = "your-client-id"
         $ClientSecret = "your-client-secret"

Step 4 - Open PowerShell 5.1 or later and run:
         .\Get-UserEmailByUsername.ps1

Step 5 - Review the console output and generated CSV and log files.

--------------------------------------------------------------------------------
EXPECTED OUTPUT
--------------------------------------------------------------------------------
Console:
  - Per-username pass results (Pass 1 / Pass 2 outcome)
  - Final result per username: FOUND / MULTIPLE MATCH / NOT FOUND / ERROR
  - Display name and email shown inline for found users
  - Summary: total, found, multiple, not found, error counts

Files (saved to same folder as script):
  - UserEmailDetails_[Timestamp].csv
  - UserEmailDetails_[Timestamp].log

CSV Columns (17):
  InputUsername, MatchCount, LookupStatus,
  DisplayName, UserPrincipalName, Mail,
  Department, JobTitle, OfficeLocation,
  AccountEnabled, UserId,
  CompanyName, UsageLocation,
  Country, State, City, StreetAddress

--------------------------------------------------------------------------------
LOOKUP STATUS VALUES
--------------------------------------------------------------------------------
FOUND          - Exactly one match. Full profile exported.
MULTIPLE MATCH - More than one user shares the exact input string.
                 All matching rows are exported so you can identify the right one.
NOT FOUND      - No user matched on either pass. All detail columns = N/A.
ERROR          - Graph API error during lookup. All detail columns = N/A.

--------------------------------------------------------------------------------
IMPORTANT NOTES
--------------------------------------------------------------------------------
- Script uses Graph API v1.0 (stable, not beta).

- ConsistencyLevel: eventual + $count=true is required for $filter on
  displayName to work reliably in Entra ID. Without it, Graph returns empty
  results even when the user exists. The script sets these automatically.

- -ieq post-validation is applied after every Graph response to guarantee
  character-exact, case-insensitive matching. Prevents partial or fuzzy
  results from Graph returning unexpected records.

- MULTIPLE MATCH is rare but possible when two users share the same exact
  display name in the same tenant. All rows are exported with
  LookupStatus = MULTIPLE MATCH and MatchCount = N so you can identify
  the correct user.

- 429 throttle handling: reads Retry-After response header, waits specified
  time, retries once automatically.

- 100ms delay between username lookups reduces throttling on large batches.

- All output columns default to "N/A" for NOT FOUND and ERROR rows so the
  CSV column structure remains consistent throughout.

- Script does not deduplicate input usernames. Same username appearing
  multiple times in Usernames.txt will be looked up multiple times.

--------------------------------------------------------------------------------
TROUBLESHOOTING TIPS
--------------------------------------------------------------------------------
Problem : Authentication fails immediately
Fix     : Verify TenantID, ClientID, ClientSecret. Check secret expiry
          in the Azure AD portal.

Problem : All usernames return NOT FOUND
Fix     : Confirm User.Read.All admin consent is granted.
          Confirm usernames exist in the tenant being queried.
          Check for extra spaces or special characters in Usernames.txt.

Problem : Display name input returns NOT FOUND but user exists
Fix     : The display name must match exactly — all characters, only case
          is flexible. Check for middle names, suffixes, or punctuation
          differences. Use the UPN format instead for reliable results.

Problem : UPN prefix (john.doe) returns NOT FOUND
Fix     : Pass 1 tries $filter=userPrincipalName eq 'john.doe'. If the
          tenant uses a non-standard domain suffix or the UPN prefix alone
          does not match, try the full UPN (john.doe@contoso.com) instead.

Problem : MULTIPLE MATCH returned for a display name
Fix     : Expected when two or more users share an identical display name.
          All matching rows are in the CSV. Use the UPN or UserId column
          to identify the correct user.

Problem : Mail column shows N/A for found users
Fix     : Mail is separate from UPN and may not be set on all accounts.
          UserPrincipalName will still be populated for FOUND rows.

Problem : 429 throttle errors persisting after retry
Fix     : Script retries once automatically. For large batches, increase
          the Start-Sleep delay in the foreach loop or split Usernames.txt
          into smaller batches.

Problem : CSV not created
Fix     : Check write permissions to the script folder ($PSScriptRoot).
          Review the log file for the exact error message.

--------------------------------------------------------------------------------
GUMROAD LISTING TITLE
--------------------------------------------------------------------------------
Entra ID User Email & Profile Lookup by Username | PowerShell Script

--------------------------------------------------------------------------------
GUMROAD PRODUCT DESCRIPTION
--------------------------------------------------------------------------------
Resolve any username to a full Entra ID user profile — regardless of format.

This PowerShell script accepts sAMAccountName prefixes, full UPNs, and display
names in the same input file and resolves each one to email, department, job
title, office location, account status, company, address, and user GUID via
Microsoft Graph API.

Two-pass exact lookup with ConsistencyLevel: eventual and -ieq post-validation
ensures accurate results across all account types — members, guests, and
external users — with no partial or fuzzy matches.

Built for IT admins and endpoint engineers who work with mixed username formats
and need a reliable, bulk-ready way to get full user profile details from Entra
ID without manual portal lookups.

What you get:
- Production-ready PowerShell script (PS 5.1 compatible)
- Accepts sAMAccountName, full UPN, and display name — any mix in one file
- Two-pass exact lookup: UPN first, displayName second
- ConsistencyLevel: eventual + -ieq post-validation — no false positives
- MULTIPLE MATCH handling — all rows returned when names collide
- 17-column CSV covering full profile, location, account state, and GUID
- FOUND / MULTIPLE MATCH / NOT FOUND / ERROR status per row
- 429 Retry-After auto-retry
- Timestamped CSV and log file per run
- This README with setup, troubleshooting, and Graph permissions

No external modules. No interactive sign-in. PS 5.1 compatible.

--------------------------------------------------------------------------------
KEY FEATURES
--------------------------------------------------------------------------------
- Flexible input — sAMAccountName prefix, full UPN, or display name accepted
- Two-pass exact lookup: Pass 1 UPN eq, Pass 2 displayName eq
- ConsistencyLevel: eventual + $count=true — reliable for all account types
- -ieq post-validation — character-exact, case-insensitive, no fuzzy matches
- MULTIPLE MATCH — all rows exported when more than one user shares the input
- MatchCount column — shows how many users matched per input row
- 17-column CSV — profile, department, location, address, account state, GUID
- All status values: FOUND / MULTIPLE MATCH / NOT FOUND / ERROR
- N/A defaults for non-found rows — consistent CSV structure throughout
- 429 Retry-After handling — reads header, waits, retries once
- 100ms pacing between lookups — reduces throttling on large batches
- # comment support in input file — annotate your username lists
- Read-only — no changes made to any user or directory object
- No external modules — pure PowerShell 5.1

--------------------------------------------------------------------------------
WHO THIS SCRIPT IS FOR
--------------------------------------------------------------------------------
- IT Admins resolving mixed-format username lists to full Entra profiles
- Endpoint Engineers looking up user email before device assignment
- Service Desk leads identifying users from sAMAccountName or display name
- HR / IT teams running bulk user profile checks for onboarding or audit
- Anyone who has a list of usernames in any format and needs the email and
  profile behind each one

--------------------------------------------------------------------------------
SUGGESTED TAGS / KEYWORDS
--------------------------------------------------------------------------------
Entra ID, Azure AD, Username Lookup, sAMAccountName, Display Name, UPN,
Email Lookup, PowerShell, Microsoft Graph API, User.Read.All,
Bulk User Lookup, User Profile, Department, AccountEnabled,
ConsistencyLevel, Graph v1.0, Intune, Modern Workplace, User Audit,
Endpoint Management

--------------------------------------------------------------------------------
BUYER INSTRUCTIONS
--------------------------------------------------------------------------------
1. Download and extract the ZIP file.
2. Open Get-UserEmailByUsername.ps1 in any text editor or PowerShell ISE.
3. Fill in TenantID, ClientID, and ClientSecret in the CONFIGURATION block.
4. Ensure your Azure AD App Registration has admin consent for:
     User.Read.All (required)
5. Create Usernames.txt in the same folder — one username per line.
   Mix of sAMAccountName, full UPN, and display name all accepted.
6. Run from PowerShell 5.1 or later.
7. Review the generated CSV and log file in the script folder.
8. See TROUBLESHOOTING TIPS if you encounter any issues.

For questions or support, contact the author via the Gumroad product page.

--------------------------------------------------------------------------------
FREQUENTLY ASKED QUESTIONS
--------------------------------------------------------------------------------
Q: Does this script modify any user accounts?
A: No. Fully read-only. GET requests only.

Q: What input formats are accepted?
A: Any mix of: sAMAccountName prefix (john.doe), full UPN
   (john.doe@contoso.com), or exact display name (John Doe).
   All three can appear in the same Usernames.txt file.

Q: How is this different from Get-UserDetailsByUPN.ps1?
A: Get-UserDetailsByUPN accepts only full UPNs. This script additionally
   accepts sAMAccountName prefixes and display names — useful when you
   have a mixed or incomplete list of user identifiers.

Q: What happens when two users share the same display name?
A: Both rows are exported with LookupStatus = MULTIPLE MATCH and
   MatchCount = 2 (or more). Use the UPN or UserId column to identify
   the correct user.

Q: Does it work for guest accounts?
A: Yes. ConsistencyLevel: eventual + $count=true ensures $filter works
   reliably for member, guest, and external account types.

Q: Can I look up a single username?
A: Yes. Put one username in Usernames.txt and run normally.

Q: Why use ConsistencyLevel: eventual?
A: Required for advanced Graph filter queries including $filter on
   displayName. Without it, Graph returns empty results for displayName
   lookups even when the user exists.

Q: What PowerShell version is required?
A: PowerShell 5.1 or later. No external modules required.

================================================================================
  End of README - Get-UserEmailByUsername.ps1
  Author : Sethu Kumar B
================================================================================
