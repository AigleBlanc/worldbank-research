# Issue tracking schema

Collaboration surface: **one file**, `issue_tracking.xlsx` — edited collaboratively by the agent, the RA, and the field team on the same sheet (Comment/Corrections/Status all live together; there is no separate audit twin). It lives entirely in a folder the OneDrive desktop app keeps synced to the cloud — **required, no local-only fallback**: `onedrive_output_dir` in `skills/hfc-fieldloop/config.json` points at that folder, and every read/write is plain file I/O against it; OneDrive's own sync client (not this skill) is what propagates changes to/from the cloud. There is never a separate local-only copy anywhere under `hfc/`. Every user-facing script calls `require_fieldloop_config_ready()` (`scripts/lib/issue_store.R`) before doing any real work, and stops with setup instructions if `config.json` isn't fully configured/reachable — see `SKILL.md`'s A0.

Two dated-snapshot subfolders live alongside the live file, inside the same synced folder:

| Subfolder | Filename | Written by | Purpose |
|---|---|---|---|
| `intermediate/` | `<YYYYMMDD>_issue_tracking.xlsx` | every `run_setup_build.R` run | this run's freshly computed findings, before merging into the live file |
| `resolutions/` | `<YYYYMMDD>_issues_resolution.xlsx` | `apply_feedback.R clone` | the agent's working clone for one day's "Process HFC feedback" pass |

**Naming note:** this `intermediate/` (tracking snapshots, next to `issue_tracking.xlsx`) is unrelated to `<sibling of input_data_dir>/intermediate/` (fixed microdata, see `write_intermediate()` in `scripts/lib/utils.R`) — always use the qualified path when referring to either.

A same-day rerun overwrites that day's snapshot/clone rather than creating a second dated file (so an in-progress "Process HFC feedback" pass isn't discarded by a second look the same day).

## Columns

Column order in every written file matches this table.

