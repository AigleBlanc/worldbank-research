---
name: hfc-fieldloop
description: >-
  Drop-in HFC FieldLoop skill for a survey project folder in VS Code + Claude Code.
  Use when the user says "Run HFC FieldLoop", "Start FieldLoop", "Process HFC feedback",
  "Run FieldLoop fixes", or "Apply field feedback", or invokes /hfc-fieldloop. Discovers
  data/form, confirms check modules with AskUserQuestion option cards, builds the HTML
  report and checks under hfc/, and keeps one shared issue_tracking.xlsx in OneDrive
  (required — no local fallback), or runs the post-feedback fix pipeline, writing
  agent-authored fixes to data/intermediate/.
---

# HFC FieldLoop (drop-in project skill — Claude Code)

Copy this folder into a survey project as **`.claude/skills/hfc-fieldloop/`** (Claude Code discovers skills there). The **survey project root** is the parent of `.claude/` (three levels above this skill directory). Product docs: `README.md`, skill tree map: `structure.html`, deps: `install.R`.

Supporting files resolve via `${CLAUDE_SKILL_DIR}` (this skill directory) or relative paths from the survey root:

```bash
Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --open
Rscript "${CLAUDE_SKILL_DIR}/scripts/run_setup_build.R" "<project_root>" --open
```

**Built product** (`config/`, `instruments/`, `registry/`, `outputs/`, `code/` — with `code/checks/` and `code/resolutions/`) always lands under **`hfc/`** next to `data/raw/` and this skill. `issue_tracking.xlsx` itself lives entirely in OneDrive (required — see A0c), not under `hfc/`. Open `hfc/structure.html` in a browser and AskUserQuestion **Continue** before writing the full package.

Two pipelines — choose by the user's prompt (see `references/prompts.md`):

| Intent | Trigger examples | What you do |
|---|---|---|
| **A. Setup** | "Run HFC FieldLoop" (+ `for <project>` if workspace is a monorepo) | Discover → AskUserQuestion confirms → `hfc/` outline → build → open HTML |
| **B. Post-feedback** | "Process HFC feedback" (+ `for <project>` when needed) | Clone → list Open+RIL-Comment rows → per row: read + write fix code → apply (single pass) → merge back → confirm → commit |

Authority (read; do not invent standards):

- `references/interaction.md` — **AskUserQuestion** UX (required for all gates; multiple-choice, not typed mega-strings)
- `references/check_modules.md` — M1–M13 option-card specs + required-fields gate + nested skip-logic
- `references/issue_tracking_schema.md` — the issue-tracking file's schema, including the `Status` lifecycle
- `references/checklist.md` — package completeness
- `references/flags.md` — failure modes (incl. F19–F29)
- `references/prompts.md` — exact trigger phrases
- `references/ai_use.md` — no PII to commercial AI

Helpers (prefer `Rscript` rather than reimplementing):

