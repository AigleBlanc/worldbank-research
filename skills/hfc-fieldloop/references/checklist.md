# Package checklist

Use after Pipeline A (setup) and again after Pipeline B (post-feedback).

## Always required (setup)

| Item | Required |
|---|---|
| `data/raw/` microdata (immutable) | yes |
| Instrument / form | optional (preferred for M11 / M3 / nested skip-logic) |
| Media folder (`data/raw/media/` or discovered) | optional (M12 on-disk checks; column checks still run) |
| `hfc/structure.html` reviewed + Continue confirmed | yes |
| Required-fields gate: unique identifier(s), country(ies)/timezone, last date | yes (F20, F24, F25) |
| `hfc/project.yaml` | yes |
| `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` | yes (agent writes from confirmed options before build) |
| `hfc/code/main.R` (one path global) | yes |
| `hfc/checks/` modules (stubs, templates, custom) | yes |
| `hfc/registry/findings.csv` with stable `finding_id` | yes |
| `hfc/registry/feedback.csv` with `status` + `resolved` | yes (defaults Open / No; no `check_module`) |
| `hfc/output/tracking.xlsx` | yes |
| `hfc/output/feedback_sheet.xlsx` | yes |
| `hfc/report/index.html` | yes (navigable; searchable tables) |
| Project `README.md` drafted from `assets/README_template.md` | yes (confirm once with user) |

## OneDrive (optional but preferred)

| Item | Notes |
|---|---|
| `hfc/config/onedrive.json` with real `site_url`/`folder_path` | Prefer over skill placeholders |
| Local twin only if OneDrive missing / `--no-onedrive` | Builder must still succeed |
| One-time interactive sign-in via `scripts/onedrive_auth_setup.R`, run by the user outside Claude Code | Token then cached and auto-refreshed; no secrets stored in this package |
| Folder shared with collaborators via OneDrive's own "Specific people" UI (once, by hand) | Code never mints its own share links |

## After post-feedback

| Item | Required |
|---|---|
| `hfc/fixes/` as used | yes |
| `data/raw/*_resolved.*` sibling (raw unchanged) | yes |
| Feedback `resolved` updated (`yes` / `partial` / `No`) | yes |
| Audit file updated when OneDrive configured | yes |

## Smoke

- [ ] Open `hfc/structure.html` then `hfc/report/index.html` in a browser
- [ ] Report tables searchable; GPS map present when M8 on; flagged points render in a distinct color from non-flagged points
- [ ] Last Day tab present and populated when a last date was confirmed; matching findings bolded in their own module tables
- [ ] Every table sorted by enumerator, then unique ID, then date (most recent first)
- [ ] Main feedback file (and report link) reachable from the shared OneDrive folder (or twin path documented)
- [ ] Grep: no hardcoded user home paths outside `hfc/code/main.R`
- [ ] If survey has pictures/audio: M12 on; filename cols not mis-filed under M13
- [ ] Nested skip-logic blanks not flagged as missing when form available
