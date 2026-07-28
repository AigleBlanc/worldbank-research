---
name: hfc-fieldloop
description: >-
  Drop-in HFC FieldLoop skill for a survey project folder in VS Code + Claude Code.
  Use when the user says "Run HFC FieldLoop", "Start FieldLoop", "Process HFC feedback",
  "Run FieldLoop fixes", or "Apply field feedback", or invokes /hfc-fieldloop. Discovers
  data/form, confirms check modules with AskUserQuestion option cards, builds product
  under hfc/ (HTML report + tracking + feedback Sheet twin), or runs the post-feedback
  fix pipeline to write *_resolved files.
---

# HFC FieldLoop (drop-in project skill — Claude Code)

Copy this folder into a survey project as **`.claude/skills/hfc-fieldloop/`** (Claude Code discovers skills there). The **survey project root** is the parent of `.claude/` (three levels above this skill directory). Product docs: `README.md`, skill tree map: `structure.html`, deps: `install.R`.

Supporting files resolve via `${CLAUDE_SKILL_DIR}` (this skill directory) or relative paths from the survey root:

```bash
Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --open
Rscript "${CLAUDE_SKILL_DIR}/scripts/run_setup_build.R" "<project_root>" --open
```

**Built product** (checks, config, report, registry, output, code, fixes) always lands under **`hfc/`** next to `data/raw/` and this skill. Open `hfc/structure.html` in a browser and AskUserQuestion **Continue** before writing the full package.

Two pipelines — choose by the user's prompt (see `references/prompts.md`):

| Intent | Trigger examples | What you do |
|---|---|---|
| **A. Setup** | "Run HFC FieldLoop" (+ `for <project>` if workspace is a monorepo) | Discover → AskUserQuestion confirms → `hfc/` outline → build → open HTML |
| **B. Post-feedback** | "Process HFC feedback" (+ `for <project>` when needed) | Read feedback → AskUserQuestion confirms → apply → `*_resolved` + `resolved` column |

Authority (read; do not invent standards):

- `references/interaction.md` — **AskUserQuestion** UX (required for all gates; multiple-choice, not typed mega-strings)
- `references/check_modules.md` — M1–M13 option-card specs + required-fields gate + nested skip-logic
- `references/feedback_schema.md` — required feedback columns including `status` / `resolved`
- `references/checklist.md` — package completeness
- `references/flags.md` — failure modes (incl. F19–F25)
- `references/prompts.md` — exact trigger phrases
- `references/ai_use.md` — no PII to commercial AI

Helpers (prefer `Rscript` rather than reimplementing):

