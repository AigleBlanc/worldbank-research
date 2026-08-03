# Package checklist

Use after Pipeline A (setup) and again after Pipeline B (post-feedback).

## Always required (setup)

| Item | Required |
|---|---|
| `data/raw/` microdata (immutable) | yes |
| Instrument / form | optional (preferred for M11 / M3 / nested skip-logic) |
| Media folder (`data/raw/media/` or discovered) | optional (M12 on-disk checks; column checks still run) |
| `hfc/structure.html` reviewed + Continue confirmed | yes |
| Required-fields gate: Entity ID, duplicate-check key, country(ies)/timezone, last date | yes (F20, F27, F24, F25) |
| `hfc/project.yaml` | yes |
| `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` | yes (agent writes from confirmed options before build) |
| `hfc/code/main.R` (one path global) | yes |
| `hfc/checks/` modules (stubs, templates, custom) | yes |
| `hfc/registry/findings.csv` with stable, content-derived `finding_id` (Issue ID) | yes |
| `hfc/registry/issue_tracking.csv` (local audit copy) + live `issue_tracking.xlsx` (OneDrive or `hfc/output/`) with `Status` | yes (defaults Open; the one shared file — agent, RA, and field team all edit it) |
| `hfc/report/index.html` | yes (navigable; searchable tables) |
| Project `README.md` drafted from `assets/README_template.md` | yes (confirm once with user) |

## OneDrive (optional but preferred)

| Item | Notes |
|---|---|
| `assets/lib/onedrive.json` with `"enabled": true` + `folder_path` | Skill-level config, no per-project override |
| Local `issue_tracking.xlsx` only if OneDrive missing / `--no-onedrive` | Builder must still succeed |
| One-time interactive sign-in via `setup_onedrive_auth.R`, run by the user outside Claude Code | Token then cached and auto-refreshed; no secrets stored in this package |
| Folder shared with collaborators via OneDrive's own "Specific people" UI (once, by hand) | Code never mints its own share links |

## After post-feedback

| Item | Required |
|---|---|
| `hfc/fixes/<Issue ID>.R` per resolved/reviewed finding, defining `fix(ds)` | yes |
| `data/intermediate/<stem>.<ext>` updated (raw unchanged) | yes |
| Today's `resolutions/<date>_issues_resolution.xlsx` clone has `Status` updated (`Resolved` / `Needs Review`) + `Corrections` — live `issue_tracking.xlsx` untouched until merge+commit | yes |
| `merge_resolutions.R` run, merged file reviewed with the user (AskUserQuestion), then `commit_merged_issue_tracking.R` run to update the live file | yes |

## Smoke

- [ ] Open `hfc/structure.html` then `hfc/report/index.html` in a browser
- [ ] Report tables searchable; GPS map present when M8 on; flagged points render in a distinct color from non-flagged points
- [ ] Last Day tab present and populated when a last date was confirmed; matching findings bolded in their own module tables
- [ ] Every table sorted by enumerator, then unique ID, then date (most recent first)
- [ ] `issue_tracking.xlsx`, plus the report link, reachable from the shared OneDrive folder (or local `hfc/output/` path documented)
- [ ] Grep: no hardcoded user home paths outside `hfc/code/main.R`
- [ ] If survey has pictures/audio: M12 on; filename cols not mis-filed under M13
- [ ] Nested skip-logic blanks not flagged as missing when form available
