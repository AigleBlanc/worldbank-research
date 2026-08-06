# Interactive confirms (AskUserQuestion)

Authority for how FieldLoop asks the user during setup and post-feedback in **Claude Code** (VS Code).
**Primary UX is always guess-first-then-correct** — the agent states its own best guess in plain language, then gives one free-text way to fix anything wrong. Never a long menu of options to choose between, and never typed mega-strings in the chat box.

## Two structural terms

- **Window** = one `AskUserQuestion` tool call.
- **Tab** = one `question` entry inside that call. A window can hold up to 4 tabs, all shown to the user together as a single interaction.

## Rules

1. **Use the AskUserQuestion tool** for every interactive gate (Claude Code multiple-choice UI).
2. **State the guess, not a menu.** Each tab's `question` text is the agent's plain-language best guess for the relevant field(s) — not a question the user has to interpret. The tab needs exactly one non-`Other` option, along the lines of **"Looks right (recommended)"**.
3. **Do not add an explicit "Corrections" option** — Claude Code always offers free-text Other, and that IS the correction box.
4. If the user picks **Other**, use their free text to correct whatever that tab covered.
5. **`header`** on each question: short label, max **12 characters**.
6. **1–4 tabs per window**, bundled by relatedness (see the Gate map below for exactly which tabs share a window) — never more than one tab per check module, and bundle related modules into a shared tab wherever the map says so.
7. **`multiSelect: true`** only when several options can genuinely apply together (rare under the guess-first pattern — most tabs are single-select "Looks right" / Other).
8. **Never** ask the user to type mega-strings such as `M1=Y M2=Y M8=none`, and never present a long menu of choices in place of a stated guess.
9. Do **not** dump numbered menus in plain chat when AskUserQuestion is available — the one exception is the up-to-10-item important-variables shortlist (A2 step 4), which is posted as a numbered list because the tool's 4-option cap can't hold 10 items; it's still referenced (not re-listed) inside its AskUserQuestion tab.
10. **Fallback** (AskUserQuestion unavailable): state the guesses as a numbered list in chat and ask the user to reply "looks right" or describe corrections — still not long free-form module strings.
11. Some tabs speculatively guess more than one thing at once even when they're logically dependent (e.g. Window B's Variables tab guesses both the variable shortlist AND the sentinel-missing-codes for those variables, together) — this is intentional under the guess-first pattern: a wrong guess on either is corrected via the same free-text box, so there's no need to sequence them into separate questions the way a menu-based UI would have required.
12. Agent note: AskUserQuestion is unavailable inside Agent-tool subagents — run these confirms in the main chat.

## Gate map (Pipeline A)

| Window | Tabs | When | What each tab states |
|---|---|---|---|
| Data files | — | After discovery | Not a choice — tell the user inline if nothing was found and to drop files in; no AskUserQuestion needed for the found case, it's confirmed as part of the Setup window below |
| **Setup** (A1) | Tab 1 "Confirm setup" (always), Tab 2 "Completion" (only if a completion signal was detected) | Immediately after data discovery, before any module work | Tab 1: discovered data/media files, the Entity Label (+ which column it replaces), and the data-collection country (+ timezone) — all three guessed at once, one shared correction box. Tab 2: the detected completion signal (status column / roster file / primary-secondary column) — flags a conflict explicitly if more than one signal was found |
| Check-modules preview | — | Right before Window B | Not a choice — build/open `hfc/check_modules.html` (tree of proposed defaults) for the user to review while answering the tabs below |
| **Module config B** (A2) | (a) "Dupes+Version", (b) "Timing", (c) "Variables", (d) "GPS+Media" | After the preview is open | (a): duplicate-check key restated + form version guess. (b): duration column/SD rule, work-hours window/weekend flag, and last date of data collection, all guessed together. (c): references the posted important-variables list, plus M6 SD threshold, M7 sentinel-code guess, and M9's fixed 90% threshold (stated, not asked). (d): GPS distance threshold, media-indicating columns restated, map focus default, and (only if a Treatment/Control column exists) an opt-in ask for an additional geographic grouping, default declined |
| **Module config C** (A2) | (e) "Consent", (f) "Extra checks" | Same call as Window B's follow-up, or immediately after | (e): assent/consent/audio-consent column mapping, explicitly named — never bundled with anything else. (f): "No additional checks" (recommended) / Other for a custom M11 check — mandatory every run |
| Custom check name | — | If the user requested an extra check in tab (f) | Confirm proposed name + `hfc/code/checks/<name>.R` |
| **Product structure** | — | After A2, before build | Continue with this structure (recommended) |
| Config pre-flight (A0) | — | Before Pipeline A/B start, every run | Mandatory — not a choice; if unreachable, stop and direct the user to set it up (no AskUserQuestion, just an inline message) |
| **Issue tracking columns** | — | Before writing `issue_tracking.xlsx` | Keep the standard columns (recommended) / Modify columns |
| Report type | — | Before build | Not a choice — always HTML, no AskUserQuestion |
| Project README | — | After draft | Write this README (recommended) |
| Pipeline B proceed | — | After listing Open + RIL-Comment rows | Proceed with these N rows (recommended) |
| Pipeline B commit | — | After all rows handled, before the live file changes | Confirm the merged resolutions file — warn this replaces the live shared `issue_tracking.xlsx` (recommended) |

Gates removed from the old per-module-card flow entirely (no longer separate confirms — see the Setup/Module-config windows above for where they now live as guessed values): Entity ID (auto-resolved, surfaces only via the Setup tab's "in place of `<col>`" phrasing), duplicate-check key (auto-resolved, restated in tab (a)), last date of data collection (moved into tab (b)), the module pace question (Accept-all vs. Review — collapsed entirely into the guess-first pattern, there's no separate "review" path anymore), and map focus (moved into tab (d)).

## After choices

Write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from **confirmed** (guessed-then-corrected) options, then run builders. Do not silently overwrite user corrections with profile defaults. All built product lands under `hfc/` inside the configured Code Output Directory.