- `scripts/lib/discover.R` — find/create `data/raw`, classify data vs form
- `scripts/run_setup_build.R` — build after modules confirmed (project root as arg); writes under `hfc/`
- `scripts/apply_feedback.R` — post-feedback pipeline
- `scripts/sync_feedback.R` — export/import local Sheet twin
- `assets/feedback_template.csv` — schema template
- `assets/README_template.md` / `assets/README_example.md` — draft project README on setup
- `assets/check_templates/` — M1–M13 skeletons (live logic: `scripts/lib/run_checks.R`, `scripts/lib/media.R`)
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
2. Never mutate original microdata in `data/raw/` except by writing a **new** `*_resolved.*` sibling.
3. Confirm via **option cards**, not free-text module strings. Max ~8–12 cards after data confirm — never 100 per-column questions.
4. Feedback: **two OneDrive Excel files** when configured — `main_file` (field) + `audit_file` (code), in a shared SharePoint/Team site folder — plus local `hfc/output/feedback_sheet.xlsx`. Site/folder location lives in project `hfc/config/onedrive.json` (copy from `assets/lib/onedrive.example.json`). Skill `assets/lib/onedrive.json` is placeholders only (`YOUR_TENANT`/`YOUR_SITE` are not live). Auth is delegated one-time interactive sign-in (`scripts/onedrive_auth_setup.R`, run once by the user outside Claude Code) — no secrets stored in this package. If OneDrive missing/not yet signed in, succeed with **local twin only**.
5. After HTML build, auto-open with `utils::browseURL()` (or OS `open`).
6. **Must** write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from the user's **selected** options **before** calling the builder; also write `hfc/config/module_notes.yaml` whenever a custom check was confirmed (step 8 below).
7. Default M11 (Survey-Specific) to **off / empty** unless form or heuristics find candidates; list 0–5 survey-specific options from *this* data only (split across asks if more than 4 choices).
8. **Additional-checks gate is mandatory, every run (F23):** immediately after module cards/Accept-all, always run the "Additional checks?" AskUserQuestion (`No additional checks` recommended / Other automatic). Never infer "no" silently, never fold it into the pace question, never skip it because Accept-all was chosen. If Other, also write the custom check's ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (see step A2.7).
9. Draft project-root `README.md` from `assets/README_template.md`; confirm with AskUserQuestion once. Point to `references/ai_use.md`.
10. **M12 media:** if audio/image filename columns exist, propose M12 ON. AskUserQuestion for media folder if not discovered. Proceed with column-only checks if folder missing. Never put filename cols under M13.
11. **Required-fields hard gate:** after data confirm, and before any module cards, confirm THREE fields in sequence — (a) unique identifier(s) (single column, or a confirmed multi-column composite key; shortlist ≤3/≤4 candidates, F20), (b) country/countries of data collection + resolved timezone, always shown back for confirmation, never trusted silently (F24), and (c) last date of data collection, used for report-wide bold-highlighting and the Last Day tab (F25). Persist all three to `hfc/config/role_map.yaml`.
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

### A1. Discover data + survey

1. Run discovery under `project_root` (not workspace root unless they are the same).
2. Search `data/raw/`, `data/`, `instrument/`, project root for microdata and optional form.
3. **If found:** show path, size, nrow/ncol (data) or sheet names (form). **AskUserQuestion** (≤4 options; Other automatic):
   - Use discovered paths (recommended)
   - Pick different paths
   - Wait — I will upload / drop files
4. **If not found / Wait:** create `data/raw/` if missing; tell user to drop files; AskUserQuestion again after they continue. Do not proceed without data.
5. Form optional: proceed data-only; note M11 / M3 / nested logic weaker.
6. **Required-fields gate (mandatory, immediately after data confirm, before any module cards) — three sequential AskUserQuestion sub-gates, in this order:**
   1. **Unique identifier(s):** ask single column vs. combine multiple columns (e.g. household_id + member_id). If single: shortlist ≤3 candidates (name/label/uniqueness rationale via `shortlist_submission_ids()`). If composite: `multiSelect: true` over ≤4 candidates from `shortlist_composite_id_candidates()`; after selection, report joint uniqueness inline in chat (not another gate — M2 Duplicates is the safety net for imperfect uniqueness). Do not proceed without a choice (F20).
   2. **Country(ies) + timezone:** ask single vs. multiple countries. If multiple, shortlist a country-indicator column (`shortlist_country_columns()`), resolve each value's timezone (`resolve_country_timezone_column()` in `scripts/lib/geo_timezone.R`), and **always show the resolved timezone back for confirmation/override** — never treat an unconfirmed lookup as live (F24). If single, confirm one country → one global timezone.
   3. **Last date of data collection:** offer the detected max date from the data (recommended) vs. a different date (Other). Do not skip this gate (F25) — it drives report-wide bold-highlighting and the Last Day tab.
   Persist all three to `hfc/config/role_map.yaml` (`id`, `id_sep`, `country_mode`, `country`/`country_col`/`country_timezone_map`, `timezone`, `last_date`).
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
8. **If the user answers Other in step 7:** propose a check name + `hfc/checks/<name>.R`, confirm via AskUserQuestion, implement and register under M11/`custom`, **and** write its ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (`custom.<name>.label` / `.description`) so `hfc/report/index.html` can show it under the M11 section (schema in `references/check_modules.md`).

### A3. Outline + product structure

