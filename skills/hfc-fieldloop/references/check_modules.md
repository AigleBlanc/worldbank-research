# Check modules (M1–M13) — specs

Confirm modules via the guess-first-then-correct **AskUserQuestion** windows described in `interaction.md` and `SKILL.md`'s A1/A2 — the agent states its own best guess in plain language, the user gets one free-text way to correct it. Do not ask the user to type `M1=Y M2=…`. Do not ask 100 column questions.

## Required setup (Window "Setup", A1 — before any module work)

Confirmed in one window, up to 2 tabs, immediately after data discovery — not folded into M1–M13 review:

- **Tab 1 "Confirm setup" (always):** states three guesses together — (a) the discovered data + media files, (b) the Entity Label (a Title-Case guess for what to call the entity, e.g. "Household" — applies everywhere the entity is displayed: the HTML report's findings tables *and* the xlsx/csv issue-tracking export) with the underlying column named ("in place of `hhld_id`"), and (c) the data-collection country + resolved timezone — inferred from geography **in the data** (district/region/village names, a GPS bounding box) when there's no explicit country column, **never from the input folder's name**. All three in one message, one shared correction box.
  - Entity ID (the column itself) and the duplicate-check key are auto-resolved (`shortlist_entity_ids()`'s top pick; Entity ID alone if already unique, else + `detect_duplicate_key_candidates()`'s top hit) and are not separately confirmed — a wrong Entity ID pick is corrected via Tab 1's free-text box, since the entity line names the underlying column.
- **Tab 2 "Completion" (only if a completion signal is detected):** states the agent's interpretation of which completion signal applies (`detect_completion_signal()`) — a status column, a roster/target file, or a primary/secondary sample column. When more than one signal is detected at once, the message must explicitly flag the conflict rather than silently picking one.

Persist to `hfc/config/role_map.yaml`: `entity_id`, `entity_id_sep`, `entity_label`, `dup_key_extra`, `country_mode`, `country`/`country_col`/`country_timezone_map`, `timezone`, `qualitative_text_cols`, `completion_primary_signal`, `completion_status_col`, `completion_status_complete_values`, `completion_roster_candidate`, `completion_roster_key_col`, `completion_primary_secondary_col`, `completion_primary_value`. (`last_date`, `treatment_control_col`, `geo_group_col`, `geo_group_opted_in`, `map_focus`, `group_label`, `important_vars`, and `missingness_extra_vars` are confirmed later, in A2's module-config windows — see below.) `entity_display`/`enumerator_display`/`group_display` (de-identification-by-default: entity ID-only, enumerator/group name-if-available — see A1 step 4) are set to their fixed defaults by `profile_roles()` on every run, never guessed or confirmed in any window — edited directly in the yaml only on an explicit user request.

## Nested / skip-logic questions

Parent→child items (e.g. "Are you in school?" → if yes "Which grade?") must be evaluated with SurveyCTO `relevant` / skip logic when a form is available. **Do not flag child blanks as missing when the parent path makes them expected.** Without a form, note weaker nested handling; do not invent relevance.

## Module confirmation (Windows B and C, A2)

No separate "pace" question anymore (there's no more Accept-all vs. Review split) — every module setting is always stated as a guess with a correction box, bundled into two windows:

**Window B**, 4 tabs: (a) "Dupes+Version" — M2 + M3. (b) "Timing" — M4 + M5 + last date of data collection. (c) "Variables" — the unified important-variables shortlist (posted separately as a numbered chat list, referenced here) + M6's fixed 3 SD threshold + M7's sentinel-code guess and its three fixed missingness thresholds (50% variable-issue / 90% enumerator-pool / 50% enumerator-personal, all stated, not asked) + M9's fixed 90% threshold (stated, not asked). (d) "GPS+Media" — M8 + M11's media-indicating columns + map focus default + an opt-in geographic-grouping ask (only shown when a Treatment/Control column exists; default declined) + a guessed Group Label (`derive_group_label()`, e.g. "School" for `school_id` — what `roles$group` is called throughout the report/tracking sheet; distinct from the Treatment/Control-vs-geography grouping question above).

**Window C**, 2 tabs: (e) "Consent" — M12, its own tab, never bundled with anything else. (f) "Extra checks" — M10, mandatory every run.

**Mandatory, every run, cannot be skipped or silently auto-answered:** tab (f) always asks **Extra checks?** — `No additional checks` (recommended) (Other automatic for a custom check). If Other, design a named check under `hfc/code/checks/<name>.R`, confirm the name/file, register under M10/`custom`, and write a ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (`custom.<name>.description`) so the HTML report can show it (see "Report display labels & descriptions" below).

## M1 — Completion

**Default: ON.** Redefined from "did this row finish" to "were all planned surveys conducted." Signal type comes from A1's Tab 2 (`roles$completion_primary_signal`):

- **status** — an explicit per-row outcome column (Complete/Incomplete/Refused-style). Filters M2–M13 to the completed subset.
- **roster** — a target/planned-sample file compared against the actual survey data. Reports "planned vs. actually surveyed"; every surveyed row still counts as completed for M2–M13's purposes.
- **primary_secondary** — a column marking each surveyed row Primary or Secondary sample, when there's no separate roster. Reports the primary/secondary composition instead of a target-vs-actual rate; every row still counts as completed.
- **none detected** — falls back to the original row-missingness heuristic (`row_missing_ratio() <= 0.1`), unchanged from before this redesign.

Reports: overall, **by group** (one combined table covering both breakdowns when both apply — defaults to a detected Treatment/Control column — `modules$M1$group_vars`; only falls back to geography when no Treatment/Control column exists, or adds it alongside T/C only if the user opted in, each row tagged with which breakdown it belongs to), by enumerator (sorted lowest-to-highest completion), by date — counts **and** percentages, no charts by default. A separate, still-valid finding independently flags specific groups (keyed on `roles$group`, labeled with `roles$group_label` — e.g. "School has fewer completed submissions than…" — falling back to the generic "Group" when no label was guessed/confirmed) whose completion count falls below `modules$M1$pct_median` (default 50%) of the target — the median completion count across all groups. One aggregate-level finding per flagged group (no Entity ID, via `mk_aggregate_finding()`), never broken down by respondent.

## M2 — Duplicates

**Default: ON** — duplicate submission IDs / keys (DIME ieduplicates spirit); composite-ID aware.

Confirmed in Window B tab (a): the duplicate-check key is auto-resolved in A1 (Entity ID alone if unique, else + detected round/wave-like columns) and only restated here for visibility, correctable via tab (a)'s free-text box.

## M3 — Form Version

**Default: ON** — best-effort, always propose-then-confirm, never trust silently.

Confirmed in Window B tab (a), alongside M2: the version column (or, if none exists, a best-guess of N version windows from column-availability changes) + a date-range↔version mapping, stated as a guess only when a form with more than one detected version exists.

Reports: version × date-range × n table. Optional finding when a real version column exists: recorded version doesn't match the expected version for its date.

## M4 — Survey Duration

**Default: ON** — descriptive stats (overall / by section / by enumerator) plus outlier flagging, decoupled from M5's early-start logic. Duration is always converted to and reported in **minutes** (the source column is SurveyCTO's native seconds export).

Confirmed in Window B tab (b): duration column + SD rule (default 3), stated as a guess.

## M5 — Irregular Timing

**Default: ON** — timezone-aware (uses the country/timezone confirmed in A1's Setup tab); absorbs the old "early start" concept.

Confirmed in Window B tab (b), alongside M4: work-hours window (default 7pm–7am flags evenings/nights + weekends) and last date of data collection, stated as guesses.

## M6 — Numeric Outliers

**Default: ON** — up to 10 continuous vars (exclude IDs/codes), two-sided SD rule — **fixed at 3, not configurable via the interactive flow**.

Confirmed in Window B tab (c): uses the unified important-variables shortlist directly (no separate module-level variable ask). The SD threshold is stated as a fixed default, not asked (same treatment as M9's straightlining threshold).

## M7 — Missingness

**Default: ON** — by the unified important-variables shortlist (≤10) PLUS ~20 more agent-picked variables specific to missingness reporting (any type, not just numeric), and by enumerator.

Confirmed in Window B tab (c), alongside the variable shortlist: `guess_sentinel_codes()` speculatively scans the shortlisted variables' value distributions for likely sentinel/missing codes (99, -99, -9999, …) and states that guess in the SAME tab as the variable list — no longer a separate follow-up question. A wrong guess on either the variables or the codes is corrected via the same free-text box.

The ~20 extra missingness-specific variables are agent judgment only, made during the same setup pass and written directly to `hfc/config/role_map.yaml`'s `missingness_extra_vars` — **no `AskUserQuestion` confirmation**; an RA who disagrees corrects it only by editing the yaml directly, not in chat.

**Three fixed thresholds, stated not asked** (`modules$M7$var_issue_threshold`/`enum_pool_threshold`/`enum_pct_threshold`, defaults 0.5/0.9/0.5): a variable only appears in the by-variable stats table at all if its overall (population) missingness exceeds 50% — "only report the issues." Among those, a variable is only eligible for enumerator-level flagging if its overall missingness is ≥90% — a narrower, worse-off subset. Within that pool, an enumerator is flagged if their own personal missingness on that variable is ≥50%. Skip-logic-expected blanks (via `filter_expected_skips()`/`row_is_relevant()`, the same `hfc_form_map` mechanism M12 uses) are excluded from both the numerator and denominator at every stage, so a legitimately-skipped question never inflates missingness.

Reports: missingness % by variable (issues only, per the 50% gate) and by enumerator×variable (same gate). One aggregate-level finding **per flagged enumerator** (not per enumerator×variable) — every flagged variable listed in the issue text, every personal missingness % joined with " & " in Value — via `mk_aggregate_finding()`. No Entity ID, no per-submission rows.

## M8 — GPS

**Default: ON if coordinates found, else Off.**

Confirmed in Window B tab (d): the coordinate pair + distance threshold (default 300m), stated as a guess.

Map focus for the HTML report (Country / City / World, default Country) is also stated in tab (d), not a separate gate. On the map, all points are shown; points flagged by M8 render in red, others in the default color.

## M9 — Straightlining

**Default: ON if ordinal-like candidates are detected, else Off.**

Ordinal variables: intersects the confirmed unified important-variables list with the auto-detected ≤7-category ordinal pool; falls back to the full auto-detected pool if that intersection is empty (never silently turns M9 off over a variable-selection choice).

**Threshold is a fixed default, not a choice:** both the enumerator threshold (an enumerator gave the identical single answer on one question in ≥ this share of their own surveys) and the survey threshold (a submission where ≥ this share of the confirmed ordinal variables share one identical value) default to **90%**. Stated plainly in Window B tab (c) as a fixed default the user can still override via free text, but never presented as a choice between percentages.

The enumerator-level check produces one aggregate-level finding per flagged enumerator×variable (no Entity ID, via `mk_aggregate_finding()`) — genuinely different granularity from the survey-level check's per-submission findings, so the two render as separate tables in the HTML report even though both are "M9".

## M10 — Survey-specific

**Default: None.** M10 has no built-in checks — every M10 finding comes from a
custom check the agent writes for this survey's specific content, described
by the user in Window C tab (f).

Custom user-described checks are registered under M10/`custom` and live as
`hfc/code/checks/<name>.R`, with an exported `run_<name>(ds, roles)` — see
`assets/check_templates/custom_check_example.R` for the convention.

## M11 — Media files (audio, pictures, and qualitative text)

**Default: ON if media-indicating columns detected** (audio/image filename columns via `.m4a`/`.mp3`/… or `.jpg`/`.png`/… extensions, or agent-identified qualitative open-text columns).

**Redesigned to a single check, no on-disk file access at all:** flags a media-indicating column only if it is **completely empty across every surveyed row** — a strong signal of a form/coding problem (the field isn't showing up in the enumerator's app, or the question is misconfigured), not a per-row file-hygiene issue. This deliberately drops the old per-row checks (empty cell, file missing on disk, tiny file, bad extension, duplicate basename/hash, duration, flag↔file mismatch) — none of those survive.

Confirmed in Window B tab (d), alongside M8: the media-indicating columns (audio/image filename columns + any qualitative text columns), restated from A1 for visibility.

`config.json`'s Media Folder Directory is not read by this check (kept in config for potential future use).

## M12 — Consent / assent / audio flags

**Default: ON if flag columns found.**

Yes/no (or 0/1) **flags only** — not filename columns (those are M11). Respect nested skip-logic for assent/consent follow-ups.

**Confirmed in its own tab, Window C tab (e), never bundled with anything else** — assent and consent are different concepts (assent = the child/minor's own agreement; consent = the parent/guardian's, or an adult respondent's own) and mixing them up is a real risk worth isolating. States which column maps to assent, consent, and audio-consent, explicitly naming each: *"I found: `assent` → child's own agreement, `consent` → guardian consent, `audio_consent_flag` → recorded-audio consent. Tell me if any of these are swapped."*

## M13 — Summary Statistics

**Default: ON** — purely descriptive, zero findings rows.

Uses the confirmed unified important-variables list directly (no separate module-level variable ask).

Two kinds of tables, both Variable | Mean | SD | Min | Max | NA | Obs, no panel/lettered grouping: an **Overall** table (always first, all rows), plus one additional table **per enumerator** (using the enumerator's display name when available) — not a replacement for Overall, both always render together.

## After confirms

Map confirmed (guessed-then-corrected) values → `hfc/config/modules.yaml` + `hfc/config/role_map.yaml`, then run the builder. No typed mega-reply required.

## Report display labels & descriptions (authoritative)

Source of truth for how modules appear in `hfc/outputs/report.html` (mirrored as `MODULE_META` in `scripts/lib/build_outputs.R` — keep both in sync). Tab/heading text is the label; the module code still appears alongside it, smaller, since it's used internally (e.g. `issues.csv`). Descriptions are ≤3 plain-English sentences, no raw column names.

| Code | Label | Description |
|---|---|---|
| M1 | Completion | Reports how many submissions are complete overall, and by group, enumerator, and date, so gaps in fieldwork show up early. By default, also flags any group whose completed-submission count falls below 50% of the target — the median completion count across all groups — one finding per flagged group, never broken down by respondent. |
| M2 | Duplicates | Flags submissions that share the same unique ID or survey key, which usually means the same interview was uploaded or entered more than once. |
| M3 | Form Version | Tracks which version of the survey instrument was in use on each date, and flags any submission whose recorded version doesn't match the expected window for its date. |
| M4 | Survey Duration | Reports how long interviews took, in minutes, overall and by enumerator, and flags individual interviews that were unusually long or short. |
| M5 | Irregular Timing | Flags interviews conducted at unusual times — weekends or outside normal working hours — using each submission's local time zone. |
| M6 | Numeric Outliers | Flags unusually high or low values on key numeric questions (e.g. ages, scores) that fall outside the normal range for this survey. |
| M7 | Missingness | Flags variables and enumerators with unusually high rates of missing or sentinel-coded (e.g. 99, -9999) responses on key survey questions. |
| M8 | GPS Location | Flags submissions recorded far from where other submissions at that site were recorded, which can mean the interview happened somewhere unexpected. |
| M9 | Straightlining | Flags enumerators who gave the same answer on a question in 90%+ of their interviews, and submissions where 90%+ of ordinal/Likert-style questions share one identical value. |
| M10 | Survey-Specific | Flags logic issues specific to this survey's content (for example, a mismatch between a record saying something happened and the respondent's own answer), including any custom checks requested for this project. |
| M11 | Media Files | Flags a media-indicating column (audio, image, or qualitative-capture) that is completely empty across every surveyed row — usually a form/coding problem, not a per-row file issue. |
| M12 | Consent & Assent | Flags cases missing a required consent (guardian agreement) or assent (the child's own agreement) flag, which the survey should always capture before proceeding. |
| M13 | Summary Statistics | A simple reference table of mean, SD, min, max, and observation count for the survey's most important numeric variables. |

Custom/M10 checks confirmed via the Extra-checks tab get their own description, authored at confirm time and persisted to `hfc/config/module_notes.yaml`:

```yaml
custom:
  <name>:
    label: "Short human name"
    description: "≤3 sentences, plain English, no raw column names."
overrides:        # optional — replaces a default M1-M13 description above for this survey
  M6: "Custom text replacing the default M6 description."
```
