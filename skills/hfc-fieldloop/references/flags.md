# Failure flags

| ID | Rule |
|---|---|
| F1 | Hardcoded user paths outside `hfc/code/main.R` |
| F2 | Mutating original microdata (fixes must write to `data/intermediate/`, never touch `data/raw/`) |
| F3 | Findings without stable `finding_id` |
| F4 | Applying a fix to a row that is not `Status=Open` with a non-empty RIL Comment (the sole eligibility gate); legacy `status`/`resolved` pairs accepted only when migrated |
| F5 | Missing `Status` column on the issue tracking file |
| F7 | Proceeding without data confirm when files missing |
| F8 | Asking unbounded per-column free-text instead of module options |
| F9 | Building without writing `hfc/config/modules.yaml` from confirmed options (silent default overwrite of user picks) |
| F10 | Requiring monorepo gold / Malawi paths for a new survey drop-in |
| F11 | Treating an `sync_folder.json` with `"enabled": false` (or missing) as live config |
| F12 | Enabling an M11 custom check without a user-described need and a registered `hfc/code/checks/<name>.R` |
| F13 | Age/outlier copy that assumes child surveys when roles are generic adults/HH |
| F14 | Calling deleted eval harness paths (`eval/`, `verify_all`, `run_demo`, SimUser as required) |
| F15 | Project README missing or invented access dates / exhibit IDs not in the package |
| F16 | Treating media **filename** columns (e.g. `audio_audit` `.m4a`) as M13 flags instead of M12 |
| F17 | Claiming media OK / skipping empty-cell checks when on-disk folder missing (on-disk may skip; cells must still be checked) |
| F18 | Enabling M12 without detecting or confirming audio/image cols when they exist in data |
| F19 | Asking primary confirms via free-text / mega-string (`M1=Y M2=…`) instead of AskUserQuestion option cards when AskUserQuestion is available; adding a redundant explicit Other when Claude Code already provides Other |
| F20 | Skipping the Entity ID AskUserQuestion gate (must shortlist ≤3 single-column or ≤4 composite candidates after data confirm; Other is automatic) |
| F21 | Writing product artifacts outside `hfc/` (config, instruments, registry, outputs, code — with code/checks, code/resolutions — project.yaml) |
| F22 | Flagging child/nested question blanks as missing when parent skip-logic makes them expected |
| F23 | Skipping or silently auto-answering the "Additional checks" AskUserQuestion gate after module confirmation (it must fire every run, even under Accept-all pace) |
| F24 | Skipping the country/timezone confirm gate, or treating a resolved country→timezone lookup as live without showing it back for confirmation |
| F25 | Skipping the last-date-of-data-collection AskUserQuestion gate (drives report-wide bold-highlighting and the Last Day tab) |
| F26 | Code/agent writing `Status`/`Corrections` directly to the live `issue_tracking.xlsx` instead of today's `resolutions/<date>_issues_resolution.xlsx` clone — the live file is only ever updated by `commit_merged_issue_tracking.R`, after explicit AskUserQuestion confirmation |
| F27 | Skipping the duplicate-check-key sub-gate when Entity ID is NOT already 100% unique in the raw data (must offer detected round/wave-like candidates or "Entity ID alone"; auto-skip only applies when uniqueness already holds) |
| F28 | Overwriting `issue_tracking.xlsx` (via `merge_issues.R`/`merge_resolutions.R`'s output) without an explicit AskUserQuestion confirmation first — always review the `merged_*.xlsx` file with the user before running `commit_merged_issue_tracking.R` |
| F29 | Skipping or silently bypassing the OneDrive pre-flight check (A0c) — if `local_path` isn't configured/reachable, stop and direct the user to `install.R` + confirming OneDrive desktop sync is running + `assets/lib/sync_folder.json`; never proceed with a build that has nowhere to write `issue_tracking.xlsx` |
| F30 | Skipping the mandatory post-commit report rebuild in Pipeline B (step 6b) — leaving `hfc/outputs/report.html` showing findings that were already fixed/resolved |
| F31 | Skipping the mandatory important-variables shortlist gate (A2.10) before build, or letting M6/M9/M10 fall back to their old independent auto-pools when a unified list was never confirmed |