- `scripts/lib/discover.R` — find/create `data/raw`, classify data vs form
- `scripts/run_setup_build.R` — build after modules confirmed (project root as arg); writes under `hfc/`
- `scripts/apply_feedback.R` — post-feedback CLI (`clone` / `list-open` / `apply` / `needs-review`); fix logic is agent-authored, see `scripts/lib/apply_feedback_helpers.R`
- `scripts/merge_issues.R` / `scripts/merge_resolutions.R` — fold a dated snapshot / resolutions clone back into `issue_tracking.xlsx`, producing a `merged_*.xlsx` for the agent to review
- `scripts/commit_merged_issue_tracking.R` — the only script that ever overwrites the live `issue_tracking.xlsx`, run only after explicit AskUserQuestion confirmation
- `assets/issue_tracking_template.csv` — schema template
- `assets/README_template.md` / `assets/README_example.md` — draft project README on setup
- `assets/check_templates/` — M1–M13 real, runnable per-module scripts, copied into `hfc/code/checks/` at build time (same logic as `scripts/lib/run_checks.R`'s `check_mN()` functions, `scripts/lib/media.R` for M12)
- `scripts/lib/media.R` — detect media cols, media folder, M12 file checks
- `scripts/lib/geo_timezone.R` — country → IANA timezone lookup/resolver for M5
- `scripts/lib/form_logic.R` — SurveyCTO relevance / nested skip-logic helper + M4's group/section parsing
- `scripts/lib/product_structure.R` — write `hfc/structure.html`

## Interactive confirms (AskUserQuestion)

**Required.** Read and follow `references/interaction.md`.

- Use the **AskUserQuestion** tool for every gate (Claude Code multiple-choice UI). Do not ask the user to type `M1=Y M2=…` or similar mega-strings.
- **2–4 options per question**; Claude Code supplies free-text **Other** automatically — do **not** add an explicit `Other` option.
- **1–4 questions** per AskUserQuestion call; one call per assistant turn when sequencing gates.
- Fallback only if AskUserQuestion is unavailable: short numbered list with the same options; user replies with a single number/letter — still not long free-form module strings.

## Operating principles

1. Phases that write files wait for explicit AskUserQuestion confirmation (no silent proceed).
2. Never mutate original microdata in `data/raw/` — agent-authored fixes write to `data/intermediate/<stem>.<ext>` instead (one evolving file, sibling of `data/raw/`).
3. Confirm via **option cards**, not free-text module strings. Max ~8–12 cards after data confirm — never 100 per-column questions.
4. Feedback: **one shared file**, `issue_tracking.xlsx` — edited collaboratively by the agent, the RA, and the field team on the same file (RIL Comment/Corrections/Status all live in the same sheet; no separate audit twin). OneDrive is **required** (no local fallback in the product — see A0c): once `assets/lib/sync_folder.json` has `"enabled": true` and `"local_path"` pointed at a folder the OneDrive desktop app is syncing, that folder is the **sole store** — every read/write is plain file I/O against it, and OneDrive's own sync client (not this skill) propagates changes to the cloud, so there is never a separate local-only copy. Two dated-snapshot subfolders live alongside it, inside the same synced folder: `intermediate/<YYYYMMDD>_issue_tracking.xlsx` (one per setup-build run) and `resolutions/<YYYYMMDD>_issues_resolution.xlsx` (the agent's working clone during a "Process HFC feedback" pass) — see `references/issue_tracking_schema.md`. Folder location lives in the skill's own `assets/lib/sync_folder.json` — the only file that matters, edited directly, no per-project override, no auth step or secrets in this package. The folder is then shared manually (by whoever owns it) with collaborators via OneDrive's "Specific people" sharing UI.
5. After HTML build, auto-open with `utils::browseURL()` (or OS `open`).
6. **Must** write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from the user's **selected** options **before** calling the builder; also write `hfc/config/module_notes.yaml` whenever a custom check was confirmed (step 8 below).
7. M11 (Survey-Specific) has no built-in checks and defaults to **off / empty** — every M11 finding comes from a custom check the agent writes for this survey's specific content, driven entirely by what the user describes at the Additional-checks gate (step 8).
8. **Additional-checks gate is mandatory, every run (F23):** immediately after module cards/Accept-all, always run the "Additional checks?" AskUserQuestion (`No additional checks` recommended / Other automatic). Never infer "no" silently, never fold it into the pace question, never skip it because Accept-all was chosen. If Other, also write the custom check's ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (see step A2.7).
9. Draft project-root `README.md` from `assets/README_template.md`; confirm with AskUserQuestion once. Point to `references/ai_use.md`.
10. **M12 media:** if audio/image filename columns exist, propose M12 ON. AskUserQuestion for media folder if not discovered. Proceed with column-only checks if folder missing. Never put filename cols under M13.
11. **Required-fields hard gate:** after data confirm, and before any module cards, confirm FIVE fields in sequence — (a) Entity ID (single column, or a confirmed multi-column composite key; shortlist ≤3/≤4 candidates, F20) — the analysis-unit identifier, not necessarily row-unique, (b) Entity Label — what to call it in the HTML report (e.g. "Student ID"), display-only, (c) the duplicate-check key (Entity ID alone, auto-resolved when already unique, or Entity ID + confirmed extra column(s) like round/wave, F27), (d) country/countries of data collection + resolved timezone, always shown back for confirmation, never trusted silently (F24), and (e) last date of data collection, used for report-wide bold-highlighting and the Last Day tab (F25). Persist all five to `hfc/config/role_map.yaml`.
12. **Nested questions:** when form `relevant` says a child item is skipped, do not flag blanks as missing (F22).
13. All product code/artifacts under **`hfc/`** (F21).
14. **Report-wide sort & highlight:** every table sorts by enumerator, then unique ID, then date (most recent first); every finding matching the confirmed last date renders bold, and appears in the dedicated Last Day tab.

