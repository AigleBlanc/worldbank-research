# Issue tracking schema

Collaboration surface: **one file**, `issue_tracking.xlsx` — edited collaboratively by the agent, the RA, and the field team on the same sheet (RIL Comment/Corrections/Status all live together; there is no separate audit twin). Once `assets/lib/onedrive.json` has `"enabled": true`, the OneDrive folder it names (inside the runner's own individual OneDrive for Business — no SharePoint site or Team needed) is the **sole source of truth**: every read fetches current state, every write commits back, and there is no permanent local copy that persists as "the real file." If OneDrive isn't configured, or a call fails, local `hfc/output/issue_tracking.xlsx` becomes the sole store instead — exactly one location either way, never a persistent dual copy. See `scripts/lib/issue_store.R` for the backend-resolution logic.

Two dated-snapshot subfolders live alongside the live file, in whichever backend is active:

| Subfolder | Filename | Written by | Purpose |
|---|---|---|---|
| `intermediate/` | `<YYYYMMDD>_issue_tracking.xlsx` | every `run_setup_build.R` run | this run's freshly computed findings, before merging into the live file |
| `resolutions/` | `<YYYYMMDD>_issues_resolution.xlsx` | `apply_feedback.R clone` | the agent's working clone for one day's "Process HFC feedback" pass |

**Naming note:** this `intermediate/` (tracking snapshots, next to `issue_tracking.xlsx`) is unrelated to `data/intermediate/` (fixed microdata, see `write_intermediate()` in `scripts/lib/utils.R`) — always use the qualified path when referring to either.

A same-day rerun overwrites that day's snapshot/clone rather than creating a second dated file (so an in-progress "Process HFC feedback" pass isn't discarded by a second look the same day).

## Columns

Template: `assets/issue_tracking_template.csv`. Column order in every written file matches this table.

| column | source | notes |
|---|---|---|
| Today's Date | — | creation timestamp, `YYYYMMDDHHMM` — stamped once when a finding first appears and preserved across reruns (see Merging, below) |
| Entity ID | `submission_id` | the data-collection unit's ID (student/household/school/...) — **not necessarily unique per row** (e.g. a household surveyed across multiple rounds keeps the same Entity ID); row-uniqueness for M2 is a separate, explicitly confirmed duplicate-check key (Entity ID + optional extra columns like round/wave). This header is always the fixed generic "Entity ID" in the xlsx/csv — the survey-specific display label (e.g. "Student ID") is HTML-report-only, driven by `role_map.yaml`'s `entity_label`. |
| Entity | detected name field | human-readable name for that same unit (e.g. respondent name) — **empty string when no name-like column exists in the survey; never falls back to duplicating the ID** |
| Group ID | `group_id` | site/cluster identifier |
| Group | detected name field | human-readable name for the group unit (e.g. village name vs village code) — empty when not found |
| Enumerator ID | `enumerator` | enumerator code/id |
| Enumerator | detected name field | enumerator's name — empty when not found |
| Startdate / Enddate | `start_date` / `end_date` | |
| Issue | `issue` | plain-English issue label |
| Value | `value` | the flagged value itself |
| RIL Comment | — | field team text (was `field_comment`) |
| Corrections | — | proposed/applied solution — written by field/RA when proposing a fix, or by the agent (`apply_feedback.R apply --corrections`) describing what it actually did |
| Correction Author | — | RA/field initials, or the agent |
| **Status** | — | see below |
| Issue Category | `category` | which check category flagged this |
| Variable (DIME use) | — | the survey column the check evaluated (e.g. `income`, `duration`) — distinct from `Unique Submission ID`, populated by `mk_findings(..., variable_name = )` |
| Unique Submission ID | `key` | the machine-unique key (SurveyCTO uuid/instanceid) |
| **Issue ID** | findings | last column. Content-derived, stable key: `<check_module lowercase>:<Entity ID>[:<Variable>][:N]` (e.g. `m3:90992`, `m6:90992:income`; a trailing `:2`/`:3` only for genuine same-module/same-entity/no-variable collisions, e.g. M2 duplicate rows). Not part of the literal template, but required — `Unique Submission ID` alone isn't unique per row (one submission can produce several findings), and this key must survive reruns so merging can preserve human/agent edits. See `mk_findings()`/`dedupe_finding_ids()` in `scripts/lib/utils.R`. |

**Removed from `issue_tracking.xlsx`:** `check_module` (kept only on internal `findings` for the HTML report).

### Status

Five values:

| Status | Meaning | Set by |
|---|---|---|
| `Open` | Default; not yet triaged, or triaged but not yet fixed | System default |
| `Accepted` | Field/RA agrees the finding is valid — advisory triage, not a hard gate | Field/RA edit |
| `Revise` | Field/RA disagrees, sent back — advisory | Field/RA edit |
| `Resolved` | The agent wrote and applied a fix | `apply_feedback.R apply`, in today's resolutions clone only, until merged and committed |
| `Needs Review` | The agent couldn't confidently resolve it | `apply_feedback.R needs-review`, in today's resolutions clone only, until merged and committed |

**Trigger for the agent to act:** any row with `Status == Open` **and** a non-empty RIL Comment is eligible — there is no separate `Accepted` gate. `Accepted`/`Revise` are advisory signals a field/RA can still use for their own triage, but the agent interprets and fixes any Open+commented row regardless of whether it's `Accepted`.

Legacy files (old `status`+`resolved` pair, or `ra_status`) are migrated automatically on read: `accepted`+`resolved=yes`→`Resolved`; `accepted`+`resolved=partial`→`Needs Review`; `accepted`+`resolved=No`→`Accepted`; `revise`→`Revise`; else→`Open`.

