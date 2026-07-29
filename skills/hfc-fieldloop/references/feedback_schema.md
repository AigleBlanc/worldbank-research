# Feedback schema

Collaboration surface: **two Excel files in a folder inside the runner's own individual OneDrive for Business** (see `assets/lib/onedrive.json`) plus local twin `hfc/output/feedback_sheet.xlsx`. No SharePoint site or Team is needed — whoever runs the pipeline connects it to their own account.

| File | Key in `onedrive.json` | Who edits |
|---|---|---|
| **Main** | `main_file` | Field team (`field_comment`, `proposed_fix`) |
| **Audit** | `audit_file` | Code mid-process (`status`, `resolved`, …) |

One row per finding / data-collection unit as appropriate. **Confirm schema with the user once** at build (AskUserQuestion: keep / modify; Other automatic) before writing the OneDrive files or the local twin.

## Required columns

| column | values / notes |
|---|---|
| finding_id | stable id from findings |
| submission_id | unique data-collection id (student/hh/interview id) |
| issue | plain-English issue label |
| field_comment | field team text |
| proposed_fix | field team proposed solution |
| **status** | `Open` \| `accepted` \| `revise` — default **`Open`** (capital O). Replaces legacy `ra_status`. |
| resolved | `No` \| `yes` \| `partial` — default **`No`** (capital N). Post-feedback pipeline updates. |
| initials | RA or field initials |
| date_updated | ISO date |

**Removed from feedback twin:** `check_module` (kept only on internal `findings` for the HTML report).

## Optional columns

`school_id`, `enumerator`, `key`, `value`, `notes`

## Config

1. Defaults under `hfc-fieldloop/assets/lib/`:
   - `onedrive.json` — ships `"enabled": false` (not yet set up)
   - `onedrive.example.json` — copy template into project config, e.g.:
     ```json
     {
       "enabled": true,
       "folder_path": "HFC Reports",
       "main_file": "feedback_main.xlsx",
       "audit_file": "feedback_audit.xlsx"
     }
     ```
2. **Real config:** project `hfc/config/onedrive.json` with `"enabled": true` (required for OneDrive sync).
   Loader preference: `hfc/config/onedrive.json` → legacy `config/onedrive.json` → `assets/lib/onedrive.json` (first with `enabled: true` wins; otherwise → local twin / `--no-onedrive`). There's no site/tenant URL to configure — `Microsoft365R::get_business_onedrive()` connects to whichever account signs in.
3. **Auth:** delegated, one-time interactive sign-in — no secrets stored in this package (unlike the old Google service-account key). Run `Rscript scripts/onedrive_auth_setup.R` **once, yourself, in a normal interactive R/RStudio session** — this cannot be done from inside a non-interactive Claude-Code-driven run. `Microsoft365R`/`AzureAuth` then cache the token locally and refresh it silently on every later run. This connects to the runner's own OneDrive — no SharePoint site or Team needs to exist.
4. Share the OneDrive **folder** (not the individual files) with collaborators via the normal OneDrive "Specific people" sharing UI, once, before relying on this — the code never mints its own share links, it just uploads into whatever folder access has already been configured.
5. `hfc/project.yaml` stores `feedback_main_url` / `feedback_audit_url` (the uploaded files' OneDrive URLs) plus `report_onedrive_url` (the report's own URL). Local Excel remains fallback if OneDrive auth missing.

## Local twin

Always also written regardless of OneDrive status:

- `hfc/registry/feedback.csv`
- `hfc/output/feedback_sheet.xlsx`

## Flow

- **Setup build:** upload Feedback file to **main** and **audit** in the shared OneDrive folder; also upload the HTML report and record its link.
- **Field work:** edits **main** only.
- **Process HFC feedback:** pull **main** → apply fixes → write `resolved` → push updated rows to **audit**.

## Sync commands

```bash
# Pull main (field) -> local
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R <project> import

# Push local -> main + audit
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R <project> export
# or push-both (same effect) / push-main (main only) / push-audit (audit only, after code updates)
```
