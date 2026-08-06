# Package checklist

Use after Pipeline A (setup) and again after Pipeline B (post-feedback).

## Always required (setup)

| Item | Required |
|---|---|
| Microdata in the configured Input Data Directory (immutable) | yes |
| Instrument / form (also in the Input Data Directory) | optional (preferred for M11 / M3 / nested skip-logic) |
| `hfc/structure.html` reviewed + Continue confirmed | yes |
| Setup window (A1): data/media files, Entity Label, country/timezone confirmed (+ completion signal, if detected) | yes |
| Module-config windows (A2): Dupes+Version, Timing (incl. last date), Variables, GPS+Media, Consent, Extra checks all confirmed | yes |
| `hfc/project.yaml` | yes |
| `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` | yes (agent writes from confirmed options before build) |
| `hfc/code/main.R` (one path global) | yes |
| `hfc/code/checks/` modules (real, runnable per-module scripts + custom) | yes |
| `hfc/registry/findings.csv` with stable, content-derived `finding_id` (Issue ID) | yes |
| Live `issue_tracking.xlsx` in OneDrive, with `Status` | yes (defaults Open; the one shared file — agent, RA, and field team all edit it; no local copy) |
| `hfc/outputs/report.html` | yes (navigable; searchable tables) |
| Project `README.md` drafted from `assets/README_template.md` | yes (confirm once with user) |

## OneDrive (required)

| Item | Notes |
|---|---|
| `config.json` with Input Data Directory, OneDrive Folder Directory, Code Output Directory all set to real paths (Media Folder Directory optional) | Skill-level config, no per-project override — OneDrive Folder Directory is the OneDrive desktop app's synced local folder |
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

- [ ] Open `hfc/structure.html` then `hfc/outputs/report.html` in a browser
- [ ] Report tables searchable; GPS map present when M8 on; flagged points render in a distinct color from non-flagged points
- [ ] Last Day tab present and populated when a last date was confirmed; matching findings bolded in their own module tables
- [ ] Every table sorted by enumerator, then unique ID, then date (most recent first)
- [ ] `issue_tracking.xlsx`, plus a copy of the report, present in the shared OneDrive-synced folder
- [ ] Grep: no hardcoded user home paths outside `hfc/code/main.R`
- [ ] If survey has pictures/audio: M12 on; filename cols not mis-filed under M13; M12 findings are dataset-level (one per fully-empty column), never per-row file-hygiene findings
- [ ] Nested skip-logic blanks not flagged as missing when form available
- [ ] If a completion signal was confirmed: M1 reports target-vs-actual (or primary/secondary composition) by group (Treatment/Control by default) and by enumerator; a "status" signal's Incomplete/Refused rows do not appear in any M2-M13/M10 finding
- [ ] M9 straightlining fires at the 90% default unless explicitly overridden
- [ ] Country was inferred from data content (or an explicit column), not the input folder's name