---

## Pipeline A — Setup

### A0. Resolve project root

**Survey project root** = folder containing `data/raw/` for *this* survey, and `.claude/skills/hfc-fieldloop/` when this skill is installed as a drop-in. Not the VS Code workspace root when that workspace is a monorepo.

Resolution order:

1. **Named in the prompt** — e.g. `for test/malawi1`, `project: malawi1`, `@test/malawi1` → use that path.
2. **Skill lives at `<survey>/.claude/skills/hfc-fieldloop/`** — `project_root = dirname(dirname(dirname(skill_dir)))` (parent of `.claude/`).
3. Otherwise **AskUserQuestion**: list up to 4 candidate project folders (Other is automatic).

Never run discover/build against the monorepo root when a nested survey project was named or chosen.

If packages may be missing: `Rscript <project_root>/.claude/skills/hfc-fieldloop/install.R` (or `Rscript "${CLAUDE_SKILL_DIR}/install.R"`).

### A0b. Config-reuse gate

Immediately after project root is resolved, check whether `hfc/config/role_map.yaml` **and** `hfc/config/modules.yaml` already exist (a prior run). If neither exists, skip straight to A1 — nothing to reuse yet. If they exist, **AskUserQuestion** before touching anything else:

- **Reuse existing configuration and rebuild** (recommended) — proceed straight to A4 build with the saved configs; skip A1's required-fields gate and A2's module cards (the existing reload logic in `run_setup_build.R` already handles this — no new code needed).
- **Start fresh** — delete `hfc/config/role_map.yaml` and `hfc/config/modules.yaml` (only those two files), then run A1–A4 normally as a first-ever setup.
- **Open the config files for me to edit, then continue** — tell the user the paths (`hfc/config/role_map.yaml`, `hfc/config/modules.yaml`), wait for them to confirm they're done editing, then proceed straight to A4 build; the existing reload logic picks up their hand-edited values automatically.

### A0c. OneDrive pre-flight (mandatory, every run)

OneDrive is required — there is no local-only mode. It's accessed as a plain local folder that the OneDrive desktop app keeps synced to the cloud, not via any API/sign-in — so before proceeding to A1, verify it's configured and reachable: `assets/lib/sync_folder.json` must have `"enabled": true` with a real `local_path` pointing at an existing (or creatable) local directory (this is exactly what `require_sync_folder_ready()` in `scripts/lib/issue_store.R` checks — every CLI script in this skill calls it automatically and `stop()`s with the same instructions below, so this gate is also enforced in code, not just in this doc).

- **If it's already configured and reachable:** say so briefly in chat (name the configured folder) and continue to A1 — no AskUserQuestion needed, there's no choice to make.
- **If it isn't configured, or the path isn't reachable:** stop here. Tell the user, in this order: (1) run `Rscript <skill_dir>/install.R` if packages might be missing, (2) make sure the OneDrive desktop app is installed and signed in on this machine, and note the local folder it syncs to, (3) edit `assets/lib/sync_folder.json` — set `"enabled": true` and `"local_path"` to that folder's absolute path — this is skill-level config, applies to every project using this skill copy. Do not proceed with Pipeline A or B until they confirm this is done and the pre-flight succeeds.

