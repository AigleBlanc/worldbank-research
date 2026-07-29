# Gold-standard project README example (FieldLoop)

Annotated example of a **survey project** README the FieldLoop agent should aim for after setup. Annotations in [brackets] explain why each element works. Pair with `README_template.md`.

---

## Overview

> This package runs High-Frequency Checks (HFCs) for an example school survey wave under `data/raw/` (illustrative name: WFP Malawi Child). Setup builds an HTML report, tracking workbook, and a feedback file twin synced to a shared OneDrive folder. Post-feedback writes `*_resolved` beside the raw file for accepted RA fixes. It does **not** produce analysis tables for a paper or a cleaned longitudinal panel.

[Why this works: names the survey, states what is produced and what is not.]

## Data

> **Survey microdata**
> - File: `data/raw/malawi_child_sample.dta` (or `.csv` equivalent)
> - Source: SurveyCTO export for this wave
> - Note: Original file is immutable. Accepted feedback writes `data/raw/malawi_child_sample_resolved.dta` (or `.csv`) in the same folder.
> - Form (optional): `instrument/form.xlsx` — improves M11 survey-specific proposals (and M3 Form Version / M4 Duration section detection); setup proceeds without it.

[Why this works: exact path, immutability rule, resolved sibling named.]

## Software requirements

> - R ≥ 4.3 (tested with R 4.4 on macOS)
> - `Rscript .claude/skills/hfc-fieldloop/install.R` installs: haven, readr, readxl, dplyr, tidyr, tibble, stringr, lubridate, openxlsx, yaml, jsonlite; plus Microsoft365R, geosphere when using OneDrive/GPS

[Why this works: install entrypoint and package list, not a vague “R packages”.]

## Instructions

> 1. Confirm `.claude/skills/hfc-fieldloop/` is installed and `data/raw/` is ready.
> 2. Run `Rscript .claude/skills/hfc-fieldloop/install.R`.
> 3. In Claude Code (VS Code): **Run HFC FieldLoop** or `/hfc-fieldloop` (add `for <project>` if the workspace is a monorepo). Choose AskUserQuestion option cards for data, **required fields (unique ID(s), country/timezone, last date)**, modules, additional checks, `hfc/structure.html` Continue, OneDrive, and feedback columns — use **Other** when needed. Do not type `M1=Y M2=…`.
> 4. Open `hfc/report/index.html` (builder may auto-open). Field edits the **main** feedback file in the shared OneDrive folder (access set up once, by hand).
> 5. Later: **Process HFC feedback** after RAs mark `status=accepted` (choose options to proceed).
>
> CLI after `hfc/config/modules.yaml` exists:
> ```bash
> Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --open
> Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R .
> ```

[Why this works: ordered recipe; two prompts named; CLI as fallback.]

## Outputs

> - `hfc/structure.html` — product tree (review before Continue)
> - `hfc/report/index.html` — findings by module (searchable tables, GPS map)
> - `hfc/output/tracking.xlsx` — summary tabs
> - `hfc/output/feedback_sheet.xlsx` + `hfc/registry/feedback.csv` — local twin (`status`, `resolved`)
> - `hfc/config/onedrive.json` — `enabled`/`folder_path`, `main_file` (field) and `audit_file` (code)
> - `hfc/registry/findings.csv` — stable `finding_id`s

## Folder structure

> - `data/raw/` — immutable microdata
> - `hfc/checks/` — module stubs / templates / custom (e.g. `fed.R`)
> - `hfc/code/main.R` — one-path entry
> - `hfc/registry/`, `hfc/output/`, `hfc/report/`, `hfc/fixes/`, `hfc/config/`
> - `.claude/skills/hfc-fieldloop/` — drop-in skill (do not edit unless upgrading the skill)

## AI / confidentiality

> Household / school microdata must not be pasted into commercial AI tools. See `.claude/skills/hfc-fieldloop/references/ai_use.md`.
