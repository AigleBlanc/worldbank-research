# Failure flags

| ID | Rule |
|---|---|
| F1 | Hardcoded user paths outside `hfc/code/main.R` |
| F2 | Mutating original microdata (must write `*_resolved` sibling) |
| F3 | Findings without stable `finding_id` |
| F4 | Feedback applied without `status=accepted` (or explicit user override); legacy `ra_status` accepted only when mapped |
| F5 | Missing `resolved` column on feedback |
| F6 | Attempting an interactive OneDrive sign-in from a Claude-Code-driven run instead of falling back to the local twin (the user must complete the one-time sign-in themselves via `scripts/onedrive_auth_setup.R`) |
| F7 | Proceeding without data confirm when files missing |
| F8 | Asking unbounded per-column free-text instead of module options |
| F9 | Building without writing `hfc/config/modules.yaml` from confirmed options (silent default overwrite of user picks) |
| F10 | Requiring monorepo gold / Malawi paths for a new survey drop-in |
| F11 | Treating an `onedrive.json` with `"enabled": false` (or missing) as live config |
| F12 | Enabling irrelevant M11 checks (e.g. food/ravens) when form/heuristics found no candidates |
| F13 | Age/outlier copy that assumes child surveys when roles are generic adults/HH |
| F14 | Calling deleted eval harness paths (`eval/`, `verify_all`, `run_demo`, SimUser as required) |
| F15 | Project README missing or invented access dates / exhibit IDs not in the package |
| F16 | Treating media **filename** columns (e.g. `audio_audit` `.m4a`) as M13 flags instead of M12 |
| F17 | Claiming media OK / skipping empty-cell checks when on-disk folder missing (on-disk may skip; cells must still be checked) |
| F18 | Enabling M12 without detecting or confirming audio/image cols when they exist in data |
| F19 | Asking primary confirms via free-text / mega-string (`M1=Y M2=…`) instead of AskUserQuestion option cards when AskUserQuestion is available; adding a redundant explicit Other when Claude Code already provides Other |
| F20 | Skipping the unique identifier(s) AskUserQuestion gate (must shortlist ≤3 single-column or ≤4 composite candidates after data confirm; Other is automatic) |
| F21 | Writing product artifacts outside `hfc/` (checks, config, report, registry, output, code, fixes, project.yaml) |
| F22 | Flagging child/nested question blanks as missing when parent skip-logic makes them expected |
| F23 | Skipping or silently auto-answering the "Additional checks" AskUserQuestion gate after module confirmation (it must fire every run, even under Accept-all pace) |
| F24 | Skipping the country/timezone confirm gate, or treating a resolved country→timezone lookup as live without showing it back for confirmation |
| F25 | Skipping the last-date-of-data-collection AskUserQuestion gate (drives report-wide bold-highlighting and the Last Day tab) |