| column | source | notes |
|---|---|---|
| **Startdate / Enddate** | `start_date` / `end_date` | **First column — the date the issue is reporting on** (the flagged submission's own date), not when the row was logged. Blank for an aggregate-level finding (e.g. a by-enumerator missingness finding), same as Entity ID |
| Today's Date | — | creation timestamp, `YYYYMMDDHHMM` — stamped once when a finding first appears and preserved across reruns (see Merging, below). Distinct from Startdate/Enddate above — this is when the row was logged, not the date it's about |
| Entity ID | `submission_id` resolved via `resolve_display_vec()`, mode `role_map.yaml`'s `entity_display` | the data-collection unit's ID (student/household/school/...) by **default** — HFC data is de-identified, so we never have the respondent's real name; `entity_display` defaults to `"id"` and only shows the name if a project explicitly overrides it to `"name"`. **Blank for an aggregate-level finding** (e.g. a by-enumerator missingness finding, a by-site low-completion finding) since the check never established an entity-level answer, not just hidden from display. When populated with an ID, not necessarily unique per row (e.g. a household surveyed across multiple rounds keeps the same Entity ID); row-uniqueness for M2 is a separate, explicitly confirmed duplicate-check key. This header is always the fixed generic "Entity ID" in the xlsx/csv — the survey-specific display label (e.g. "Student ID") is HTML-report-only, driven by `role_map.yaml`'s `entity_label`. There is no separate "Entity"/name column — one column, mode-resolved. |
| Group | `group_id` resolved via `resolve_display_vec()`, mode `role_map.yaml`'s `group_display` (default `"name"`) | site/cluster's display name if a name field exists in the survey, else the raw ID — a single column, never a separate ID+Name pair. Header is the confirmed Group Label (e.g. "School") when set (`role_map.yaml`'s `group_label`), else the generic "Group". Blank when the underlying check doesn't operate at the group level. |
| Enumerator | `enumerator` resolved via `resolve_display_vec()`, mode `role_map.yaml`'s `enumerator_display` (default `"name"`) | enumerator's display name if a name field exists in the survey, else the raw ID by **default** — HFC data usually does have enumerator names, so this defaults the opposite way from Entity. Same single-column resolution as Group. |
| Issue | `issue` | plain-English issue label |
| Value | `value` | the flagged value itself, when the check has one to report at this row's granularity — every number in the report, `round1()`'d at the source in `scripts/lib/run_checks.R`, is 1 decimal place (continuous measurements like duration/GPS distance/outlier deviation/straightlining share/media duration, and percentages like completion/missingness alike — e.g. `87.3%`, not a whole number), with the one deliberate exception of p-values (Balance Tables), which keep their own precision so a significant result doesn't collapse to `0.0` |
| Comment | — | field team/RA/agent text (was `field_comment`, then `RIL Comment` — RIL doesn't stand for the field team — then `Comment`, simplified since the field team isn't the only one who writes here) |
| Corrections | — | proposed/applied solution — written by field/RA when proposing a fix, or by the agent (`apply_feedback.R apply --corrections`) describing what it actually did |
| Correction Author | — | RA/field initials, or the agent |
| **Status** | — | see below |
| Issue Category | `category` | which check category flagged this — written as a **human-readable label** (e.g. "Low completion", not `low_completion`), via `category_label()`/`CATEGORY_LABELS` in `scripts/lib/build_outputs.R`; an unmapped category (e.g. an M9 custom check) falls back to a Title-Case-from-snake_case transform of the raw value |
| Variable (DIME use) | — | the survey column the check evaluated (e.g. `income`, `duration`) — distinct from `Unique Submission ID`, populated by `mk_findings()`/`mk_aggregate_finding(..., variable_name = )` |
| Unique Submission ID | `key` | the machine-unique key (SurveyCTO `key`/uuid/instanceid) — blank for an aggregate-level finding, same as Entity ID. `detect_unique_key_column()` (`scripts/lib/profile_roles.R`) checks the exact-name pattern against the **full** column set before Entity-ID exclusion is applied, so a column literally named `key` still populates this even when it was also picked as Entity ID (the two can legitimately coincide) |
| **Issue ID** | findings | last column. Content-derived, stable key: `<check_module lowercase>:<Entity ID>[:<Variable>][:N]` for a row-level finding (e.g. `m3:90992`, `m6:90992:income`), or `<check_module lowercase>:enumerator\|group:<unit ID>[:<Variable>][:N]` for an aggregate-level one (e.g. `m7:enumerator:ENUM02:income`) — a trailing `:2`/`:3` only for genuine collisions within the same key. Not part of the literal template, but required — `Unique Submission ID` alone isn't unique per row (one submission can produce several findings), and this key must survive reruns so merging can preserve human/agent edits. See `mk_findings()`/`mk_aggregate_finding()`/`dedupe_finding_ids()` in `scripts/lib/utils.R`. |

**Removed from `issue_tracking.xlsx`:** `check_module` (kept only on internal `findings` for the HTML report). **Merged into single columns:** the old separate `Entity ID`+`Entity`, `Group ID`+`Group`, `Enumerator ID`+`Enumerator` pairs are each now one column, mode-resolved by `resolve_display_vec()` (`scripts/lib/utils.R`).

**De-identification defaults & override:** `role_map.yaml`'s `entity_display` (default `"id"`), `enumerator_display` (default `"name"`), and `group_display` (default `"name"`) control the three resolutions above — set once by `profile_roles()`, never guessed or asked about. Applies identically to the HTML report's findings tables *and* its descriptive stats tables (M1/M4/M7's by-enumerator breakdowns, M11's per-enumerator labels). Change one only on an explicit user request, by editing the field directly and rebuilding — see `SKILL.md` A1 step 7c.

### Status

Five values:

| Status | Meaning | Set by |
|---|---|---|
| `Open` | Default; not yet triaged, or triaged but not yet fixed | System default |
| `Accepted` | Field/RA agrees the finding is valid — advisory triage, not a hard gate | Field/RA edit |
| `Revise` | Field/RA disagrees, sent back — advisory | Field/RA edit |
| `Resolved` | The agent wrote and applied a fix | `apply_feedback.R apply`, in today's resolutions clone only, until merged and committed |
| `Needs Review` | The agent couldn't confidently resolve it | `apply_feedback.R needs-review`, in today's resolutions clone only, until merged and committed |

**Trigger for the agent to act:** any row with `Status == Open` **and** a non-empty Comment is eligible — there is no separate `Accepted` gate. `Accepted`/`Revise` are advisory signals a field/RA can still use for their own triage, but the agent interprets and fixes any Open+commented row regardless of whether it's `Accepted`.

Legacy files (old `status`+`resolved` pair, or `ra_status`) are migrated automatically on read: `accepted`+`resolved=yes`→`Resolved`; `accepted`+`resolved=partial`→`Needs Review`; `accepted`+`resolved=No`→`Accepted`; `revise`→`Revise`; else→`Open`.

## Merging

The live `issue_tracking.xlsx` is never overwritten silently — two different merge directions, each narrow to its own purpose, both requiring explicit AskUserQuestion confirmation before the live file changes:

**Setup Build side** (`merge_preserve_existing()` in `scripts/lib/build_outputs.R`, driven by `scripts/merge_issues.R`): merges this run's `intermediate/` snapshot against the live file.
- Every row already in the live file is kept **exactly as-is** — no column refreshed, nothing recomputed, `Today's Date`/`Comment`/`Status`/etc. all untouched.
- Issue IDs only in the new snapshot → genuinely new findings, appended with `Status = Open`.
- Issue IDs only in the live file (no longer reproduced by current data) → **never dropped**; their trail also lives on in `hfc/code/resolutions/`/`data/intermediate/` if a fix was ever applied.
- `run_setup_build.R` runs this automatically on every rebuild once a live file exists; it writes `merged_issue_tracking.xlsx` and stops with a `MERGE_PENDING` message rather than overwriting — the agent reviews it with the user, then runs `commit_merged_issue_tracking.R`.

**Post-feedback side** (`merge_resolution_updates()` in `scripts/lib/build_outputs.R`, driven by `scripts/merge_resolutions.R`): merges today's `resolutions/` clone against the live file.
- For Issue IDs in both: take `Status`/`Corrections`/`Correction Author` from the clone, keep every other column from the live file (in case the field/RA edited something concurrently, e.g. a new Comment on an unrelated row).
- Issue IDs only in the live file pass through unchanged.
- Writes `merged_issue_resolutions.xlsx`; same review-then-commit pattern.

**`commit_merged_issue_tracking.R`** is the *only* script that ever overwrites the live `issue_tracking.xlsx` — it reads the named `merged_*.xlsx`, commits it as the new live file, and deletes the merged file. It only ever runs after the agent has shown the user the merged file's contents and gotten explicit AskUserQuestion confirmation, with an upfront warning that this replaces the live shared file (F28).

## Config

One file, one rule: `hfc-fieldloop/config.json` — the only config that matters, edited directly. No per-project override; every run using this skill copy shares it. Ships with `<...>`-wrapped placeholder values by default — the three required fields must be filled in with real absolute paths before first use:
```json
{
  "Input Data Directory": "/Users/you/Documents/my_survey/data",
  "Media Folder Directory": "",
  "HFC Output Directory": "/Users/you/OneDrive - Your Org/HFC Reports",
  "Code Output Directory": "/Users/you/code/my_survey_hfc",
  "Main Tracking Filename": "issue_tracking.xlsx"
}
```
**HFC Output Directory** must be an absolute path to a folder the OneDrive desktop app is already syncing on this machine (it's created automatically if the sync client hasn't materialized it yet). A missing or still-placeholder **Input Data Directory**, **HFC Output Directory**, or **Code Output Directory** → every user-facing script's `require_fieldloop_config_ready()` pre-flight `stop()`s, naming the specific field, rather than proceeding. **Media Folder Directory** is optional — no check module reads it (see `references/check_modules.md`'s M13 section); it's kept in `config.json` only in case a future check needs on-disk media access.

Share the OneDrive **folder** (not the individual file) with collaborators via the normal OneDrive "Specific people" sharing UI, once, before relying on this — this skill never mints its own share links, it just reads/writes whatever folder access has already been configured.

`hfc/project.yaml` stores `issue_tracking_merge_pending` (whether a rebuild is waiting on a merge confirm).

**Migrating from the old dual-twin design:** if a project still has `issue_resolution.xlsx`/`.csv` from a prior version of this skill, there's no automated migration — those files simply stop being written; manually fold anything still relevant into `issue_tracking.xlsx` and delete them.

## Post-feedback flow

There's no built-in fix-classification engine — the agent reads each eligible row and writes the fix itself. See `SKILL.md`'s Pipeline B and `scripts/lib/apply_feedback_helpers.R`. Everything below operates on today's `resolutions/<date>_issues_resolution.xlsx` clone, never on `issue_tracking.xlsx` directly:

1. `apply_feedback.R clone` — creates (or reuses, if already run today) today's resolutions clone from the current live file.
2. `apply_feedback.R list-open` — filters today's clone to `Status = Open` + non-empty Comment, writes `hfc/outputs/fix_candidates.csv` with full row context.
3. Per row, in a single pass: the agent interprets the Comment, writes `hfc/code/resolutions/<Issue ID, sanitized>.R` defining `fix(ds) -> ds`, then calls `apply_feedback.R apply --finding-id <id> --corrections "<what it did>"` — loads `<sibling of input_data_dir>/intermediate/<stem>.<ext>` if it exists (else the original file in `input_data_dir`), applies `fix(ds)`, writes back to `<sibling of input_data_dir>/intermediate/` (one evolving file), and sets `Corrections` + `Status = Resolved` in the clone only.
4. `apply_feedback.R needs-review --finding-id <id>` — sets `Status = Needs Review` in the clone for rows the agent can't confidently handle.
5. `merge_resolutions.R` folds the clone back into a `merged_issue_resolutions.xlsx`; after AskUserQuestion confirmation, `commit_merged_issue_tracking.R` applies it to the live file.