### A1. Discover data + survey

1. Run discovery under `project_root` (not workspace root unless they are the same).
2. Search `data/raw/`, `data/`, `instrument/`, project root for microdata and optional form.
3. **If found:** show path, size, nrow/ncol (data) or sheet names (form). **AskUserQuestion** (≤4 options; Other automatic):
   - Use discovered paths (recommended)
   - Pick different paths
   - Wait — I will upload / drop files
4. **If not found / Wait:** create `data/raw/` if missing; tell user to drop files; AskUserQuestion again after they continue. Do not proceed without data.
5. Form optional: proceed data-only; note M11 / M3 / nested logic weaker.
6. **Required-fields gate (mandatory, immediately after data confirm, before any module cards) — five sequential AskUserQuestion sub-gates, in this order:**
   1. **Entity ID:** the analysis-unit identifier (person/household/school/whatever level the user wants) — ask single column vs. combine multiple columns (e.g. household_id + member_id). If single: shortlist ≤3 candidates (name/label/uniqueness rationale via `shortlist_entity_ids()`). If composite: `multiSelect: true` over ≤4 candidates from `shortlist_composite_entity_ids()`; after selection, report joint uniqueness inline in chat. Note: Entity ID is **not** necessarily row-unique (e.g. a household surveyed across multiple rounds keeps the same Entity ID) — that's what the next sub-gate is for. Do not proceed without a choice (F20).
   2. **Entity Label:** ask what to call the Entity ID in the HTML report (e.g. "Student ID", "Household ID") — offer "Entity ID" (generic, recommended) vs. Other (free text). Display-only: the xlsx/csv exports always keep the fixed generic "Entity ID" header regardless of this answer.
   3. **Duplicate-check key:** check whether Entity ID (as just confirmed) is already 100% unique per row in the raw data. If yes, auto-resolve to "Entity ID alone" and say so inline in chat — do **not** fire an AskUserQuestion for this common case. If Entity ID repeats, ask: *"Entity ID repeats in your data — does that reflect real duplicates, or do you need extra columns (e.g. round/wave) to check for true duplicates?"* — options: Entity ID alone / add detected candidate column(s) (`detect_duplicate_key_candidates()`, `multiSelect: true`, ≤4) / Other. Do not skip when Entity ID repeats (F27).
   4. **Country(ies) + timezone:** ask single vs. multiple countries. If multiple, shortlist a country-indicator column (`shortlist_country_columns()`), resolve each value's timezone (`resolve_country_timezone_column()` in `scripts/lib/geo_timezone.R`), and **always show the resolved timezone back for confirmation/override** — never treat an unconfirmed lookup as live (F24). If single, confirm one country → one global timezone.
   5. **Last date of data collection:** offer the detected max date from the data (recommended) vs. a different date (Other). Do not skip this gate (F25) — it drives report-wide bold-highlighting and the Last Day tab.
   Persist all five to `hfc/config/role_map.yaml` (`entity_id`, `entity_id_sep`, `entity_label`, `dup_key_extra`, `country_mode`, `country`/`country_col`/`country_timezone_map`, `timezone`, `last_date`).
7. If media filename columns exist: **AskUserQuestion** for media folder (use discovered / column-only; Other automatic).

### A2. Audit + module confirmation

1. Read `references/check_modules.md` and `references/interaction.md`.
2. Profile columns (names/types/labels only — no PII row dumps). Use `format_module_cards` / profile for recommended defaults.
3. **AskUserQuestion (pace):**
   - Accept all recommended defaults (recommended)
   - Review module-by-module
