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
8. **Never** ask the user to type mega-strings such as `M1=Y M2=Y M10=none`, and never present a long menu of choices in place of a stated guess.
9. **List full item sets explicitly** in a tab's own text (e.g. every variable name) — only the *options* array is capped at 4, the description text isn't. No more separate numbered-list-in-chat workaround.
10. **Fallback** (AskUserQuestion unavailable): state the guesses as a numbered list in chat and ask the user to reply "looks good" or describe corrections — still not long free-form module strings.
11. Agent note: AskUserQuestion is unavailable inside Agent-tool subagents — run these confirms in the main chat.
12. **Never re-ask a tab a prior answer already resolved.** Check A1's Instructions answer and any hand-edited `modules.yaml`/`role_map.yaml` value before presenting a tab; skip it (stating the fact once in chat) if already settled. See SKILL.md Operating Principle 19 and the Map focus row below for the concrete case this exists for.
13. **GPS Map (M10) never has a distance-threshold tab in standard setup** — it's a pure visualization by default (SKILL.md Operating Principle 20). Missingness (M7) likewise has no threshold tab — it's descriptive only by default (Operating Principle 21). Both modules' old flagging logic still exists, but only surfaces if the user's own Instructions specifically ask for it.

## Gate map (Pipeline A)

**Only 5 gates fire on a normal run: Config reuse, Data found, Instructions, Completion Signal, and Review & Approve.** Everything else below ("Decided silently" rows) is applied directly to `modules.yaml`/`role_map.yaml` with no `AskUserQuestion` call and no chat narration — replayable only via Review & Approve's "Walk me through all modules" option (see Deep Review tabs at the bottom).

