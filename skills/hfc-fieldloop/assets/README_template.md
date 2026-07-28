# README template — FieldLoop survey project

Fill every section for the **survey project** (parent of `.claude/` (survey root with `.claude/skills/hfc-fieldloop/`)), not for the skill itself.
Use `assets/README_example.md` for the expected level of specificity. Confirm once with the user before finalizing.

## Contents

1. [Overview](#overview)
2. [Data](#data)
3. [Software requirements](#software-requirements)
4. [Instructions](#instructions)
5. [Outputs](#outputs)
6. [Folder structure](#folder-structure)
7. [AI / confidentiality](#ai--confidentiality)

---

## Overview

- Survey / project name:
- What FieldLoop produces for this survey (HTML report, tracking workbook, feedback file twin, resolved data):
- What it does **not** produce (e.g. cleaned analysis dataset, manuscript tables):
- Setup vs post-feedback: one sentence each

## Data

- Microdata path under `data/raw/` (filename, format, approximate n rows / cols if known):
- Optional instrument / form path:
- Access / confidentiality note (internal only, DUA, etc.):
- Rule: never mutate originals; accepted fixes write `*_resolved` sibling beside the source file

## Software requirements

- R version tested:
- Install: `Rscript .claude/skills/hfc-fieldloop/install.R`
- Core packages: haven, readr, readxl, dplyr, tidyr, tibble, stringr, lubridate, openxlsx, yaml, jsonlite
- Optional: Microsoft365R, geosphere

## Instructions

### First-time setup

1. Place `.claude/skills/hfc-fieldloop/` in the survey project; put microdata (+ optional form) in `data/raw/`.
2. Run `Rscript .claude/skills/hfc-fieldloop/install.R`.
3. In VS Code + Claude Code: **Run HFC FieldLoop** or `/hfc-fieldloop` (add `for <project>` in a monorepo). Choose AskUserQuestion option cards; use **Other** for custom answers — do not type `M1=Y M2=…`.
4. The **main** feedback file lives in a shared OneDrive folder (if using OneDrive) — access to that folder is set up once, by hand, via OneDrive's own sharing UI, and (for a fully unattended pipeline run) someone must have already completed the one-time interactive sign-in via `scripts/onedrive_auth_setup.R`.

CLI equivalent after modules confirmed:

```bash
Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --open
# Local-only (no OneDrive):
Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --no-onedrive --open
```

### After field feedback

1. Say **Process HFC feedback** (or run apply script).
2. Review proposed fixes; confirm.
3. Expect `data/raw/<stem>_resolved.<ext>`; raw file unchanged.

```bash
Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R .
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R . export   # optional local twin
Rscript .claude/skills/hfc-fieldloop/scripts/sync_feedback.R . import
```

## Outputs

| Artifact | Path | Purpose |
|---|---|---|
| Product map | `hfc/structure.html` | Review tree in browser before Continue |
| HTML report | `hfc/report/index.html` | Navigable findings (searchable tables, GPS map) |
| Tracking workbook | `hfc/output/tracking.xlsx` | Tabular check summaries |
| Feedback twin | `hfc/output/feedback_sheet.xlsx` / `hfc/registry/feedback.csv` | Local collaboration copy |
| Findings | `hfc/registry/findings.csv` | Machine-readable findings |
| Main file | OneDrive folder from `hfc/config/onedrive.json` → `main_file` | Field / RA edits |
| Report link | `hfc/project.yaml` → `report_onedrive_url` | Shareable link to the built report |
| Audit file | `audit_file` | Code mid-process + `resolved` |
| Resolved data | `data/raw/*_resolved.*` | After Pipeline B |

## Folder structure

List the project tree after setup (`data/raw/`, `hfc-fieldloop/`, `hfc/` with checks, code, config, registry, output, report, fixes).

## AI / confidentiality

Point to `.claude/skills/hfc-fieldloop/references/ai_use.md`. Do not paste PII or restricted microdata into commercial AI tools.
