---
name: hfc-fieldloop
description: >-
  Drop-in HFC FieldLoop skill for a survey project folder in VS Code + Claude Code.
  Use when the user says "Run HFC FieldLoop", "Start FieldLoop", "Process HFC feedback",
  "Run FieldLoop fixes", or "Apply field feedback", or invokes /hfc-fieldloop. Discovers
  data/form, confirms setup with the agent's own best guess (never a long menu of
  choices), builds the HTML report and checks under hfc/, and keeps one shared
  issue_tracking.xlsx in OneDrive (required — no local fallback), or runs the
  post-feedback fix pipeline, writing agent-authored fixes to a sibling intermediate/
  folder next to the configured Input Data Directory.
---

# HFC FieldLoop (drop-in project skill — Claude Code)

Copy this folder anywhere as **`.claude/skills/hfc-fieldloop/`** (Claude Code discovers skills there), then configure **`config.json`** at this skill's root with four directories: **Input Data Directory** (survey microdata), **Media Folder Directory** (optional — audio/image attachments; reserved for future use, no check currently reads it), **OneDrive Folder Directory** (a OneDrive-synced folder for the shared `issue_tracking.xlsx`), and **Code Output Directory** (a git working copy the user manages themselves — World Bank practice prefers versioned code/config output; this skill only ever writes plain files there, never runs git). There is no "survey project root" concept — the skill never searches for data, and the built product is decoupled from wherever the raw data lives. Product docs: `README.md`, skill tree map: `hfc/structure.html` (generated), deps: `install.R`.

Supporting files resolve via `${CLAUDE_SKILL_DIR}` (this skill directory); every script reads its paths from `config.json`, not from CLI arguments:

```bash
Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R
Rscript "${CLAUDE_SKILL_DIR}/scripts/run_setup_build.R"
```

**Built product** (`config/`, `instruments/`, `outputs/`, `code/` — with `code/checks/` and `code/resolutions/`) always lands under **`hfc/`** inside the configured Code Output Directory. `issue_tracking.xlsx` itself lives entirely in the configured OneDrive Folder Directory (required — see A0), not under `hfc/`. Open `hfc/structure.html` in a browser and confirm via the Wrap-up window's Structure tab (A2) before writing the full package.

Two pipelines — choose by the user's prompt (see `references/prompts.md`):

| Intent | Trigger examples | What you do |
|---|---|---|
| **A. Setup** | "Run HFC FieldLoop" | Discover → confirm (guess + corrections) → `hfc/` outline → build → open HTML |
| **B. Post-feedback** | "Process HFC feedback" | Clone → list Open+Comment rows → per row: read + write fix code → apply (single pass) → merge back → confirm → commit |

Authority (read; do not invent standards):

- `references/interaction.md` — **AskUserQuestion** UX (required for all gates; guess-then-correct, not typed mega-strings)
- `references/check_modules.md` — M1–M13 specs + the required-gate window + nested skip-logic
- `references/issue_tracking_schema.md` — the issue-tracking file's schema, including the `Status` lifecycle
- `references/checklist.md` — package completeness
- `references/flags.md` — failure modes
- `references/prompts.md` — exact trigger phrases
- `references/ai_use.md` — no PII to commercial AI

Helpers (prefer `Rscript` rather than reimplementing):

