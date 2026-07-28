# HFC FieldLoop — drop-in skill (VS Code + Claude Code)

Copy this folder into any survey project as **`.claude/skills/hfc-fieldloop/`**.

```
any_survey/                            ← open this folder in VS Code
├── .claude/skills/hfc-fieldloop/      ← this folder (skill)
├── data/raw/                          ← .dta / .csv (+ optional form.xlsx)
└── hfc/                               ← built product (after setup)
```

**From this monorepo:** copy `skills/hfc-fieldloop/` → `any_survey/.claude/skills/hfc-fieldloop/` (create `.claude/skills/` if needed). Claude Code requires the leading-dot `.claude` name in the **target** project.

Browse the skill tree: open [`structure.html`](structure.html). After setup, review **`hfc/structure.html`** in a browser before confirming Continue.

## Overview

FieldLoop builds a versioned HFC package for **this** survey: checks (M1–M13, including audio/picture media files), tracking workbook, HTML report, and a feedback loop with field/RAs (two Excel files — main + audit — in a shared OneDrive folder, or local Excel twin only). A second pass applies accepted fixes to a `*_resolved` sibling beside the raw file.

It does **not** replace your analysis pipeline or mutate originals in `data/raw/`.

| Say | Pipeline |
|---|---|
| **Run HFC FieldLoop** / `/hfc-fieldloop` (+ `for <project>` if needed) | Discover → AskUserQuestion (data, required fields, modules, extras, `hfc/` structure, OneDrive, columns) → build under `hfc/` |
| **Process HFC feedback** (+ `for <project>` if needed) | Pull feedback → option cards → apply → `*_resolved` + update `resolved` |

Confirms use Claude Code **AskUserQuestion** cards. Free-text **Other** is built in. You should not type long replies like `M1=Y M2=Y M11=none`.

## Data

- Put microdata under `data/raw/` (`.dta`, `.csv`, or respondent `.xlsx`).
- Optional SurveyCTO-like form improves M11 survey-specific proposals, M3 Form Version, and M4 Duration section detection; setup proceeds without it.
- Optional media binaries under `data/raw/media/` (or `media/` beside the export) for **M12** on-disk checks; filename columns are still checked if the folder is missing.
- Never overwrite the original file; fixes write `*_resolved` next to it.

## Software requirements

1. R (≥ 4.3 recommended)
2. From the **survey project root** (parent of `.claude/`, e.g. `any_survey/`):

```bash
Rscript .claude/skills/hfc-fieldloop/install.R
```

Installs: haven, readr, readxl, dplyr, tidyr, tibble, stringr, lubridate, openxlsx, yaml, jsonlite; plus Microsoft365R, geosphere (OneDrive/GPS). Optional for M12 audio duration: `av` (or system `ffprobe`) — install does not fail without it.

**OneDrive auth (optional):** delegated, one-time interactive sign-in — no secrets stored in this package. Run `Rscript .claude/skills/hfc-fieldloop/scripts/onedrive_auth_setup.R` **once, yourself, in a normal interactive R/RStudio session** (not through Claude Code) to complete the browser/device-code login; `Microsoft365R`/`AzureAuth` then cache the token locally and refresh it silently on every later run.

**Site/folder config:** copy `assets/lib/onedrive.example.json` → project `hfc/config/onedrive.json` and replace the placeholder with your real SharePoint/Team site URL and folder. Skill `assets/lib/onedrive.json` stays placeholders only. Without a real `site_url`, use `--no-onedrive` (local twin only).

## Instructions

**Survey project root** = the folder that contains both `.claude/skills/hfc-fieldloop/` and `data/raw/` (e.g. `any_survey/`). It is *not* a parent monorepo root unless that is also where your survey data lives.

### Tell Claude Code which project

If you opened the survey folder itself in VS Code, say:

```text
Run HFC FieldLoop
```

or type `/hfc-fieldloop`.

If you opened a **parent** workspace (monorepo, multi-survey repo), **name the project folder** in the prompt so the agent does not use the workspace root:

```text
Run HFC FieldLoop for test/malawi1
```

Also fine: `for malawi1`, `project: test/malawi1`.

Same rule for feedback: `Process HFC feedback for test/malawi1`.

The agent should set `project_root` to that folder (the parent of that project’s `.claude/`), confirm `data/raw/` there, and run scripts with that path — not `.` at the monorepo root.

### Setup steps

1. Copy this skill to `.claude/skills/hfc-fieldloop/` in the survey project; add data to `data/raw/` (and optional `data/raw/media/`).
2. From the **survey project root** (not the monorepo root unless they are the same):

```bash
Rscript .claude/skills/hfc-fieldloop/install.R
```

3. In VS Code + Claude Code: prompt as above (include the project path when the workspace is larger than one survey), or `/hfc-fieldloop`.
4. When the agent asks, **choose** the option cards (data → **required fields: unique ID(s), country/timezone, last date** → modules → additional checks → open `hfc/structure.html` → Continue → OneDrive → feedback columns → map focus). Use **Other** only when no option fits. Do not type `M1=Y M2=…`.
5. The **main** feedback file and the report link both live in the shared OneDrive folder (if configured) — access is set up once, by hand, via OneDrive's own sharing UI.
6. Later: **Process HFC feedback** (again with the project path if needed); again use option cards rather than typing long replies.

### CLI (from survey project root)

After `hfc/config/modules.yaml` / `role_map.yaml` exist (or accept profile defaults):

```bash
# cwd = survey project root
Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --open
Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --no-onedrive --open
```

Other helpers:

```bash
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R . export
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R . import
Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R .
```

One-path rebuild after setup: `Rscript hfc/code/main.R` (from survey project root; written from `assets/main.R`).

## Outputs map

| Artifact | Location |
|---|---|
| Product map | `hfc/structure.html` |
| HTML report | `hfc/report/index.html` |
| Tracking | `hfc/output/tracking.xlsx` |
| Feedback twin | `hfc/output/feedback_sheet.xlsx`, `hfc/registry/feedback.csv` |
| Findings | `hfc/registry/findings.csv` |
| OneDrive main / audit | `hfc/config/onedrive.json` (`site_url`, `folder_path`, `main_file`, `audit_file`) |
| Report link | `hfc/project.yaml` → `report_onedrive_url` |
| Resolved data | `data/raw/*_resolved.*` |

## Folder structure (this skill)

```
.claude/skills/hfc-fieldloop/
├── SKILL.md
├── README.md
├── install.R
├── structure.html
├── references/          # prompts, interaction, modules, schema, checklist, flags, ai_use
├── assets/
│   ├── main.R
│   ├── README_template.md
│   ├── README_example.md
│   ├── feedback_template.csv
│   ├── check_templates/   # M1–M13 + custom_fed_example.R
│   └── lib/               # onedrive*.json (no secrets — delegated auth)
└── scripts/
    ├── run_setup_build.R
    ├── apply_feedback.R
    ├── sync_feedback.R
    ├── onedrive_auth_setup.R  # one-time interactive sign-in (run by the user)
    └── lib/               # media, form_logic, product_structure, …
```

## AI / confidentiality

Do not upload household microdata or PII to commercial AI tools. See [`references/ai_use.md`](references/ai_use.md).
