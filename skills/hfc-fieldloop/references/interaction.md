# Interactive confirms (AskUserQuestion)

Authority for how FieldLoop asks the user during setup and post-feedback in **Claude Code** (VS Code).
**Primary UX is guess-first-then-accept, one atomic fact per tab, minimal text, packed into as few windows as possible.**

## Two structural terms

- **Window** = one `AskUserQuestion` tool call.
- **Tab** = one `question` entry inside that call, covering exactly ONE fact/guess. A window can hold up to 4 tabs, all shown to the user together as a single interaction.

## Standard tab template

> *[Guess + how it's used. ≤2 sentences, no em-dashes.]*
> Option 1: starts with "Looks good" (e.g. "Looks good!", "Looks good, continue!")
> Option 2: contextual to the tab's subject, not literally "Needs correction" (e.g. "The list needs edits", "A mapping is swapped") — "(I will type in Other)" unless a named 3rd/4th option already covers the correction path

## Rules

1. **Use the AskUserQuestion tool** for every interactive gate (Claude Code multiple-choice UI).
2. **One fact per tab.** Never bundle multiple independent guesses (e.g. duration column + SD rule + work hours) into one tab's text.
3. **Options aren't always the generic 2-choice pair.** When a rule has a natural partial-accept split (e.g. "flag work hours OR weekends" → maybe just one half) or an obvious alternate mode (e.g. "last date" → "include more days"), enumerate those as real, named options (up to 4) instead of routing everything through free-text Other.
4. **Do not add an explicit "Corrections" option** when relying on Other — Claude Code always offers free-text Other, and that IS the correction box.
5. **`header`** on each question: short label, max **12 characters**.
6. **Pack windows to capacity.** Backfill spare tab slots in an earlier window rather than opening a new one for 1-2 leftover facts — minimizing window count matters more than keeping tabs topically pure. Only a genuine data dependency (a tab whose content requires output that doesn't exist until a prior tab's answer is acted on) justifies a new window. See the Gate map below for the current packing.
7. **`multiSelect: true`** only when several options can genuinely apply together (rare — most tabs are single-select).
8. **Never** ask the user to type mega-strings such as `M1=Y M2=Y M8=none`, and never present a long menu of choices in place of a stated guess.
9. **List full item sets explicitly** in a tab's own text (e.g. every variable name) — only the *options* array is capped at 4, the description text isn't. No more separate numbered-list-in-chat workaround.
10. **Fallback** (AskUserQuestion unavailable): state the guesses as a numbered list in chat and ask the user to reply "looks good" or describe corrections — still not long free-form module strings.
11. Agent note: AskUserQuestion is unavailable inside Agent-tool subagents — run these confirms in the main chat.

## Gate map (Pipeline A)

| Window | Tabs | When | Fires |
|---|---|---|---|
| Data files | — | After discovery | Not a choice — tell the user inline if nothing was found and to drop files in; the found case is confirmed as part of Setup below |
| Config pre-flight (A0) | — | Before Pipeline A/B start, every run | Mandatory — not a choice; if unreachable, stop and direct the user to set it up (no AskUserQuestion, just an inline message) |
| **Config reuse** (A0b) | Reuse config | Only if `role_map.yaml`+`modules.yaml` already exist | 3 real options: reuse and rebuild (recommended) / start fresh / let me edit the files first |
| **Setup** (A1) | Data found, Entity, Country, Completion (conditional) | Immediately after data discovery, before any module work | Up to 4 tabs, one fact each — data found (paths + row/column/date-range, plus a project description/PAP doc if found — read silently for background context in step 1b, not a separate tab), entity label, country + timezone, completion signal (only if detected; states the downstream filtering effect) |
| Draft modules.yaml | — | Right after Setup, before module-config windows | Not a choice — write the commented, human-readable `hfc/config/modules.yaml` (every module's proposed defaults). Its real path isn't stated yet — that happens in the Wrap-up window below, once it's the natural point to mention it |
| **Keys & Hours** (A2) | Duplicate key, Form version (conditional), Duration column, Work hours | After the draft is written | Duplicate key restated. Form version + mapping only if 2+ versions exist. Duration column stated (M4's SD rule is a fully silent fixed default, never mentioned anywhere). Work hours: real partial-accept options (both / work-hours only / weekend only), not generic Other |
| **Dates, Variables & GPS** (A2) | Last date, Variables, Sentinel codes, GPS threshold | Same phase as Keys & Hours | Last date states the Last Day tab dependency, with a real "include more days" option. Variables lists the full important-variables shortlist inline (no separate chat post anymore). Sentinel codes. GPS distance threshold (M8). M6's fixed 3 SD threshold, M9's fixed 90% threshold, and M7's three missingness thresholds are all fully silent now — not mentioned in any tab |
| **Media, Map & Grouping** (A2) | Media columns, Map focus, Add geography (conditional), Group label | Same phase | Media columns restated from Setup. Map focus default. Geography opt-in only if a Treatment/Control column exists, real Yes/No options, default No. Group label (`derive_group_label()`'s guess) |
| **Wrap-up** (A2 tail + A3 + A4 prep) | Consent mapping, Extra checks, Structure, Excel columns | After the three module-config windows, once `hfc/structure.html` is built | Consent mapping, its own tab, never bundled. Extra checks: "No additional checks" (recommended) / Other for a custom M10 check, mandatory every run. Structure: states the real `modules.yaml` path here (first mention) — 3 options: continue / "I edited the specifications" (re-read the file) / change the plan. Excel columns: standard schema, keep/modify |
| Custom check name | — | If the user requested an extra check on the Extra checks tab | Confirm proposed name + `hfc/code/checks/<name>.R` |
| Report type | — | Before build | Not a choice — always HTML, no AskUserQuestion |
| **Merge confirm** (A4) | Merge | Only on a rebuild where `issue_tracking.xlsx` already exists | States the diff size (N new, M unchanged); merge (recommended) / let me review first |
| **Proceed** (Pipeline B) | Proceed | After listing Open + Comment rows | States row count; proceed with all (recommended) / only some (Other) |
| **Commit** (Pipeline B) | Commit | After all rows handled, before the live file changes | States Resolved/Needs Review counts; confirm merge (recommended) / let me review first |

Windows are ordered above by when they fire, not alphabetically. On a first-time clean run, only Setup → Keys & Hours → Dates/Variables/GPS → Media/Map/Grouping → Wrap-up → Proceed → Commit actually appear (7 windows) — Config reuse and Merge confirm are rebuild-only conditionals.

Gates removed from the old per-module-card flow entirely (no longer separate confirms — see the windows above for where they now live as guessed values): Entity ID (auto-resolved, surfaces only via the Setup tab's "in place of `<col>`" phrasing), duplicate-check key (auto-resolved, restated in Keys & Hours), the module pace question (Accept-all vs. Review — collapsed entirely into the guess-first pattern, there's no separate "review" path anymore), and the project README confirm (now auto-written, no gate at all).

## After choices

Write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from **confirmed** (guessed-then-accepted) options, then run builders. Do not silently overwrite user corrections with profile defaults. All built product lands under `hfc/` inside the configured Code Output Directory.