## Merging

The live `issue_tracking.xlsx` is never overwritten silently — two different merge directions, each narrow to its own purpose, both requiring explicit AskUserQuestion confirmation before the live file changes:

**Setup Build side** (`merge_preserve_existing()` in `scripts/lib/build_outputs.R`, driven by `scripts/merge_issues.R`): merges this run's `intermediate/` snapshot against the live file.
- Every row already in the live file is kept **exactly as-is** — no column refreshed, nothing recomputed, `Today's Date`/`RIL Comment`/`Status`/etc. all untouched.
- Issue IDs only in the new snapshot → genuinely new findings, appended with `Status = Open`.
- Issue IDs only in the live file (no longer reproduced by current data) → **never dropped**; their trail also lives on in `hfc/fixes/`/`data/intermediate/` if a fix was ever applied.
- `run_setup_build.R` runs this automatically on every rebuild once a live file exists; it writes `merged_issue_tracking.xlsx` and stops with a `MERGE_PENDING` message rather than overwriting — the agent reviews it with the user, then runs `commit_merged_issue_tracking.R`.

**Post-feedback side** (`merge_resolution_updates()` in `scripts/lib/build_outputs.R`, driven by `scripts/merge_resolutions.R`): merges today's `resolutions/` clone against the live file.
- For Issue IDs in both: take `Status`/`Corrections`/`Correction Author` from the clone, keep every other column from the live file (in case the field/RA edited something concurrently, e.g. a new RIL Comment on an unrelated row).
- Issue IDs only in the live file pass through unchanged.
- Writes `merged_issue_resolutions.xlsx`; same review-then-commit pattern.

**`commit_merged_issue_tracking.R`** is the *only* script that ever overwrites the live `issue_tracking.xlsx` — it reads the named `merged_*.xlsx`, commits it as the new live file, and deletes the merged file. It only ever runs after the agent has shown the user the merged file's contents and gotten explicit AskUserQuestion confirmation, with an upfront warning that this replaces the live shared file (F28).

## Config

One file, one rule: `hfc-fieldloop/assets/lib/onedrive.json` — the only config that matters, edited directly. No per-project override; every project using this skill copy shares it. Starts `"enabled": false` until set up:
```json
{
  "enabled": true,
  "folder_path": "HFC Reports",
  "main_file": "issue_tracking.xlsx"
}
```
`"enabled": false` (or the file missing) → local `issue_tracking.xlsx` only / `--no-onedrive`. There's no site/tenant URL to configure — `Microsoft365R::get_business_onedrive()` connects to whichever account signs in.

**Auth:** delegated, one-time interactive sign-in — no secrets stored in this package. Run `Rscript setup_onedrive_auth.R` **once, yourself, in a normal interactive R/RStudio session** — this cannot be done from inside a non-interactive Claude-Code-driven run. `Microsoft365R`/`AzureAuth` then cache the token locally and refresh it silently on every later run. This connects to the runner's own OneDrive — no SharePoint site or Team needs to exist.

Share the OneDrive **folder** (not the individual file) with collaborators via the normal OneDrive "Specific people" sharing UI, once, before relying on this — the code never mints its own share links, it just uploads into whatever folder access has already been configured.

`hfc/project.yaml` stores `issue_tracking_backend` (`onedrive`/`local`) and `issue_tracking_merge_pending` (whether a rebuild is waiting on a merge confirm) plus `report_onedrive_url` (the report's own URL). Local `issue_tracking.xlsx` remains the fallback store if OneDrive isn't configured or auth is missing.

**Migrating from the old dual-twin design:** if a project still has `issue_resolution.xlsx`/`.csv` from a prior version of this skill, there's no automated migration — those files simply stop being written; manually fold anything still relevant into `issue_tracking.xlsx` and delete them.

## Post-feedback flow

There's no built-in fix-classification engine — the agent reads each eligible row and writes the fix itself. See `SKILL.md`'s Pipeline B and `scripts/lib/apply_feedback_helpers.R`. Everything below operates on today's `resolutions/<date>_issues_resolution.xlsx` clone, never on `issue_tracking.xlsx` directly:

1. `apply_feedback.R clone` — creates (or reuses, if already run today) today's resolutions clone from the current live file.
2. `apply_feedback.R list-open` — filters today's clone to `Status = Open` + non-empty RIL Comment, writes `hfc/registry/fix_candidates.csv` with full row context.
3. Per row, in a single pass: the agent interprets the RIL Comment, writes `hfc/fixes/<Issue ID, sanitized>.R` defining `fix(ds) -> ds`, then calls `apply_feedback.R apply --finding-id <id> --corrections "<what it did>"` — loads `data/intermediate/<stem>.<ext>` if it exists (else `data/raw/`), applies `fix(ds)`, writes back to `data/intermediate/` (one evolving file), and sets `Corrections` + `Status = Resolved` in the clone only.
4. `apply_feedback.R needs-review --finding-id <id>` — sets `Status = Needs Review` in the clone for rows the agent can't confidently handle.
5. `merge_resolutions.R` folds the clone back into a `merged_issue_resolutions.xlsx`; after AskUserQuestion confirmation, `commit_merged_issue_tracking.R` applies it to the live file.

## Sync commands

```bash
# Refresh the local registry copy from whichever backend is live
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R <project> pull

# Push the local hfc/registry/issue_tracking.csv up as the live file
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R <project> push
```
