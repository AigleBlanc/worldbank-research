# Gold-standard project README example (FieldLoop)

Annotated example of a **survey project** README the FieldLoop agent should aim for after setup, written to `<code_output_dir>/README.md`. Annotations in [brackets] explain why each element works. Pair with `README_template.md`.

---

## Overview

> This package runs High-Frequency Checks (HFCs) for an example school survey wave (illustrative name: WFP Malawi Child), reading microdata from the configured Input Data Directory. Setup builds an HTML report and a shared `issue_tracking.xlsx` synced to a OneDrive folder. Post-feedback writes agent-authored fixes to a sibling `intermediate/` folder next to the Input Data Directory for Open+RIL-commented rows. It does **not** produce analysis tables for a paper or a cleaned longitudinal panel.

[Why this works: names the survey, states what is produced and what is not.]

## Data

> **Survey microdata**
> - File: `malawi_child_sample.dta` (or `.csv` equivalent), in the configured Input Data Directory
> - Source: SurveyCTO export for this wave
> - Note: Original file is immutable. Applying a fix writes `<sibling of Input Data Directory>/intermediate/malawi_child_sample.dta` (or `.csv`) — one evolving fixed copy, updated as fixes accumulate.
> - Form (optional): also in the Input Data Directory — improves M11 survey-specific proposals (and M3 Form Version / M4 Duration section detection); setup proceeds without it.

[Why this works: exact path, immutability rule, intermediate output named.]

## Software requirements

> - R ≥ 4.3 (tested with R 4.4 on macOS)
> - `Rscript .claude/skills/hfc-fieldloop/install.R` installs: haven, readr, readxl, dplyr, tidyr, tibble, stringr, lubridate, openxlsx, yaml, jsonlite; geosphere is optional (GPS distance)
> - OneDrive is required — a plain local folder synced by the OneDrive desktop app, no extra R package needed

[Why this works: install entrypoint and package list, not a vague “R packages”.]

## Instructions

> 1. Confirm `.claude/skills/hfc-fieldloop/config.json` is fully configured (Input Data Directory, OneDrive Folder Directory, Code Output Directory; Media Folder Directory optional).
> 2. Run `Rscript .claude/skills/hfc-fieldloop/install.R`.
> 3. In Claude Code (VS Code): **Run HFC FieldLoop** or `/hfc-fieldloop`. The agent first confirms `config.json` is reachable (required — stops with setup instructions if not), then walks through config reuse (if a prior run exists), a Setup window (discovered files, Entity Label, country — stated as best guesses to confirm or correct), module-config windows (duplicates/version, timing, key variables, GPS/media, consent, extra checks — same guess-then-correct pattern), `hfc/structure.html` Continue, and feedback columns — use **Other** to correct anything wrong. Do not type `M1=Y M2=…`.
> 4. Open `hfc/outputs/report.html` (builder may auto-open). Field/RA edit `issue_tracking.xlsx` directly in the shared OneDrive-synced folder (access set up once, by hand).
> 5. Later: **Process HFC feedback** once RIL Comments exist on Open rows in `issue_tracking.xlsx` — the agent reads each row and writes the fix itself, against a working clone, then merges back after confirmation (choose options to proceed).
>
> CLI after `hfc/config/modules.yaml` exists:
> ```bash
> Rscript .claude/skills/hfc-fieldloop/scripts/run_setup_build.R --open
> Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R clone
> Rscript .claude/skills/hfc-fieldloop/scripts/apply_feedback.R list-open
> ```

[Why this works: ordered recipe; two prompts named; CLI as fallback.]

## Outputs

> - `hfc/structure.html` — product tree (review before Continue)
> - `hfc/outputs/report.html` — findings by module (searchable tables, GPS map)
> - OneDrive-synced `issue_tracking.xlsx` (required, no local copy) — the one shared file; agent, RA, and field team all edit it
> - `.claude/skills/hfc-fieldloop/config.json` — Input Data Directory / Media Folder Directory / OneDrive Folder Directory / Code Output Directory / Main Tracking Filename; skill-level, not per-project
> - `hfc/registry/findings.csv` — stable, content-derived Issue IDs

## Folder structure

> - Input Data Directory (configured, external) — immutable microdata
> - `<sibling of Input Data Directory>/intermediate/` — agent-fixed data (one evolving file per source, raw untouched)
> - `<Code Output Directory>/hfc/code/checks/` — real, runnable per-module scripts + custom (e.g. `example_check.R`)
> - `<Code Output Directory>/hfc/code/resolutions/` — agent-authored fix code, one `<Issue ID>.R` per resolved finding
> - `<Code Output Directory>/hfc/code/main.R` — skill/code-output-path entry
> - `<Code Output Directory>/hfc/registry/`, `hfc/outputs/`, `hfc/instruments/`, `hfc/config/`
> - `.claude/skills/hfc-fieldloop/` — drop-in skill (do not edit unless upgrading the skill)

## AI / confidentiality

> Household / school microdata must not be pasted into commercial AI tools. See `.claude/skills/hfc-fieldloop/references/ai_use.md`.