| Window | Tabs | When | Fires |
|---|---|---|---|
| Data files | — | After discovery | Not a choice — tell the user inline if nothing was found and to drop files in; the found case is confirmed as part of Setup below |
| Config pre-flight (A0) | — | Before Pipeline A/B start, every run | Mandatory — not a choice; if unreachable, stop and direct the user to set it up (no AskUserQuestion, just an inline message) |
| **Config reuse** (A0b) — Gate 1 | Reuse config | Only if `role_map.yaml`+`modules.yaml` already exist | 3 real options: reuse and rebuild (recommended) / start fresh / let me edit the files first |
| Blank modules.yaml draft | — | Right after discovery, before Setup | Not a choice — `preview_modules.R --blank` writes an unfilled `hfc/config/modules.yaml` (every module's `desc:` only, no guesses yet, no data dependency). Its real path is stated in the Setup window's Instructions tab, inviting the user to pre-fill it directly |
| **Setup** (A1) — Gates 2-3 | Data found, Instructions | Immediately after data discovery, before any role profiling | 2 tabs, one fact each — data found (paths + row/column/date-range, plus a project description/PAP doc if found), and an open "any specific instructions, or specific checks you'd like run?" catch-all naming the blank modules.yaml's path. Any requested check is matched to a standard module or authored as an M9 custom check right after this answer, silently — no separate Field Request tab exists anymore |
| Entity, Country, duplicate key, media columns | — | Decided silently, right after Setup | Not a choice — same guess logic as always (`shortlist_entity_ids()`, geography/GPS-bbox country inference, auto-resolved duplicate key, `detect_media_vars()`), written directly to `role_map.yaml`. Replayable under Deep Review's "Entity & Country" window |
| **Completion Signal** (A1) — Gate 4 | Completion Signal | Right after the signal-detection pass, whenever gating, roster, or primary_secondary was found | 1 tab — states the guessed signal (gate question(s) in form order, or the roster/primary_secondary signal instead), and that a failing gate's value becomes a non-completion "Reason" (first failed gate wins). Skipped entirely (no tab) when no signal at all was found. Daily target and Replacement sample are decided silently alongside it (same guess logic as before — median enumerator-day count; roster status/rank/group columns) — replayable under Deep Review |
| Informed modules.yaml draft | — | Right after the Completion Signal step, start of A2 | Not a choice — `preview_modules.R` (no flag) merges fresh role-informed guesses with whatever the user pre-filled in the blank draft (`merge_prefilled_modules()`), rewriting the same file in place |
| Every other module setting (A2) | — | Decided silently, all of A2 | Not a choice — duplicate key, form version, duration column (+ section pairs), work hours, last date, variables/sentinel codes, GPS coordinates, media columns, map focus, geography opt-in, group label, Balance Tables groupings, consent/assent/audio mapping, Excel columns — all written directly to `modules.yaml`/`role_map.yaml`, same guess logic as always. Replayable, exact tab wording preserved, under Deep Review (see below) |
| Custom check name | — | If a specific check was requested in Instructions (A1) and doesn't map to a standard module | Not a separate gate — name it, write `hfc/code/checks/<name>.R`, and proceed |
| Report type | — | Before build | Not a choice — always HTML, no AskUserQuestion |
| **Review & Approve** (A4) — final gate | Review & Approve | Once the report (and, on a true first-ever setup, `hfc/structure.html`) are open | 1 tab, 3 real options (a 4th, free-text "Other," is automatic — never authored as a literal option): "All good!" (recommended, commits the pending tracking file) / "Walk me through all modules" (replays every Deep Review window, pre-filled, then rebuilds and re-asks) / a described fix or "I edited the yaml files myself" (applies it, rebuilds, re-asks). Loops until approved — the only gate that touches the live `issue_tracking.xlsx` |
| **Proceed** (Pipeline B) | Proceed | After listing Open + Comment rows | States row count; proceed with all (recommended) / only some (Other) |
| **Commit** (Pipeline B) | Commit | After all rows handled, before the live file changes | States Resolved/Needs Review counts; confirm merge (recommended) / let me review first |

### Deep Review tabs (only under Review & Approve's "Walk me through all modules")

Same windows, same tab wording and options as always — just replayed on request instead of firing automatically, each pre-filled with the value already computed:

| Window | Tabs |
|---|---|
| Entity & Country | Entity, Country |
| Completion Signal extras | Daily target, Replacement sample (conditional) |
| Keys & Hours | Duplicate key, Form version (conditional), Duration column, Work hours |
| Dates, Variables & GPS | Last date, Variables, Sentinel codes, GPS coordinates (conditional) |
| Media, Map & Grouping | Media columns, Map focus (conditional), Add geography (conditional), Group label |
| Wrap-up | Consent mapping, Balance Tables groupings (conditional), Excel columns |

(Field Request isn't part of Deep Review — it's handled once, every run, at Setup's Instructions tab.)

Windows are ordered above by when they fire, not alphabetically. On a first-time clean run, only Setup → Completion Signal → Review & Approve → Proceed → Commit actually appear (5 windows) — Config reuse is a rebuild-only conditional, Completion Signal only fires when a real signal was found, and Deep Review only fires if explicitly requested.

Gates removed from the old per-module-card flow entirely (no longer separate confirms even under Deep Review — see the rows above for where they now live as guessed values): Entity ID (auto-resolved, surfaces only via the Entity tab's "in place of `<col>`" phrasing when reviewing), duplicate-check key (auto-resolved, restated in Keys & Hours when reviewing), the module pace question (Accept-all vs. Review — collapsed entirely into the guess-first pattern), the project README confirm (auto-written, no gate at all), and — new in this round — every module-confirmation window itself, Structure, and Field Request as *default* gates (all decided silently; Structure's function is now covered by Review & Approve itself, Field Request by the Instructions tab).

## After choices

Write `hfc/config/modules.yaml` + `hfc/config/role_map.yaml` from **confirmed** (guessed-then-accepted, or silently-decided) options, then run builders. Do not silently overwrite user corrections with profile defaults. All built product lands under `hfc/` inside the configured Code Output Directory. **The live `issue_tracking.xlsx` itself is never written until Review & Approve's "All good!"** — every build produces only a pending `merged_issue_tracking.xlsx` before that.
