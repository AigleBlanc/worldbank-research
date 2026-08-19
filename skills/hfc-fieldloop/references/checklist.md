# Package checklist

Use after Pipeline A (setup) and again after Pipeline B (post-feedback).

## Always required (setup)

| Item | Required |
|---|---|
| Microdata in the configured Input Data Directory (immutable) | yes |
| Instrument / form (also in the Input Data Directory) | optional (preferred for M9 / M3 / nested skip-logic) |
| Project description / Pre-Analysis Plan (pdf/doc/docx/txt/md, also in the Input Data Directory) | optional (read once for background context; never a data source) |
| `hfc/structure.html` opened alongside the report at the final Review & Approve gate (first-ever setup only — a rebuild opens only the report) | yes |
| Setup window (A1) — Gates 2-3: data found, Instructions (incl. any specific-check requests) confirmed | yes |
| Completion Signal window (A1) — Gate 4: gate question(s)/reasons or roster/primary-secondary confirmed, if a signal was detected | yes |
| Entity, Country, and every A2 module setting decided silently (no confirmation by default) | yes (reviewable via "Walk me through all modules" at Review & Approve) |
| Review & Approve window (A4) — final gate: approved before the live `issue_tracking.xlsx` is written | yes |
| `hfc/project.yaml` | yes |
| `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` | yes (agent writes from confirmed options before build) |
| `hfc/code/main.R` (one path global) | yes |
| `hfc/code/checks/` modules (real, runnable per-module scripts + custom) | yes |
| `hfc/outputs/issues.csv` with stable, content-derived `finding_id` (Issue ID) | yes |
| Live `issue_tracking.xlsx` in OneDrive, with `Status` | yes (defaults Open; the one shared file — agent, RA, and field team all edit it; no local copy) |
| `hfc/outputs/<MMDD>_HFCs.html` | yes (navigable; searchable tables) |
| Project `README.md` drafted from `assets/README_template.md` | yes (drafted automatically, no confirmation) |

## OneDrive (required)

| Item | Notes |
|---|---|
| `config.json` with Input Data Directory, HFC Output Directory, Code Output Directory all set to real paths (Media Folder Directory optional) | Skill-level config, no per-project override — HFC Output Directory is the OneDrive desktop app's synced local folder |
| Config pre-flight (A0) passes before any real work starts | No local-only mode — `require_fieldloop_config_ready()` stops the build otherwise |
| Folder shared with collaborators via OneDrive's own "Specific people" UI (once, by hand) | Code never mints its own share links |

## After post-feedback

| Item | Required |
|---|---|
| `hfc/code/resolutions/<Issue ID>.R` per resolved/reviewed finding, defining `fix(ds)` | yes |
| `<sibling of Input Data Directory>/intermediate/<stem>.<ext>` updated (raw unchanged) | yes |
| Today's `resolutions/<date>_issues_resolution.xlsx` clone has `Status` updated (`Resolved` / `Needs Review`) + `Corrections` — live `issue_tracking.xlsx` untouched until merge+commit | yes |
| `merge_resolutions.R` run, merged file reviewed with the user (AskUserQuestion), then `commit_merged_issue_tracking.R` run to update the live file | yes |

## Smoke

- [ ] `hfc/outputs/<MMDD>_HFCs.html` opens at the final Review & Approve gate; `hfc/structure.html` opens alongside it only on a true first-ever setup
- [ ] Report tables searchable; GPS map present when M10 on and coordinates exist, with every valid-coordinate point shown; no flagged (red) points unless the project specifically turned on the advanced distance flag
- [ ] Last Day tab present and populated when a last date was confirmed
- [ ] Every table sorted by enumerator, then unique ID, then date (most recent first)
- [ ] `issue_tracking.xlsx`, plus a copy of the report, present in the shared OneDrive-synced folder
- [ ] Grep: no hardcoded user home paths outside `hfc/code/main.R`
- [ ] If survey has pictures/audio: M13 on; filename cols not mis-filed under M14; M13 findings are dataset-level (one per fully-empty column), never per-row file-hygiene findings
- [ ] Nested skip-logic blanks not flagged as missing when form available
- [ ] If a completion signal was confirmed: M1 reports target-vs-actual (or primary/secondary composition) by group (Treatment/Control by default) and by enumerator; a "gating" signal's non-completed rows do not appear in any M2-M14 finding; a Reasons breakdown renders when gating found more than zero non-completions
- [ ] M8 straightlining fires at its defaults (100% per enumerator per day, min. 3 that day; 90% within one submission) unless explicitly overridden
- [ ] M7 Missingness shows only its reference tables (no findings) unless the project specifically turned on the advanced enumerator flag
- [ ] If M12 Balance Tables is on: gt-rendered tables appear right before All Issues, four per grouping, in order (Completed Interviews, By \<group\>, Completion Regression, Replacements); M1's roster-mode BY GROUP column reads "Progress," not "Completion"
- [ ] Country was inferred from data content (or an explicit column), not the input folder's name