4. If **Accept all**: apply starred defaults from profile; skip per-module cards unless M3 (Form Version)/M7 (Missingness)/M9 (Straightlining)/M11/M12 need a quick confirm.
5. If **Review**: AskUserQuestion cards per `check_modules.md` (on/off, key columns, thresholds). Respect 2–4 options per question; split into sequential asks. Do not ask for typed `M1=Y M2=…`. **M7 Missingness is a genuine sequential dependency:** confirm the variable shortlist first, then confirm sentinel missing-codes in a follow-up question that names those specific confirmed variables — the second question cannot be authored as a static card ahead of time.
6. Never one free-text question per variable.
7. **Additional checks — mandatory, every run, cannot be skipped (F23):** immediately after steps 3–6, always run a separate AskUserQuestion — `No additional checks` (recommended) (Other automatic for custom). This fires regardless of whether the user picked Accept-all or Review in step 3; do not treat Accept-all as an implicit "no" here.
8. **If the user answers Other in step 7:** propose a check name + `hfc/code/checks/<name>.R`, confirm via AskUserQuestion, implement and register under M11/`custom`, **and** write its ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (`custom.<name>.label` / `.description`) so `hfc/outputs/report.html` can show it under the M11 section (schema in `references/check_modules.md`).

### A3. Outline + product structure

1. Write / update `hfc/structure.html` (product tree map). Open it in the browser.
2. Briefly propose tracking/HTML sections, feedback approach, README plan in chat.
3. **AskUserQuestion:** Continue with this structure (recommended) (Other automatic).

### A4. Build

1. **OneDrive — informational, not a gate here:** A0c already confirmed OneDrive is configured and reachable before A1 even started, so there's no choice left to make. State the configured folder inline in chat ("Using your configured OneDrive folder: `<local_path>`") and move on — no AskUserQuestion.
2. **AskUserQuestion — Issue tracking columns:** Keep the standard columns (recommended) / Modify columns. Schema: `Status` (Open default; any Open row with a non-empty RIL Comment is eligible for the agent to interpret and resolve in Pipeline B — Accepted/Revise are advisory triage values the field/RA can still set, not a hard gate; Resolved/Needs Review are set by the agent, always in the resolutions clone first, never written straight to the live file — see `references/issue_tracking_schema.md`).
3. **AskUserQuestion — Map focus** (if GPS on): Country / City / World. Store in `hfc/config/role_map.yaml` (`map_focus`).
4. **AskUserQuestion — Report:** HTML (recommended).
5. Write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from confirmed options.
6. Run builder:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R "<project_root>" --open
   # equivalently:
   Rscript "${CLAUDE_SKILL_DIR}/scripts/run_setup_build.R" "<project_root>" --open
   ```
   (No `--no-onedrive` flag exists — the builder itself calls `require_sync_folder_ready()` and stops with setup instructions if OneDrive isn't reachable, same as A0c.)
   On a rebuild (an `issue_tracking.xlsx` already exists), the builder does **not** overwrite it — it writes `merged_issue_tracking.xlsx` and prints `MERGE_PENDING`. Show the user what changed (preserved rows unchanged, genuinely-new findings appended, nothing dropped), **AskUserQuestion** to confirm, then run:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/commit_merged_issue_tracking.R "<project_root>" merged_issue_tracking.xlsx
   ```
   Warn the user first that this replaces the live shared file — this is the only script that ever does so.
7. Draft project `README.md`; **AskUserQuestion:** Write this README (recommended).
8. Auto-open `hfc/outputs/report.html`. Tell user: `issue_tracking.xlsx` and a copy of the report itself now live in the shared OneDrive-synced folder (access already granted via the one-time manual folder share) — it'll sync to the cloud automatically. Later: **Process HFC feedback** (+ project path if monorepo).

---

## Pipeline B — Post-feedback

There is no built-in fix-classification engine. **You (the agent) read and interpret each eligible row yourself and write the fix code** — same philosophy as M11 custom checks: no fixed catalog of fix types, decide per row. Trigger: any row with `Status == Open` **and** a non-empty RIL Comment is eligible — there is no separate Accepted gate. Everything in this pipeline operates on today's `resolutions/<date>_issues_resolution.xlsx` clone, never on `issue_tracking.xlsx` directly — the live shared file is only ever updated by the explicit merge-and-commit step at the end.