- `scripts/lib/discover.R` — scan the configured Input Data Directory only, classify data vs. form vs. a candidate roster/target-sample file
- `scripts/preview_modules.R` — write `hfc/config/modules.yaml`, a commented draft of proposed module defaults (run before A2's confirmation windows)
- `scripts/run_setup_build.R` — build after modules confirmed (reads `config.json`, no positional args); writes under `hfc/` in the Code Output Directory
- `scripts/rebuild_report.R` — post-resolution report refresh (Pipeline B step 7): re-runs checks against the latest data, drops Resolved/untracked findings from `report.html` only (`issue_tracking.xlsx` keeps full history)
- `scripts/apply_feedback.R` — post-feedback CLI (`clone` / `list-open` / `apply` / `needs-review`); fix logic is agent-authored, see `scripts/lib/apply_feedback_helpers.R`
- `scripts/merge_issues.R` / `scripts/merge_resolutions.R` — fold a dated snapshot / resolutions clone back into `issue_tracking.xlsx`, producing a `merged_*.xlsx` for the agent to review
- `scripts/commit_merged_issue_tracking.R` — the only script that ever overwrites the live `issue_tracking.xlsx`, run only after explicit AskUserQuestion confirmation
- `assets/issue_tracking_template.csv` — schema template
- `assets/README_template.md` / `assets/README_example.md` — draft project README on setup
- `assets/summary_message_example.md` — annotated calibration example for the A4 Summary narrative
- `assets/check_templates/` — M1–M13 real, runnable per-module scripts, copied into `hfc/code/checks/` at build time (same logic as `scripts/lib/run_checks.R`'s `check_mN()` functions, `scripts/lib/media.R` for M11); the Input Data Directory is read live from `config.json` each time a copied script runs, not frozen at generation time
- `scripts/lib/media.R` — detect media-indicating columns; M11 now flags only a column that's completely empty across every surveyed row, no on-disk file access
- `scripts/lib/geo_timezone.R` — country → IANA timezone lookup/resolver for M5, and for the country-confirm tab in A1
- `scripts/lib/form_logic.R` — SurveyCTO relevance / nested skip-logic helper + M4's group/section parsing
- `scripts/lib/product_structure.R` — write `hfc/structure.html`
- `scripts/lib/check_modules_preview.R` — write the commented `hfc/config/modules.yaml`
- `scripts/lib/module_desc.R` — per-module report descriptions computed from this project's actual configured thresholds
- `scripts/lib/pipeline_core.R` — shared "run checks + write `hfc/outputs/issues.csv`" step used by both `run_setup_build.R` and `rebuild_report.R`

## Interactive confirms (AskUserQuestion) — guess first, correct if wrong

**Required.** Read and follow `references/interaction.md`.

The core pattern for every confirm in this skill: **the agent always states its own best guess first, in plain language, then gives the user a fast way to accept or correct it** — one atomic fact per tab, minimal text, packed into as few windows as possible. Two structural terms used throughout this doc:

- **Window** = one `AskUserQuestion` tool call.
- **Tab** = one `question` entry inside that call, covering exactly ONE fact/guess. A window can hold up to 4 tabs, all shown to the user together as a single interaction.

**Standard tab template — use this for every tab:**
> *[Guess + how it's used. ≤2 sentences, no em-dashes.]*
> Option 1: starts with "Looks good" (e.g. "Looks good!", "Looks good, continue!")
> Option 2: contextual to the tab's subject, not literally "Needs correction" (e.g. "The list needs edits", "A mapping is swapped", "The threshold is wrong") — "(I will type in Other)" unless a named 3rd/4th option already covers the correction path

Rules:

- One fact per tab. Never bundle multiple independent guesses (e.g. duration column + SD rule + work hours) into a single tab's text — that was the old design and it's been reverted.
- Sentence 1 leads with the concrete artifact (real path, real column name). Sentence 2 states only what's needed to judge the guess, plus any real downstream effect on other checks (e.g. "every other check runs on that subset only") — never leave a consequential effect implicit.
- Options aren't always the generic "Looks good!"/correction pair. When a rule has a natural partial-accept split, or an obvious alternate mode, enumerate those as real, named options (up to 4) instead of routing everything through free-text Other.
- List full item sets explicitly in a tab's own text (e.g. every variable name, not "and 5 more") — only the *options* array is capped at 4, the description text isn't.
- Timezones are always stated as abbreviation + city/country + UTC offset (e.g. "CAT (Blantyre, Malawi, UTC+2:00)"), never a bare IANA name.
- **Pack windows to capacity.** Backfill spare tab slots in an earlier window rather than opening a new one for 1-2 leftover facts — minimizing window count matters more than keeping tabs topically pure. Only a genuine data dependency (a tab whose content requires output that doesn't exist until a prior tab's answer is acted on) justifies a new window. See the Gate map in `references/interaction.md` for the current window-by-window packing.
- Fallback only if AskUserQuestion is unavailable: state the guesses as a numbered list in chat and ask the user to reply "looks good" or describe corrections — still not a typed mega-string like `M1=Y M2=N`.

## Operating principles

1. Phases that write files wait for explicit AskUserQuestion confirmation (no silent proceed).
2. Never mutate original microdata in the configured Input Data Directory — agent-authored fixes write to `<sibling of Input Data Directory>/intermediate/<stem>.<ext>` instead (one evolving file, never inside the git-tracked Code Output Directory).
3. **Guess first, correct if wrong** (see Interactive confirms above) — every setup confirm states the agent's own best guess and gives one free-text correction option, never a long menu of choices. This applies to every window in A1 and A2 below.
4. Feedback: **one shared file**, `issue_tracking.xlsx` — edited collaboratively by the agent, the RA, and the field team on the same file (Comment/Corrections/Status all live in the same sheet; no separate audit twin). OneDrive is **required** (no local fallback in the product — see A0): once `config.json`'s **OneDrive Folder Directory** points at a folder the OneDrive desktop app is syncing, that folder is the **sole store** — every read/write is plain file I/O against it, and OneDrive's own sync client (not this skill) propagates changes to the cloud, so there is never a separate local-only copy. Two dated-snapshot subfolders live alongside it, inside the same synced folder: `intermediate/<YYYYMMDD>_issue_tracking.xlsx` (one per setup-build run) and `resolutions/<YYYYMMDD>_issues_resolution.xlsx` (the agent's working clone during a "Process HFC feedback" pass) — see `references/issue_tracking_schema.md`. All four directories live in the skill's own `config.json` — the only file that matters, edited directly, no per-project override, no auth step or secrets in this package. The OneDrive folder is then shared manually (by whoever owns it) with collaborators via OneDrive's "Specific people" sharing UI.
5. Open `report.html` exactly once per pipeline pass, with `utils::browseURL()` (or OS `open`) — only after the Summary narrative (and, in Pipeline A, the README) are already folded in. Never at a preview/first build: opening an incomplete report and then silently rewriting the file underneath that open tab is confusing, not helpful.
6. **Must** write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from the user's **confirmed** (guessed-then-corrected) options **before** calling the builder; also write `hfc/config/module_notes.yaml` whenever a custom check was confirmed, and `role_map.yaml`'s `important_vars` from the confirmed shortlist.
7. M10 (Survey-Specific) has no built-in checks and defaults to **off / empty** — every M10 finding comes from a custom check the agent writes for this survey's specific content, driven entirely by what the user describes in the Extra-checks tab (A2, Wrap-up window).
8. **Extra-checks confirm is mandatory, every run:** part of the Wrap-up window (A2) — always state "No additional checks" as the guess, with Other available for the user to describe a custom need. Never skip this tab, never treat silence elsewhere as an implicit "no."
9. Draft `<Code Output Directory>/README.md` from `assets/README_template.md` automatically — no confirmation needed, it's just documentation. Point to `references/ai_use.md`.
10. **M11 media, redesigned:** the ONLY thing to flag is a media-indicating column that is completely empty across every surveyed row (a form/coding problem — the field isn't showing up in the enumerator's app, or the question is misconfigured) — never per-row file hygiene, and no on-disk file access at all. Confirm which columns indicate media presence (audio/image filename columns, plus any qualitative open-text columns the agent itself identifies) in the Media Columns tab (A2, Media/Map/Grouping window). Never put filename cols under M12.
11. **Completion is redefined:** it means whether all PLANNED surveys were conducted, not whether a started survey finished. The agent detects a completion signal (a status column, a target/roster file, or a primary/secondary sample column) and confirms it in the Setup window's Completion tab (A1) — only when a signal is actually found; if none is found, M1 falls back to its original row-missingness heuristic and nothing else changes. Once confirmed, if a "status" signal shows some rows were not completed, EVERY other check module (M2–M13) runs only on the completed/surveyed subset — incomplete rows are filtered out before any other check sees them. M1 itself always sees the full picture (the complete dataset, or the roster/target list).
12. **Grouping defaults to Treatment/Control**, not geography — M1's completion-by-group stats table groups by a detected Treatment/Control column first. Geography is only used when no Treatment/Control column exists, or the user explicitly opts in to it alongside Treatment/Control (default: declined — ask about this only when a Treatment/Control column was actually found).
13. **Redundant/near-duplicate variables** (e.g. `treat` vs. `treat_ext`, `age` vs. `age_calc`): always silently keep the single most reasonable one in every shortlist you propose — never present both as if independently meaningful, and never ask the user to pick between them.
14. **Country inference must come from geography in the data** (district/region/village/site names, or a GPS bounding box), never from the input folder's name/basename — that's a report-title convenience only, not a location signal.
15. **Be careful about assent vs. consent** — they are different concepts (assent = the child/minor's own agreement; consent = the parent/guardian's, or an adult respondent's own). Confirm the column mapping explicitly, naming which column maps to which concept, in its own tab (A2, Wrap-up window) — never bundled with anything else.
16. **Nested questions:** when form `relevant` says a child item is skipped, do not flag blanks as missing.
17. All product code/artifacts under **`hfc/`**.
18. **Report-wide sort:** every table sorts by enumerator, then unique ID, then date (most recent first); every finding matching the confirmed last date also appears in the dedicated Last Day tab.

---

## Pipeline A — Setup

### A0. Config pre-flight (mandatory, every run)

There is no "survey project root" and no local-only mode — everything is driven by `skills/hfc-fieldloop/config.json`, naming four directories: **Input Data Directory**, **Media Folder Directory** (optional), **OneDrive Folder Directory**, **Code Output Directory** (Input Data Directory, OneDrive Folder Directory, Code Output Directory are required). Before proceeding to A0b/A1, verify `config.json` is fully configured — real paths, not the shipped `<...>` placeholders (this is exactly what `require_fieldloop_config_ready()` in `scripts/lib/issue_store.R` checks — every CLI script in this skill calls it automatically and `stop()`s with the same instructions below, naming the specific missing field, so this gate is also enforced in code, not just in this doc).

- **If it's already fully configured:** say so briefly in chat (name the three configured directories) and continue to A0b — no AskUserQuestion needed, there's no choice to make.
- **If any required field is missing or still a placeholder:** stop here. Tell the user, in this order: (1) run `Rscript <skill_dir>/install.R` if packages might be missing, (2) make sure the OneDrive desktop app is installed and signed in on this machine, and note the local folder it syncs to, (3) edit `<skill_dir>/config.json` — set Input Data Directory, OneDrive Folder Directory, and Code Output Directory to real absolute paths (Media Folder Directory optional) — this is skill-level config, applies to every run using this skill copy. Do not proceed with Pipeline A or B until they confirm this is done and the pre-flight succeeds.

### A0b. Config-reuse gate (Window: Config reuse — conditional)

Immediately after the config pre-flight passes, check whether `hfc/config/role_map.yaml` **and** `hfc/config/modules.yaml` already exist under the configured Code Output Directory (a prior run). If neither exists, skip straight to A1 — nothing to reuse yet, no window shown. If they exist, one tab, three real options (no generic Other needed, these three cover it):

> *Found a saved setup from a prior run. Rebuild using it as-is?*
> - "Yes, reuse and rebuild (recommended)" — proceed straight to A4 build with the saved configs; skip A1 and A2 entirely (the existing reload logic in `run_setup_build.R` already handles this).
> - "No, start fresh" — delete `hfc/config/role_map.yaml` and `hfc/config/modules.yaml` (only those two files), then run A1–A4 normally as a first-ever setup.
> - "Let me edit the config files first" — state the paths (`hfc/config/role_map.yaml`, `hfc/config/modules.yaml`), wait for the user to confirm they're done, then proceed straight to A4 build; the existing reload logic picks up their hand-edited values automatically.

### A1. Discover + confirm setup (Window: Setup — always, up to 4 tabs)

1. Run discovery in the configured Input Data Directory only — no searching elsewhere, but including any nested subfolders (`discover_project()`). This also surfaces a `roster_candidate` — a second file that looks like a target/planned-sample list, distinct from the main data file — used by the completion-signal detection in step 5; and a `context_doc` — a project description / Pre-Analysis Plan document (pdf/doc/docx/txt/md), used in step 1b below.
1b. **If `context_doc` was found, read it now** (before profiling roles) — the Read tool handles PDF and text/markdown directly. If it's a `.docx`, run `Rscript <skill_dir>/scripts/lib/docx_text.R "<path>"` first (prints the path to a plain-text extraction, no new dependency needed — it's just an unzipped `word/document.xml`) and `Read` that instead of the binary file. Legacy binary `.doc` (pre-2007, not a zip container) can't be parsed this way — for that one format only, say so briefly in chat and ask the user to export it as `.docx` or PDF instead, and move on without blocking setup. Treat its contents as **background context only** — survey purpose, design, treatment arms, target sample/completion, key outcome variables, timeline — letting it inform judgment calls throughout A1/A2 (country guess, entity label, important-variables shortlist, M10 custom-check suggestions). It is never itself a data source: never parse findings or role fields out of it mechanically, and never let it silently override what the actual microdata shows — if the two conflict, trust the data and flag the discrepancy in chat. If multiple candidate documents were found with no clear name match, don't guess — name them all in chat and ask which one, in the same message as step 1b's summary (no separate tab).
2. **If nothing is found:** tell the user to drop files into the configured Input Data Directory, then try again. Do not proceed without data.
3. Form optional: proceed data-only; note M10 / M3 / nested logic weaker.
4. Profile roles automatically — none of the following are separately confirmed; they surface only through the tabs below, correctable via each tab's free-text box:
   - **Entity ID**: `shortlist_entity_ids()`'s top candidate.
   - **Entity Label**: a Title-Case guess for what to call the entity (e.g. "Household" for a column named `hhld_id`) — used everywhere the entity is displayed: the HTML report's findings tables *and* the xlsx/csv issue-tracking export.
   - **Duplicate-check key**: auto-resolved — Entity ID alone if already 100% unique in the raw data, else Entity ID + the top `detect_duplicate_key_candidates()` hit. (Restated for visibility in the Keys & Hours window, A2.)
   - **Media-indicating columns**: `detect_media_vars()` for audio/image filename columns, plus any qualitative/open-text columns the agent itself identifies as capturing qualitative data — stated in the Media, Map & Grouping window, A2, not here.
   - **De-identification defaults (not confirmed, not surfaced in chat):** HFC data is de-identified by default — the entity's real name is never available, but enumerator names usually are. `profile_roles()` sets `roles$entity_display = "id"` (Entity always shows the raw ID), `roles$enumerator_display = "name"` and `roles$group_display = "name"` (Enumerator/Group show the name when one exists, else the ID) — applied everywhere (HTML report findings tables *and* their descriptive stats tables, `issue_tracking.xlsx`/`issues.csv`) via `resolve_display_vec()` (`scripts/lib/utils.R`). These are fixed defaults, not a guess — do not ask about them anywhere. Only change one if a user **explicitly** asks (e.g. "this data isn't anonymized, show respondent names" or "show enumerator IDs instead"): edit the matching field directly in `hfc/config/role_map.yaml` and rebuild — never guess or proactively offer this.
5. **Country**: if an explicit country-name/code column exists (`shortlist_country_columns()`), use it directly and resolve its timezone(s) via `resolve_country_timezone_column()` (`scripts/lib/geo_timezone.R`). If not, read the sampled values from `shortlist_geography_signal_cols()` (district/region/village/site-name-like columns, plus a GPS bounding box if coordinates exist) and use your own general-knowledge judgment to state a best-guess country — **never infer this from the input folder's name/basename**, that's a report-title convenience only. Resolve the guessed country's timezone via `resolve_country_timezone()` — state it as abbreviation + city/country + UTC offset (e.g. "CAT (Blantyre, Malawi, UTC+2:00)"), never a bare IANA name — a resolved timezone is always shown back for confirmation, never trusted silently.
6. **Detect the completion signal** (`detect_completion_signal()` in `scripts/lib/profile_roles.R`) — up to three types, and more than one can be present at once:
   - **status** — an explicit per-row outcome column (e.g. `result`: Complete/Incomplete/Refused) with both complete- and non-complete-looking values.
   - **roster** — the `roster_candidate` from step 1: a second file that looks like a target/planned-sample list.
   - **primary_secondary** — a column within the surveyed data marking each row Primary or Secondary sample (no separate roster).
   If **none** are detected, there's nothing to confirm here — skip the Completion tab entirely, and M1 falls back to its original row-missingness heuristic.
   If **exactly one** is detected, state it as a normal guess in the Completion tab.
   If **more than one** is detected, do NOT silently pick — the Completion tab's text must explicitly name the conflict (e.g. *"Found both a status column (result) and a roster file (sample_list.csv). Using the status column by default, the more direct signal."*) and flag it as needing a closer look, not a routine guess.
7. **One window, "Setup," up to 4 tabs — one atomic fact each, standard template:**
   - **Data found**: sentence 1 states the real paths found (data file, form if any, and project description/PAP document if found in step 1b); sentence 2 states row count, column count, and collection date range.
   - **Entity**: "The entity here is `<Label>`, in place of `<column>`. I'll use this name across the report and tracking sheet."
   - **Country**: "Data collection country is `<Country>`. Timezone is `<abbrev>` (`<city, country>`, UTC`<offset>`)."
   - **Specific instructions**: *"Any specific instructions related to this data or this HFC check session? This can be anything I should know before diving in."* Options: `"All good!"` / `Other`. Deliberately asked here, before any role-profiling judgment call (step 4 onward), so an `Other` answer can actually shape those calls rather than arriving too late to matter — apply it to A1/A2 judgment and to `role_map.yaml`/`modules.yaml` wherever it concretely applies.
   - **Completion** (only when step 6 found a signal): states the guess (or the explicit conflict framing) plus the downstream effect — "every other check runs on that subset only." When Completion also fires, the window is already at its 4-tab cap with the three tabs above plus this one — Specific instructions still always takes the 4th slot (it must run before role profiling), so Completion becomes its own immediately-following single-tab **window "Completion"** instead of a 5th tab in the same call. No such split when there's no completion signal to show.
8. Persist everything confirmed (including any corrections from step 7) to `hfc/config/role_map.yaml`: `entity_id`, `entity_id_sep`, `entity_label`, `dup_key_extra`, `country_mode`, `country`/`country_col`/`country_timezone_map`, `timezone`, `qualitative_text_cols`, `completion_primary_signal`, `completion_status_col`, `completion_status_complete_values`, `completion_roster_candidate`, `completion_roster_key_col`, `completion_primary_secondary_col`, `completion_primary_value`, `context_doc_path` (from step 1b, so a rebuild doesn't need to re-discover it).

### A2. Module confirmation (three windows: Keys & Hours, Dates/Variables/GPS, Media/Map/Grouping — plus the Wrap-up window shared with A3/A4)

1. Read `references/check_modules.md` and `references/interaction.md`.
2. Profile columns (names/types/labels only — no PII row dumps) and compute proposed defaults for every module (`default_modules()`), now using the roles confirmed in A1 — including the completion-aware M1 group source (Treatment/Control by default, via `detect_treatment_control_vars()`, falling back to geography only when no Treatment/Control column exists).
3. **Write the draft module config:**
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/preview_modules.R
   ```
   Writes `hfc/config/modules.yaml` — a commented, human-readable draft of every M1–M13 module's *proposed default* (on/off, description, thresholds/variables), one module per block, so there's a real file on disk the user can open directly while the windows below ask for confirmation. This IS the file that ends up governing the actual build — nothing separate gets written later, corrections just edit this same file (see step 8). Its real path gets stated later, in the Wrap-up window's Structure tab (step 7 below) — not here, since the file is only just being written.
4. **Important variables shortlist (unified for M6/M9/M13/M7) — mandatory, every run:** propose up to 10 variables using your own judgment about what's contextually important to this survey — read column names/labels/content, informed by (not limited to) the profile's numeric/ordinal candidate pools, not driven by numeric-ness alone. When two or more candidates are near-duplicates of each other (e.g. `treat` vs. `treat_ext`), silently keep only the single most reasonable one — never present both, never ask the user to pick between them. List them out in full in the Variables tab below (step 6) — no separate chat post needed, the tab's own text has no length cap. `guess_sentinel_codes()` scans these variables' value distributions for likely sentinel/missing codes (99, -99, -9999, …) — its own separate tab, same window.
   Additionally, for M7 Missingness specifically, read through the full column list and select ~20 more variables (any type, not just numeric) you judge important for missingness reporting — broader than the unified shortlist above. This is agent judgment only: no `AskUserQuestion` confirmation, write directly to `hfc/config/role_map.yaml`'s `missingness_extra_vars`. An RA who disagrees with the picks edits that file directly — there is no in-chat correction path for this specific list.
5. **Window "Keys & Hours" — up to 4 tabs:**
   - **Duplicate key**: restate the auto-resolved key from A1.
   - **Form version** (only if 2+ versions detected): guessed version column + date-range↔version mapping.
   - **Duration column** (M4): the guessed column. Its 3 SD outlier threshold is a fully fixed default, never mentioned in any tab (stricter than M6/M9/M7's thresholds, which are still stated elsewhere). When `roles$section_time_pairs` also found section-level start/end timestamps (e.g. `introduction_start`/`introduction_end`, `training_start`/`training_end` — common when a survey times its sections separately), extend this same tab's options with a real named choice instead of a separate tab: "Looks good!" (overall duration only, default) / "Also check timing by section: `<Section1>, <Section2>, ...`" / `Other`. If chosen, persist the selected pairs to `modules.yaml`'s `M4.section_pairs` — each opted-in section then gets its own SD-outlier flagging (`long_duration`/`short_duration`, same fixed 3 SD threshold) alongside the overall duration check, not instead of it.
   - **Work hours** (M5): the guessed work-hours window + weekend flag, as one rule — but offer real partial-accept options, not just Looks good!/Other: "Looks good!" (flag both) / "Flag work-hours only" / "Flag weekend only".
6. **Window "Dates, Variables & GPS" — up to 4 tabs:**
   - **Last date**: the detected max date, states it drives the Last Day tab. Options: "Looks good!" / "Include more days (I will specify)" — if chosen, the Last Day tab's filter must support a date range, not single-date equality.
   - **Variables**: the full important-variables list from step 4, spelled out by name (not truncated).
   - **Sentinel codes**: `guess_sentinel_codes()`'s guess for the variables above.
   - **GPS threshold** (M8): the guessed distance threshold (default 300m).
   M6's fixed 3 SD threshold, M9's fixed 90% threshold, and M7's three missingness thresholds (50% variable-issue / 90% enumerator-pool / 50% enumerator-personal) are all fully silent fixed defaults now — not mentioned in any tab, same treatment as M4's SD rule.
7. **Window "Media, Map & Grouping" — up to 4 tabs:**
   - **Media columns** (M11): restate the media-indicating columns from A1.
   - **Map focus**: the default (Country).
   - **Add geography?** (only if a Treatment/Control column was found in step 2): real Yes/No options, not Other — "No, Treatment/Control only (recommended)" / "Yes, add geography too". Only surfaced when a Treatment/Control column actually exists; when it doesn't, geography becomes the default automatically, no tab needed.
   - **Group label**: `derive_group_label()`'s guess for what `roles$group` (e.g. `school_id`) is called throughout the report/tracking sheet.
8. **Window "Wrap-up" — up to 4 tabs, closes out A2/A3/A4-prep together:**
   - **Consent mapping** — its own tab, never bundled with anything else: state which column maps to assent, consent, and audio-consent, explicitly naming each. Assent and consent are different concepts (minor's own agreement vs. guardian/adult consent); get this right.
   - **Extra checks**: "No additional checks" (recommended) / Other (free text) for a custom M10 check. Mandatory every run — never skip, never treat silence elsewhere as an implicit "no."
   - **Structure**: by this point `hfc/structure.html` (product tree map, A3) has been written and opened in the browser. State the real, absolute path to `hfc/config/modules.yaml` (written in step 3) here — this is the first point it's mentioned. Three options: "Looks good, continue!" / "I edited the specifications" (re-read `modules.yaml` before proceeding, use the user's edited version) / "Change the plan (I will type in Other)".
   - **Excel columns**: the standard `issue_tracking.xlsx` schema (`Status` Open default; any Open row with a non-empty Comment is eligible for the agent to interpret and resolve in Pipeline B — Accepted/Revise are advisory triage values the field/RA can still set, not a hard gate; Resolved/Needs Review are set by the agent, always in the resolutions clone first, never written straight to the live file — see `references/issue_tracking_schema.md`). "Looks good!" / "Modify columns (I will type in Other)".
9. **If the user answers Other on Extra checks:** propose a check name + `hfc/code/checks/<name>.R`, confirm briefly in chat, implement and register under M10/`custom`, and write its ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (`custom.<name>.label` / `.description`) so `hfc/outputs/report.html` can show it under the M10 section (schema in `references/check_modules.md`).
10. Apply any chat corrections from the three module-confirmation windows directly to the already-written `hfc/config/modules.yaml` (edit the specific keys in place — its comments and every other module's settings stay untouched), then write the remaining `hfc/config/role_map.yaml` fields: `important_vars`, `missingness_extra_vars`, `last_date`, `treatment_control_col`, `geo_group_col`, `geo_group_opted_in`, `map_focus`, `group_label`. If the user said they edited `modules.yaml` directly instead (Wrap-up window's Structure tab), re-read it now rather than trusting your own draft.

### A3. Outline + product structure

1. Write / update `hfc/structure.html` (product tree map). Open it in the browser.
2. No separate confirmation here — folded into the Wrap-up window's Structure tab (A2 step 8) once `modules.yaml`'s real path is also known.

### A4. Build

1. **OneDrive — informational, not a gate here:** A0 already confirmed `config.json` (incl. OneDrive Folder Directory) is fully configured and reachable before A1 even started, so there's no choice left to make. State the configured folder inline in chat ("Using your configured OneDrive folder: `<path>`") and move on — no AskUserQuestion.
2. Issue tracking columns: confirmed in the Wrap-up window's Excel Columns tab (A2 step 8), not a separate gate here.
3. Report is always HTML — no separate gate, nothing else is implemented.
4. Write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from confirmed options (A1 + A2).
5. Run builder — **silent, no `--open`.** This is a disk-only write: the Summary narrative (step 6) and README (step 7) haven't been drafted yet, so the report isn't complete enough to show anyone. Opening it here is exactly the "several confusing versions in the browser" failure mode to avoid — the one and only open happens in step 8, once everything below is actually final.
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R
   # equivalently:
   Rscript "${CLAUDE_SKILL_DIR}/scripts/run_setup_build.R"
   ```
   (No `--no-onedrive` flag exists — the builder itself calls `require_fieldloop_config_ready()` and stops with setup instructions if `config.json` isn't fully configured, same as A0.)
   On a rebuild (an `issue_tracking.xlsx` already exists), the builder does **not** overwrite it — it writes `merged_issue_tracking.xlsx` and prints `MERGE_PENDING`. Show the user what changed (preserved rows unchanged, genuinely-new findings appended, nothing dropped), then one tab, window "Merge confirm": *"Rebuild found `<N>` new findings and kept `<M>` existing rows unchanged. Merge this into the live issue_tracking.xlsx?"* — "Yes, merge (recommended)" / "Wait, let me review first" (show the full row-by-row diff before merging) — then run:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/commit_merged_issue_tracking.R merged_issue_tracking.xlsx
   ```
   This is the only script that ever overwrites the live shared file.
6. **Draft the Summary narrative** — see `assets/summary_message_example.md` for the calibration target (a real, annotated example). Read `hfc/outputs/issues.csv` and draft a short Slack-register message that:
   1. Names real places/entities/numbers with specificity — never "several schools," always "17 schools" / "School ID 4 Gashanga."
   2. Leads with completion status vs. target, using M1's completion accounting (target-vs-actual, or primary/secondary composition — whichever signal applies; see A1).
   3. Reports completion % by group, defaulting to Treatment/Control when that grouping exists.
   4. Calls out M2 duplicates by name with the real `issue_tracking.xlsx` path and an `@mention`-style placeholder for follow-up.
   5. Reports M4 duration as mean **and** median, in minutes.
   6. Closes with a data/media-presence gap statement at entity/group granularity — read `issues.csv`'s M11/M7 rows and translate into "were not available in N schools — schools X, Y, Z," not merely restating M11's raw one-line finding.
   Write it to `hfc/config/summary_message.md` (plain text, overwritten each time — not `module_notes.yaml`), post it in chat as an FYI, then rebuild the report so it's folded in before the final open:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R
   ```
   (No `--open` needed here — step 8 opens it once, after the README is drafted.)
7. Draft project `README.md` automatically — no confirmation needed.
8. **Now open `hfc/outputs/report.html` — the only time it opens in Pipeline A.** The file on disk already reflects step 6's rebuild (Summary narrative included), so open it directly (`utils::browseURL()`, or the OS `open`/`start` command) rather than re-running the builder — a re-run isn't needed just to open a file that's already final. Tell user: `issue_tracking.xlsx` and a copy of the report itself now live in the shared OneDrive-synced folder (access already granted via the one-time manual folder share) — it'll sync to the cloud automatically. Later: **Process HFC feedback**.

---

## Pipeline B — Post-feedback

There is no built-in fix-classification engine. **You (the agent) read and interpret each eligible row yourself and write the fix code** — same philosophy as M10 custom checks: no fixed catalog of fix types, decide per row. Trigger: any row with `Status == Open` **and** a non-empty Comment is eligible — there is no separate Accepted gate. Everything in this pipeline operates on today's `resolutions/<date>_issues_resolution.xlsx` clone, never on `issue_tracking.xlsx` directly — the live shared file is only ever updated by the explicit merge-and-commit step at the end.

1. Create (or reuse) today's resolutions clone:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R clone
   ```
   Copies the current `issue_tracking.xlsx` to `resolutions/<YYYYMMDD>_issues_resolution.xlsx`. A same-day second pass reuses the existing clone rather than discarding in-progress work.
2. List eligible rows:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R list-open
   ```
   Writes `hfc/outputs/fix_candidates.csv` — one row per `Status=Open` + non-empty Comment finding in today's clone, with full context (Issue, Comment, Entity ID, Variable, Value, Issue Category, Issue ID).
3. **Window "Proceed," one tab:** *"Found `<N>` rows with a Comment and Status=Open. I'll interpret each and apply a fix in one pass per row."* — "Proceed with all `<N>` (recommended)" / "Only some of them (I will type in Other)".
4. For **each** eligible row, in turn, in a single pass — interpret the Comment, propose Corrections, apply the fix, and set Status, all at once:
   a. Read its `Issue`, `Comment`, and other fields; decide the concrete technical fix the Comment is asking for (e.g. drop the row, cap a value, recode a field), and draft the Corrections text describing what you did.
   b. Write `hfc/code/resolutions/<Issue ID, sanitized>.R` defining `fix(ds) -> ds` that implements it.
   c. Apply it:
      ```bash
      Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R apply --finding-id "<Issue ID>" --corrections "<what you did>"
      ```
      This loads `<sibling of Input Data Directory>/intermediate/<stem>.<ext>` if a prior fix already exists (else the original file in the Input Data Directory — never mutated), applies your `fix(ds)`, saves the result back to `<sibling of Input Data Directory>/intermediate/<stem>.<ext>` (one evolving file, so fixes accumulate), and writes the Corrections text + `Status = Resolved` into today's resolutions clone **only** — `issue_tracking.xlsx` is never touched by this step.
   d. If you can't confidently resolve a row, run `apply_feedback.R needs-review --finding-id "<Issue ID>"` instead — sets `Status = Needs Review` in the clone.
5. Once all rows are handled, fold the clone back into the live file:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/merge_resolutions.R
   ```
   Writes `merged_issue_resolutions.xlsx` next to `issue_tracking.xlsx` — for matched Issue IDs, Status/Corrections/Correction Author come from today's clone, every other column (in case the field/RA edited something concurrently) comes from the live file untouched; unmatched live rows pass through unchanged.
6. **Window "Commit," one tab:** *"`<N>` rows Resolved, `<M>` Needs Review. This will overwrite the live shared issue_tracking.xlsx."* — "Confirm merge (recommended)" / "Wait, let me review first" (show the row-by-row diff before committing) — then commit:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/commit_merged_issue_tracking.R merged_issue_resolutions.xlsx
   ```
7. **Rebuild the report — mandatory, every pass:**
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/rebuild_report.R
   ```
   Re-runs M1–M13 against the latest data (`<sibling of Input Data Directory>/intermediate/` if any fixes were applied, else the original file in the Input Data Directory) using the project's stored config, then drops any finding from the report whose live-tracking Status is now `Resolved`, or whose Issue ID no longer appears in `issue_tracking.xlsx` at all — display-only: the xlsx itself keeps full history unchanged, this only affects what `report.html` shows. Re-read `hfc/outputs/issues.csv` and redraft the Summary narrative (`hfc/config/summary_message.md`, same approach as A4 step 6) against these fresh findings, then re-run with `--open`:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/rebuild_report.R --open
   ```
8. Tell the user which rows were Resolved vs. Needs Review, and that `<sibling of Input Data Directory>/intermediate/<stem>.<ext>` now holds the latest fixed data (raw unchanged).

---

## What not to do

- Do not overwrite the original microdata file.
- Do not start Pipeline A when the user clearly asked for post-feedback (and vice versa).
- Do not invent access dates, exhibit IDs, or column names that are not in the data.
- Do not skip or silently bypass the config pre-flight check (A0) — if Input Data Directory, OneDrive Folder Directory, or Code Output Directory isn't configured or isn't reachable, stop and direct the user to `install.R` + confirming OneDrive desktop sync is running + editing `config.json`, never proceed with a build that has nowhere to write `issue_tracking.xlsx`.
- Do not show an entity's name anywhere (report or `issue_tracking.xlsx`) unless the user has explicitly set `entity_display: name` in `role_map.yaml` — Entity ID-only is the de-identification default, never overridden silently or by guess.
- Do not require monorepo gold data, `eval/`, `verify_all`, or SimUser for product runs.
- Do not use typed mega-replies (`M1=Y M2=…`) or long option menus as the primary confirmation UX — always guess first, correct if wrong (see Interactive confirms above).
- Do not silently guess the Entity ID without naming the underlying column in Tab 1's message — a wrong pick must be visibly correctable.
- Do not scatter product dirs outside the Code Output Directory — everything lands under `<Code Output Directory>/hfc/`.
- Do not flag expected skip-logic blanks as missing.
- Do not skip or silently auto-answer the Extra-checks tab (A2, Wrap-up window) after module confirmation.
- Do not skip the country/timezone confirm in Tab 1, or trust a resolved country→timezone lookup without showing it back for confirmation.
- Do not infer the data-collection country from the input folder's name/basename — read geography from the data itself.
- Do not skip stating the last date of data collection in its own tab (A2, Dates/Variables/GPS window) — it drives the Last Day tab.
- Do not let incomplete/non-surveyed rows leak into M2–M13 once a "status" completion signal has confirmed which rows to filter out.
- Do not run per-row file-hygiene checks for M11 — the only check is a media-indicating column that's completely empty across every surveyed row.
- Do not confuse assent and consent, and do not bundle the Consent tab (A2, Wrap-up window) with any other module.
- Do not present two near-duplicate variables (e.g. `treat` vs. `treat_ext`) as if they were independently meaningful — silently keep the one most reasonable one.
