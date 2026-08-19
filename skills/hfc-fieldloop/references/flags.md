# Failure flags

| ID | Rule |
|---|---|
| F1 | Hardcoded user paths outside `hfc/code/main.R` |
| F2 | Mutating original microdata (fixes must write to `<sibling of Input Data Directory>/intermediate/`, never touch the configured Input Data Directory) |
| F3 | Findings without stable `finding_id` |
| F4 | Applying a fix to a row that is not `Status=Open` with a non-empty Comment (the sole eligibility gate); legacy `status`/`resolved` pairs accepted only when migrated |
| F5 | Missing `Status` column on the issue tracking file |
| F7 | Proceeding without data confirm when files missing |
| F8 | Asking unbounded per-column free-text instead of module options |
| F9 | Building without writing `hfc/config/modules.yaml` from confirmed options (silent default overwrite of user picks) |
| F10 | Requiring monorepo gold / Malawi paths for a new survey drop-in |
| F11 | Treating a `config.json` with a missing or still-placeholder (`<...>`) required field as live/ready config |
| F12 | Enabling an M9 custom check without a user-described need and a registered `hfc/code/checks/<name>.R` |
| F13 | Age/outlier copy that assumes child surveys when roles are generic adults/HH |
| F14 | Calling deleted eval harness paths (`eval/`, `verify_all`, `run_demo`, SimUser as required) |
| F15 | Project README missing or invented access dates / exhibit IDs not in the package |
| F16 | Treating media **filename** columns (e.g. `audio_audit` `.m4a`) as M14 flags instead of M13 |
| F17 | Running per-row media file-hygiene checks (missing/tiny/duration/duplicate/extension) — M13 only ever flags a media-indicating column that's completely empty across every surveyed row; never re-add on-disk file checks |
| F18 | Enabling M13 without correctly detecting the media-indicating columns (audio/image filename columns, plus any qualitative open-text columns) — decided silently by default; a wrong detection must still be visibly correctable via "Walk me through all modules" (Media, Map & Grouping window's Media columns tab) |
| F19 | Asking primary confirms via free-text / mega-string (`M1=Y M2=…`) or a long menu of choices instead of a stated best guess + one free-text correction; adding a redundant explicit "Corrections" option when Claude Code already provides Other |
| F20 | Silently guessing the Entity ID without naming the underlying column in the Entity & Country window's Entity tab's message (A1) — a wrong pick must be visibly correctable through that tab's free-text box, since there's no separate Entity ID gate anymore |
| F21 | Writing product artifacts outside `<Code Output Directory>/hfc/` (config, instruments, outputs, code — with code/checks, code/resolutions — project.yaml) |
| F22 | Flagging child/nested question blanks as missing when parent skip-logic makes them expected |
| F23 | Ignoring a specific-check request in A1's Instructions answer — every run, every time, matched to a standard module or authored as an M9 custom check; there's no separate Field Request tab to catch it later |
| F24 | Resolving country/timezone incorrectly and never surfacing it — decided silently by default (A1), but must still be nameable/correctable via "Walk me through all modules" (Entity & Country window's Country tab) |
| F25 | Getting the last-date-of-data-collection guess wrong with no way to catch it — decided silently by default (drives the Last Day tab), correctable via "Walk me through all modules" (Dates, Variables & GPS window) |
| F26 | Code/agent writing `Status`/`Corrections` directly to the live `issue_tracking.xlsx` instead of today's `resolutions/<date>_issues_resolution.xlsx` clone — the live file is only ever updated by `commit_merged_issue_tracking.R`, after explicit AskUserQuestion confirmation |
| F27 | Getting the duplicate-check key wrong without it being visibly correctable — it's auto-resolved in A1 (Entity ID alone if already unique, else + detected round/wave-like candidates) and restated in the Keys & Hours window's Duplicate key tab precisely so a wrong resolution can be corrected there |
| F28 | Overwriting `issue_tracking.xlsx` (via `merge_issues.R`/`merge_resolutions.R`'s output) without an explicit AskUserQuestion confirmation first — always review the `merged_*.xlsx` file with the user before running `commit_merged_issue_tracking.R` |
| F29 | Skipping or silently bypassing the config pre-flight check (A0) — if Input Data Directory, HFC Output Directory, or Code Output Directory isn't configured/reachable in `config.json`, stop and direct the user to `install.R` + confirming OneDrive desktop sync is running + editing `config.json`; never proceed with a build that has nowhere to write `issue_tracking.xlsx` |
| F30 | Skipping the mandatory post-commit report rebuild in Pipeline B (step 7) — leaving `hfc/outputs/<MMDD>_HFCs.html` showing findings that were already fixed/resolved |
| F31 | Skipping the mandatory important-variables shortlist step (A2) before build, or letting M6/M8/M11 fall back to their old independent auto-pools when a unified list was never confirmed |
| F32 | Presenting two near-duplicate variables (e.g. `treat` vs. `treat_ext`) as if they were independently meaningful in any shortlist — always silently keep the single most reasonable one |
| F33 | Inferring the data-collection country from the input folder's name/basename instead of geography actually present in the data (district/region/village names, GPS bounding box) |
| F34 | Letting incomplete/non-surveyed rows (per a confirmed "status" completion signal) leak into any M2-M14 finding — they must be filtered out before those modules run; M1 alone sees the unfiltered data |
| F35 | Confusing assent and consent, or bundling the Consent tab (A2, Wrap-up window) with any other module's confirmation |
| F36 | Defaulting M1's completion-by-group breakdown to a geographic column when a Treatment/Control column exists and geography wasn't explicitly opted into (default: declined) |
| F37 | Treating a project description/PAP document as a data source (parsing findings or role fields out of it) or letting it silently override what the actual microdata shows |
| F38 | Including a skip-logic-dependent (conditional) variable in the missingness variable pool (unified shortlist or M7's extra vars) without an explicit user request to include that specific variable |
| F39 | Reading the survey instrument/form via a raw `Read` of the `.xlsx` (surfaces only its first sheet) instead of `scripts/lib/form_text.R`'s all-sheet dump — silently misses the `choices` sheet's value labels and the `settings` sheet's form metadata |
| F40 | Proposing a GPS distance-threshold tab as part of standard setup, or describing M10 GPS Map as flagging points by default — it's a pure visualization unless the advanced opt-in flag (`modules$M10$advanced_distance_flag$on`) is specifically requested |
| F41 | Describing M7 Missingness as flagging an enumerator or variable by default — it's descriptive only unless the advanced opt-in flag (`modules$M7$advanced_enum_flag$on`) is specifically requested |
| F42 | Calling M1's roster-mode BY GROUP ratio (Completed / Target N) "Completion" — it's "Progress," deliberately distinct from every other completion table on the page (Completed / Submitted) |
| F43 | Reusing M1's `% Replaced` formula (Replaced / Primary Targeted) for M12 Balance Tables' Replacement Success % — the two are deliberately different denominators (M12's is Replacements N / Non-Completed Primary) |