1. Create (or reuse) today's resolutions clone:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R clone "<project_root>"
   ```
   Copies the current `issue_tracking.xlsx` to `resolutions/<YYYYMMDD>_issues_resolution.xlsx`. A same-day second pass reuses the existing clone rather than discarding in-progress work.
2. List eligible rows:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R list-open "<project_root>"
   ```
   Writes `hfc/registry/fix_candidates.csv` — one row per `Status=Open` + non-empty RIL Comment finding in today's clone, with full context (Issue, RIL Comment, Entity ID, Variable, Value, Issue Category, Issue ID).
3. **AskUserQuestion:** Proceed with these N rows (recommended).
4. For **each** eligible row, in turn, in a single pass — interpret the RIL Comment, propose Corrections, apply the fix, and set Status, all at once:
   a. Read its `Issue`, `RIL Comment`, and other fields; decide the concrete technical fix the RIL Comment is asking for (e.g. drop the row, cap a value, recode a field), and draft the Corrections text describing what you did.
   b. Write `hfc/code/resolutions/<Issue ID, sanitized>.R` defining `fix(ds) -> ds` that implements it.
   c. Apply it:
      ```bash
      Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R apply "<project_root>" --finding-id "<Issue ID>" --corrections "<what you did>"
      ```
      This loads `data/intermediate/<stem>.<ext>` if a prior fix already exists (else the original `data/raw/` file — never mutated), applies your `fix(ds)`, saves the result back to `data/intermediate/<stem>.<ext>` (one evolving file, so fixes accumulate), and writes the Corrections text + `Status = Resolved` into today's resolutions clone **only** — `issue_tracking.xlsx` is never touched by this step.
   d. If you can't confidently resolve a row, run `apply_feedback.R needs-review "<project_root>" --finding-id "<Issue ID>"` instead — sets `Status = Needs Review` in the clone.
5. Once all rows are handled, fold the clone back into the live file:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/merge_resolutions.R "<project_root>"
   ```
   Writes `merged_issue_resolutions.xlsx` next to `issue_tracking.xlsx` — for matched Issue IDs, Status/Corrections/Correction Author come from today's clone, every other column (in case the field/RA edited something concurrently) comes from the live file untouched; unmatched live rows pass through unchanged.
6. Show the user a summary of what changed (which rows go Resolved/Needs Review), **AskUserQuestion** to confirm, warning that this replaces the live shared file, then commit:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/commit_merged_issue_tracking.R "<project_root>" merged_issue_resolutions.xlsx
   ```
7. Tell the user which rows were Resolved vs. Needs Review, and that `data/intermediate/<stem>.<ext>` now holds the latest fixed data (raw unchanged).

---

## What not to do

- Do not overwrite the original microdata file.
- Do not start Pipeline A when the user clearly asked for post-feedback (and vice versa).
- Do not invent access dates, exhibit IDs, or column names that are not in the data.
- Do not skip or silently bypass the OneDrive pre-flight check (A0c) — if `local_path` isn't configured or isn't reachable, stop and direct the user to `install.R` + confirming OneDrive desktop sync is running + editing `assets/lib/sync_folder.json`, never proceed with a build that has nowhere to write `issue_tracking.xlsx` (F29).
- Do not require monorepo gold data, `eval/`, `verify_all`, or SimUser for product runs.
- Do not use typed mega-replies (`M1=Y M2=…`) as the primary confirmation UX when AskUserQuestion is available (F19).
- Do not skip the unique-ID AskUserQuestion gate (F20).
- Do not scatter product dirs at project root — use `hfc/` (F21).
- Do not flag expected skip-logic blanks as missing (F22).
- Do not skip or silently auto-answer the Additional-checks AskUserQuestion gate after module confirmation (F23).
- Do not skip the country/timezone confirm gate, or trust a resolved country→timezone lookup without showing it back for confirmation (F24).
- Do not skip the last-collection-date AskUserQuestion gate (F25).
