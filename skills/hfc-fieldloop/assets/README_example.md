# Gold-standard project README example (FieldLoop)

Annotated example of a **survey project** README the FieldLoop agent should aim for after setup. Annotations in [brackets] explain why each element works. Pair with `README_template.md`.

---

## Overview

> This package runs High-Frequency Checks (HFCs) for an example school survey wave under `data/raw/` (illustrative name: WFP Malawi Child). Setup builds an HTML report and a shared `issue_tracking.xlsx` synced to a OneDrive folder. Post-feedback writes agent-authored fixes to `data/intermediate/` for Open+RIL-commented rows. It does **not** produce analysis tables for a paper or a cleaned longitudinal panel.

[Why this works: names the survey, states what is produced and what is not.]

## Data

> **Survey microdata**
> - File: `data/raw/malawi_child_sample.dta` (or `.csv` equivalent)
> - Source: SurveyCTO export for this wave
> - Note: Original file is immutable. Applying a fix writes `data/intermediate/malawi_child_sample.dta` (or `.csv`) — one evolving fixed copy, updated as fixes accumulate.
> - Form (optional): `instrument/form.xlsx` — improves M11 survey-specific proposals (and M3 Form Version / M4 Duration section detection); setup proceeds without it.

[Why this works: exact path, immutability rule, intermediate output named.]

## Software requirements

> - R ≥ 4.3 (tested with R 4.4 on macOS)
> - `Rscript .claude/skills/hfc-fieldloop/install.R` installs: haven, readr, readxl, dplyr, tidyr, tibble, stringr, lubridate, openxlsx, yaml, jsonlite; plus Microsoft365R, geosphere when using OneDrive/GPS

[Why this works: install entrypoint and package list, not a vague “R packages”.]

## Instructions

> 1. Confirm `.claude/skills/hfc-fieldloop/` is installed and `data/raw/` is ready.
> 2. Run `Rscript .claude/skills/hfc-fieldloop/install.R`.
> 3. In Claude Code (VS Code): **Run HFC FieldLoop** or `/hfc-fieldloop` (add `for <project>` if the workspace is a monorepo). Choose AskUserQuestion option cards for config reuse (if a prior run exists), data, **required fields (Entity ID, Entity Label, duplicate-check key, country/timezone, last date)**, modules, additional checks, `hfc/structure.html` Continue, OneDrive, and feedback columns — use **Other** when needed. Do not type `M1=Y M2=…`.
> 4. Open `hfc/report/index.html` (builder may auto-open). Field/RA edit `issue_tracking.xlsx` directly in the shared OneDrive folder (access set up once, by hand).
> 5. Later: **Process HFC feedback** once RIL Comments exist on Open rows in `issue_tracking.xlsx` — the agent reads each row and writes the fix itself, against a working clone, then merges back after confirmation (choose options to proceed).
>
> CLI after `hfc/config/modules.yaml` exists:
> ```bash
> Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R . --open
> Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R clone .
> Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R list-open .
> ```

[Why this works: ordered recipe; two prompts named; CLI as fallback.]

## Outputs

> - `hfc/structure.html` — product tree (review before Continue)
> - `hfc/report/index.html` — findings by module (searchable tables, GPS map)
> - OneDrive `issue_tracking.xlsx` (or local `hfc/output/issue_tracking.xlsx`) + `hfc/registry/issue_tracking.csv` — the one shared file; agent, RA, and field team all edit it
> - `.claude/skills/hfc-fieldloop/assets/lib/onedrive.json` — `enabled`/`folder_path`/`main_file`; skill-level, not per-project
> - `hfc/registry/findings.csv` — stable, content-derived Issue IDs

## Folder structure

> - `data/raw/` — immutable microdata
> - `data/intermediate/` — agent-fixed data (one evolving file per source, raw untouched)
> - `hfc/checks/` — module stubs / templates / custom (e.g. `example_check.R`)
> - `hfc/fixes/` — agent-authored fix code, one `<Issue ID>.R` per resolved finding
> - `hfc/code/main.R` — one-path entry
> - `hfc/registry/`, `hfc/output/`, `hfc/report/`, `hfc/fixes/`, `hfc/config/`
> - `.claude/skills/hfc-fieldloop/` — drop-in skill (do not edit unless upgrading the skill)

## AI / confidentiality

> Household / school microdata must not be pasted into commercial AI tools. See `.claude/skills/hfc-fieldloop/references/ai_use.md`.