1. Write / update `hfc/structure.html` (product tree map). Open it in the browser.
2. Briefly propose tracking/HTML sections, feedback approach, README plan in chat.
3. **AskUserQuestion:** Continue with this structure (recommended) (Other automatic).

### A4. Build

1. **AskUserQuestion — OneDrive:** show the configured site/folder from `hfc/config/onedrive.json` if present, else note placeholders in `assets/lib/onedrive.json` — Use project / skill config when live (recommended) / I will edit or paste the site URL / Local twin only. Never treat `YOUR_TENANT`/`YOUR_SITE` as live. If edit: write the real `site_url`/`folder_path` to `hfc/config/onedrive.json` (from `onedrive.example.json`) or paste via Other. Note: the very first sign-in against a given site is an interactive browser/device-code flow the user must complete themselves (`scripts/onedrive_auth_setup.R`, run outside Claude Code) — it cannot be completed from inside a non-interactive `Rscript` call.
2. **AskUserQuestion — Feedback columns:** Keep these feedback columns (recommended) / Modify columns. Schema: no `check_module`; `status` (default Open); `resolved` (default No).
3. **AskUserQuestion — Map focus** (if GPS on): Country / City / World. Store in `hfc/config/report.yaml`.
4. **AskUserQuestion — Report:** HTML (recommended).
5. Write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from confirmed options.
6. Run builder:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R "<project_root>" --open
   # or local twin only:
   Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R "<project_root>" --no-onedrive --open
   # equivalently:
   Rscript "${CLAUDE_SKILL_DIR}/scripts/run_setup_build.R" "<project_root>" --open
   ```
7. Draft project `README.md`; **AskUserQuestion:** Write this README (recommended).
8. Auto-open `hfc/report/index.html`. Tell user: the **main** feedback file and the report itself now live in the shared OneDrive folder (access already granted via the one-time manual folder share) — surface the report's OneDrive link from the run summary. Later: **Process HFC feedback** (+ project path if monorepo).

---

## Pipeline B — Post-feedback

1. Confirm feedback exists: pull **main** file from OneDrive or local twin `hfc/output/feedback_sheet.xlsx`; required columns include **`resolved`** and **`status`** (map legacy `ra_status` if present).
2. Summarize by `status`; propose fix actions for accepted rows.
3. **AskUserQuestion:** Proceed with accepted rows (recommended).
4. Propose `hfc/fixes/` layout; **AskUserQuestion:** Confirm fix plan (recommended).
5. Run:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R "<project_root>"
   # or: Rscript "${CLAUDE_SKILL_DIR}/scripts/apply_feedback.R" "<project_root>"
   ```
6. Write `data/raw/<stem>_resolved.<ext>` (same directory as source). Raw unchanged.
7. Update feedback `resolved`; push to **audit_file** when OneDrive configured.
8. Tell user to review the resolved file (no need to type a long reply).

---

## What not to do

- Do not overwrite the original microdata file.
- Do not start Pipeline A when the user clearly asked for post-feedback (and vice versa).
- Do not invent access dates, exhibit IDs, or column names that are not in the data.
- Do not attempt an interactive OneDrive sign-in from a Claude-Code-driven run; use the local Excel twin if the token isn't already cached (the user must run `scripts/onedrive_auth_setup.R` themselves first).
- Do not require monorepo gold data, `eval/`, `verify_all`, or SimUser for product runs.
- Do not use typed mega-replies (`M1=Y M2=…`) as the primary confirmation UX when AskUserQuestion is available (F19).
- Do not skip the unique-ID AskUserQuestion gate (F20).
- Do not scatter product dirs at project root — use `hfc/` (F21).
- Do not flag expected skip-logic blanks as missing (F22).
- Do not skip or silently auto-answer the Additional-checks AskUserQuestion gate after module confirmation (F23).
- Do not skip the country/timezone confirm gate, or trust a resolved country→timezone lookup without showing it back for confirmation (F24).
- Do not skip the last-collection-date AskUserQuestion gate (F25).
