# Interactive confirms (AskUserQuestion)

Authority for how FieldLoop asks the user during setup and post-feedback in **Claude Code** (VS Code).
**Primary UX is always multiple-choice AskUserQuestion cards** — never typed mega-strings in the chat box.

## Rules

1. **Use the AskUserQuestion tool** for every interactive gate (Claude Code multiple-choice UI).
2. **2–4 options per question.** Each option has a `label` and short `description`. Put the **recommended** choice first (label may say “recommended”).
3. **Do not add an explicit “Other” option** — Claude Code always offers free-text Other.
4. If the user picks **Other**, use their free text for **that gate only**.
5. **`header`** on each question: short label, max **12 characters**.
6. **1–4 questions** per AskUserQuestion call. One call per assistant turn when sequencing unrelated gates; related gates may share one call.
7. **`multiSelect: true`** only when several options can apply together (e.g. composite-ID columns, or a variable shortlist for M6/M7/M9/M10). Mutually exclusive choices stay single-select.
8. **Never** ask the user to type mega-strings such as `M1=Y M2=Y M8=none` as the primary UX (F19).
9. Do **not** dump numbered menus in plain chat when AskUserQuestion is available.
10. **Fallback** (AskUserQuestion unavailable): same options as a short numbered list; user replies with a single number/letter — still not long free-form module strings.
11. Max ~8–12 cards for module setup; never one free-text question per column.
12. **Required-fields gate** is mandatory after data confirm, before any module cards — five sequential sub-gates: Entity ID (single or composite; shortlist ≤3/≤4 candidates, Other automatic; do not proceed without a choice, F20), Entity Label (display-only name for the HTML report, e.g. "Student ID"; "Entity ID" recommended), duplicate-check key (auto-skip only when Entity ID is already unique; otherwise offer Entity ID alone / detected round-wave-like candidates, F27), country(ies) + timezone (always show the resolved timezone back for confirmation, F24), and last date of data collection (F25).
13. Some gates are genuinely sequential — a later question's options or wording depend on an earlier answer (e.g. M7 Missingness: sentinel-code question must name the variables just confirmed). Author the dependent question after the prior answer resolves; do not pre-write it as a static card.
14. Agent note: AskUserQuestion is unavailable inside Agent-tool subagents — run these confirms in the main chat.

## Gate map (Pipeline A)

| Gate | When | Example options (Other is automatic — do not list it) |
|---|---|---|
| Project folder | Workspace has multiple surveys / path unclear | up to 4 candidates |
| Data files | After discover | Use discovered paths (recommended) / Pick different paths / Wait — I will upload |
| **Entity ID** | **Immediately after data confirm** | Single column vs. combine multiple; up to 3 (single) or 4 (composite, `multiSelect`) shortlisted candidates |
| **Entity Label** | **Right after Entity ID** | "Entity ID" (generic, recommended) / Other (free text, e.g. "Student ID") — display-only, HTML report only |
| **Duplicate-check key** | **Right after Entity Label** | Auto-skipped when Entity ID is already unique; otherwise Entity ID alone / add detected round-wave-like column(s), up to 4 (`multiSelect`) (F27) |
| **Country(ies) + timezone** | **Right after duplicate-check key** | Single country vs. multiple (+ country column if multiple); resolved timezone always shown back for confirmation (F24) |
| **Last date of data collection** | **Right after country/timezone** | Use detected max date (recommended) / a different date (F25) |
| Media folder | Media filename cols found | Use discovered folder (recommended) / Column-only checks (no folder) |
| Module pace | After profile | Accept all recommended defaults / Review module-by-module |
| M1–M13 | If reviewing (or sub-picks after Accept all) | See `check_modules.md` option cards |
| **M3 Form Version mapping** | If reviewing M3, or a version column/inference is found | Use detected/inferred version↔date mapping (recommended) / Edit mapping |
| **M7 Missingness variables** | If reviewing M7 | Use recommended shortlist (≤10) (recommended) / Edit list |
| **M7 Missingness codes** | **After M7 variables confirmed — question must name those variables** | No special codes (recommended) / Same code(s) for all / Different codes per variable |
| **M9 Straightlining thresholds** | If reviewing M9 | Enumerator threshold 80% (recommended) / 70% / 90%; Survey threshold 80% (recommended) / 70% / 90% (confirmed independently) |
| **Additional checks** | After proposed modules reviewed — **always fires, even under Accept-all pace; never skip or auto-answer (F23)** | No additional checks (recommended) |
| Custom check name | If user requested an extra check | Confirm proposed name + `hfc/code/checks/<name>.R` |
| **Product structure** | After modules + extras; before build | Continue with this structure (recommended) |
| OneDrive pre-flight (A0c) | Before Pipeline A/B start, every run | Mandatory — not a choice; if unreachable, stop and direct the user to set it up (no AskUserQuestion, just an inline message) |
| **Issue tracking columns** | Before writing `issue_tracking.xlsx` | Keep the standard columns (recommended) / Modify columns |
| Map focus | If GPS / M8 on | Country / City / World |
| Report type | Before build | HTML (recommended) |
| Project README | After draft | Write this README (recommended) |
| Pipeline B proceed | After listing Open + RIL-Comment rows | Proceed with these N rows (recommended) |
| Pipeline B commit | After all rows handled, before the live file changes | Confirm the merged resolutions file — warn this replaces the live shared `issue_tracking.xlsx` (recommended) |

When a review card would need more than 4 choices, split into sequential AskUserQuestion calls.

## After choices

Write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from **selected** options, then run builders. Do not silently overwrite user picks with profile defaults. All built product lands under `hfc/` (not project root).
