# Check modules (M1–M13) — specs

Confirm modules via the guess-first-then-correct **AskUserQuestion** windows described in `interaction.md` and `SKILL.md`'s A1/A2 — the agent states its own best guess in plain language, the user gets one free-text way to correct it. Do not ask the user to type `M1=Y M2=…`. Do not ask 100 column questions.

## Required setup (Windows "Setup", "Entity & Country", "Completion Signals", A1 — before any module work)

**"Setup"**, 2 tabs, fires immediately after data discovery, before any role profiling:

- **Data found (always):** the discovered data/form paths, plus row count, column count, and collection date range.
- **Instructions (always):** an open "any specific instructions for this data or session?" catch-all — states the real path to a blank, pre-fillable `hfc/config/modules.yaml` (`preview_modules.R --blank`, no data dependency) that the user can hand-edit directly. Asked *before* role profiling specifically so the answer can skip inference (e.g. a stated country, a declined check), not just skip a later tab — see "Never re-ask" below.

Once the Instructions answer is applied (free text interpreted as directives, plus any hand-edited `modules.yaml` re-read), the agent reads `context_doc` (if found), then the instrument/form (if found), then finally loads and profiles the microdata — role profiling runs last, informed by everything already resolved. The instrument is read via `scripts/lib/form_text.R` (dumps every sheet of the workbook to plain text — `survey`, `choices`, `settings`, and any others — never just the raw `.xlsx`, which would only surface its first sheet), so choice-list value labels (`choices`) are available for judgment alongside the `survey` sheet's question text and skip logic.

**"Entity & Country"**, up to 2 tabs, fires right after:

- **Entity (always):** the Entity Label (a Title-Case guess for what to call the entity, e.g. "Household" — applies everywhere the entity is displayed: the HTML report's findings tables *and* the xlsx/csv issue-tracking export) with the underlying column named ("in place of `hhld_id`"). Entity ID (the column itself) and the duplicate-check key are auto-resolved (`shortlist_entity_ids()`'s top pick; Entity ID alone if already unique, else + `detect_duplicate_key_candidates()`'s top hit) and are not separately confirmed — a wrong Entity ID pick is corrected via this tab's free-text box, since the entity line names the underlying column.
- **Country (always, skipped if Instructions already stated it):** the data-collection country + resolved timezone (stated as abbreviation + city/country + UTC offset) — inferred from geography **in the data** (district/region/village names, a GPS bounding box) when there's no explicit country column, **never from the input folder's name**.

**"Completion Signals"**, up to 3 tabs, fires right after Entity & Country — each tab is independent of the other two (a project can have any combination, or none):

- **Gating & Reasons** (preferred signal, only when a/b/c below found something): the agent reads the instrument's `type`/`label`/`relevant` columns like an analyst would, looking for screening/eligibility questions whose failure skips most/all of the rest of the survey — `gate_fanout_counts()` (`scripts/lib/form_logic.R`) is a supporting ranking signal (how many other questions' `relevant` name each column as a parent), not a substitute for judgment. States the guessed gate(s) in form order plus that a failing gate's value becomes the "Reason" for that respondent's non-completion — first failed gate wins, since later gates were never reached. Falls back to naming a roster or primary/secondary signal here (same content as the old Completion tab) when no credible gate exists. Multiple genuinely-available signals at once must be named as an explicit conflict, never silently picked.
- **Daily target**: guesses a starting number (the overall median enumerator-day submission count) and asks for the real per-enumerator target, with a real "no daily target" decline option — drives M1's new day-by-day `low_completion_enum_day` check (a specific day's count below the confirmed target, not a median-based rule).
- **Replacement sample** (only when the roster/`target_ds` has status/rank/group columns — agent judgment, same posture as Gating detection, reading the roster's actual columns/values rather than guessing from a fixed name list): states the guessed status column (which values mean Primary), the position-in-replacement-queue column, and the group-matching column. Independent of which `completion_signal` is actually confirmed above — works even under `gating`. Drives `stats$by_replacement` (% of each group's targeted primary sample that was replaced) and the `replacement_sequence_gap` finding (a replacement completed while an earlier-ranked replacement in the same group's shared queue has no row in the data at all — skipped without being attempted).

**Never re-ask what's already resolved:** every A2 tab from here on checks the Instructions answer and any hand-edited `modules.yaml`/`role_map.yaml` value first — a tab whose subject is already settled gets skipped (state the fact once in chat), never re-asked. Concrete case: declining GPS checks skips both the GPS threshold tab (Dates, Variables & GPS) and the Map focus tab (Media, Map & Grouping) together, since `write_html_report()` ties the map's rendering to the M8 check being on.

Media-indicating columns (audio/image filenames, qualitative text) are detected here too but not stated until the Media, Map & Grouping window (A2) — no reason to front-load a fact that isn't needed until then.

Persist to `hfc/config/role_map.yaml`: `entity_id`, `entity_id_sep`, `entity_label`, `dup_key_extra`, `country_mode`, `country`/`country_col`/`country_timezone_map`, `timezone`, `qualitative_text_cols`, `completion_primary_signal`, `completion_roster_candidate`, `completion_roster_key_col`, `completion_roster_group_map` (only whichever `group_vars` entries needed a roster-side name remapping — see M1's completion-by-strata note below), `completion_primary_secondary_col`, `completion_primary_value`. (`completion_status_col`/`completion_status_complete_values` are superseded by gating — never written fresh, only read for backward compatibility with a pre-existing config.) Persist to `hfc/config/modules.yaml`'s `M1` block: `completion_signal`, `gate_cols`, `gate_pass_values`, `gate_labels`, `daily_target_per_enum`, `replacement_status_col`, `replacement_primary_values`, `replacement_rank_col`, `replacement_group_col`. (`last_date`, `treatment_control_col`, `geo_group_col`, `geo_group_opted_in`, `map_focus`, `group_label`, `important_vars`, `missingness_extra_vars`, and `var_labels` are confirmed later, in A2's module-config windows — see below.) `entity_display`/`enumerator_display`/`group_display` (de-identification-by-default: entity ID-only, enumerator/group name-if-available — see A1 step 7c) are set to their fixed defaults by `profile_roles()` on every run, never guessed or confirmed in any window — edited directly in the yaml only on an explicit user request.

## Nested / skip-logic questions

Parent→child items (e.g. "Are you in school?" → if yes "Which grade?") must be evaluated with SurveyCTO `relevant` / skip logic when a form is available. **Do not flag child blanks as missing when the parent path makes them expected.** Without a form, note weaker nested handling; do not invent relevance.

## Module confirmation (three windows + Wrap-up, A2)

No separate "pace" question anymore (there's no more Accept-all vs. Review split) — every module setting is stated as a guess, one atomic fact per tab, packed into as few windows as possible:

**"Keys & Hours"**, up to 4 tabs: Duplicate key (M2, restated). Form version + mapping (M3, only if 2+ versions detected). Duration column (M4) — its 3 SD threshold is a fully silent fixed default, never mentioned in any tab. Work hours (M5) — real partial-accept options (both / work-hours only / weekend only), not generic Other.

**"Dates, Variables & GPS"**, up to 4 tabs: Last date of data collection (states the Last Day tab dependency; a real "include more days" option, not just Other). Variables — the full unified important-variables shortlist, spelled out by name directly in the tab's text (no separate numbered chat post anymore, the tab text has no length cap). Sentinel codes (M7's `guess_sentinel_codes()` guess). GPS distance threshold (M8, default 300m) — **skipped when M8 is already resolved off** (Instructions or pre-filled `modules.yaml`). M6's fixed 3 SD threshold, M9's fixed 90% threshold, and M7's three missingness thresholds (50% variable-issue / 90% enumerator-pool / 50% enumerator-personal) are all fully silent fixed defaults now — not mentioned in any tab at all.

**"Media, Map & Grouping"**, up to 4 tabs: Media-indicating columns (M11, restated from A1). Map focus default — **skipped together with GPS threshold** (the map only renders when M8 is on). An opt-in geographic-grouping ask (M1, only shown when a Treatment/Control column exists; default declined; real Yes/No options). Group Label (`derive_group_label()`, e.g. "School" for `school_id` — what `roles$group` is called throughout the report/tracking sheet; distinct from the Treatment/Control-vs-geography grouping question above).

**"Wrap-up"**, up to 4 tabs, closes out A2/A3/A4-prep together: Consent mapping (M12), its own tab, never bundled with anything else. Extra checks (M10), mandatory every run. Structure — states the real `hfc/config/modules.yaml` path here (first mention), 3 options: continue / "I edited the specifications" (re-read the file) / change the plan. Excel columns — the `issue_tracking.xlsx` schema, keep/modify.

**Mandatory, every run, cannot be skipped or silently auto-answered:** the Wrap-up window's Extra checks tab always asks **Extra checks?** — `No additional checks` (recommended) (Other automatic for a custom check). If Other, design a named check under `hfc/code/checks/<name>.R`, confirm the name/file, register under M10/`custom`, and write a ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (`custom.<name>.description`) so the HTML report can show it (see "Report display labels & descriptions" below).

## M1 — Completion

**Default: ON.** Redefined from "did this row finish" to "were all planned surveys conducted." Signal type comes from the Completion Signals window (`roles$completion_primary_signal`) — the report's Completion section states which one applies for this project (`module_desc.R`'s `m1_desc()`).

- **gating (preferred)** — one or more real screening/eligibility questions read from the instrument (`modules$M1$gate_cols`, in form order, each with a confirmed `gate_pass_values` entry). A respondent is complete only if they pass every gate; failing any one means the rest of the survey was never reached. Filters M2–M13 to the completed subset, same as `status` did before. Replaces the old status-column-name-pattern heuristic entirely — reading the actual instrument is more reliable than guessing from a column name.
- **roster** — a target/planned-sample file compared against the actual survey data. Only relevant when no credible gate was found. Reports "planned vs. actually surveyed"; every surveyed row still counts as completed for M2–M13's purposes. **Completion-by-strata uses the roster's own target counts as the denominator**: `by_group`'s `n` is the roster's planned/target count for that stratum (village, farmer group, Treatment Arm, whichever `modules$M1$group_vars` names), `n_complete` is how many of those targeted individuals were actually surveyed — i.e. the real "percent of target sample surveyed so far," not a percentage of submitted rows. Needs the strata column to exist in the roster by the same name as in the survey data; when it doesn't (e.g. survey data's `village` vs. the roster's `village_name`), `roles$completion_roster_group_map` (agent-resolved at setup, SKILL.md A1 step 9b) bridges the name — without it, that stratum silently drops out of `by_group` instead of computing anything.
- **primary_secondary** — a column marking each surveyed row Primary or Secondary sample, when there's no separate roster. Only relevant when no credible gate was found. Reports the primary/secondary composition instead of a target-vs-actual rate; every row still counts as completed.
- **none detected** — falls back to the original row-missingness heuristic (`row_missing_ratio() <= 0.1`), unchanged from before this redesign.
- **status** (legacy) — `check_m1()` still recognizes an explicit per-row outcome column for a config saved before this change; never proposed as a fresh guess anymore.

**Reasons for non-completion (gating only):** for each incomplete respondent, the reason is the *first failed gate* in confirmed order — later gates were never reached, so they're not evaluated. The reason label decodes the failing value's own value labels when the gate column is labelled (`decode_labelled_chr()`), else falls back to the gate's own question label (`modules$M1$gate_labels`). Rendered as `stats$by_reason` (Reason | Count), same `render_stats_block()` path as M1's other stats tables.

**Day-by-day enumerator productivity:** a *separate*, opt-in check against a user-stated daily target (`modules$M1$daily_target_per_enum` — never a median). For each enumerator, any day whose submission count falls short of the target is flagged; one aggregate finding per enumerator lists every under-target day (`low_completion_enum_day` category). Unset/declined `daily_target_per_enum` skips this check entirely.

**Replacement-sample analysis:** a *third*, independent add-on — whenever the roster/`target_ds` has confirmed `replacement_status_col`/`replacement_rank_col`/`replacement_group_col` columns, regardless of which `completion_signal` is actually driving completion above. Reads the roster directly (`target_ds`, loaded whenever a roster file exists — no longer gated on `completion_signal == "roster"`): for each roster group, compares how many Primary-tagged individuals were targeted against how many completed themselves vs. were filled by a Replacement-tagged individual, rendered as `stats$by_replacement` (Group | Primary targeted | Primary completed | Replaced | % Replaced). A group's replacement queue is shared across all its primaries (not one chain per primary) and ranked by `replacement_rank_col`; if the highest-ranked *completed* replacement is K, every rank below K must have a row in the survey data at all (attempted, whether or not it completed) — a rank with no row at all is a genuine gap, one aggregate finding per violating group (`replacement_sequence_gap` category, no Entity ID, naming exactly which rank(s) were skipped).

**Full daily roster (`stats$by_enum_latest_day`):** a fourth, always-present add-on — needs only `roles$enum` + `roles$start`, independent of `daily_target_per_enum` being configured (same posture as M4's `stats$by_day_times`). One row per enumerator who has ever appeared anywhere in the data, with their `Attempted`/`Completed` tally for the single most recent day present in the dataset, and `Last Active Day` — the most recent day (up to and including that latest day) they have any row at all, most informative for anyone with `Attempted = 0`. Unlike the day-by-day productivity check above (which only flags enumerators falling short of a confirmed target), this table always covers every enumerator, including ones with zero submissions on the latest day — the raw material for the Summary narrative's full enumerator-roster lead sentence (`assets/summary_message_example.md`, `SKILL.md` A4 step 6).

Reports: overall, **by group** (one combined table covering both breakdowns when both apply — defaults to a detected Treatment/Control column — `modules$M1$group_vars`; only falls back to geography when no Treatment/Control column exists, or adds it alongside T/C only if the user opted in, each row tagged with which breakdown it belongs to — the table's own `group` column is labeled dynamically from `roles$group_label`, never left as the generic "Group"), by enumerator (sorted lowest-to-highest completion), by date, by reason (gating only) — counts **and** percentages, no charts by default. A separate, still-valid finding independently flags specific groups (keyed on `roles$group`, labeled with `roles$group_label` — e.g. "Village has fewer completed submissions than…" — falling back to the generic "Group" only when no label was guessed/confirmed at all) whose completion count falls below `modules$M1$pct_median` (default 50%) of the target — the median completion count across all groups. One aggregate-level finding per flagged group (no Entity ID, via `mk_aggregate_finding()`), never broken down by respondent.

## M2 — Duplicates

**Default: ON** — duplicate submission IDs / keys (DIME ieduplicates spirit); composite-ID aware.

Confirmed in the Keys & Hours window's Duplicate key tab: auto-resolved in A1 (Entity ID alone if unique, else + detected round/wave-like columns) and only restated here for visibility, correctable via this tab's free-text box.

## M3 — Form Version

**Default: ON** — best-effort, always propose-then-confirm, never trust silently.

Confirmed in the Keys & Hours window's Form version tab: the version column (or, if none exists, a best-guess of N version windows from column-availability changes) + a date-range↔version mapping, only shown when a form with more than one detected version exists.

Reports: version × date-range × n table. Optional finding when a real version column exists: recorded version doesn't match the expected version for its date.

## M4 — Survey Duration

**Default: ON** — descriptive stats (overall / by section / by enumerator / by day-times) plus outlier flagging, decoupled from M5's early-start logic. Duration is always converted to and reported in **minutes** (the source column is SurveyCTO's native seconds export) — including in M13's Summary Statistics table, when the duration column happens to be in that module's variable list (`check_m13()` applies the same conversion, not just `check_m4()`).

Confirmed in the Keys & Hours window's Duration column tab: the guessed column, stated as a guess. The SD rule (fixed at 3) is never mentioned in any tab at all — a fully silent default (same treatment M6/M9/M7's thresholds now also get).

**Daily start/end time table (`stats$by_day_times`) — always present, never confirmed in any tab.** Day | Earliest Start | Latest Start | Earliest End | Latest End, local time, `HH:MM am/pm` format (e.g. `08:00 am`, `09:43 pm`). Needs only `roles$start` (works even with no duration column configured at all; `roles$end` is optional — the End columns are blank without it). Timezone-aware the same way M5 is (`resolve_row_timezone()`), via `local_date_hm()` (`scripts/lib/run_checks.R`) — a per-timezone-group extraction of local date/hour/minute, deliberately never combining `force_tz()`'d POSIXct values into one vector before formatting (a POSIXct vector has exactly one tzone for its whole length; `as.Date.POSIXct()`'s default `tz=""` silently uses the system timezone instead of the value's own attached one — a real, confirmed trap this sidesteps).

## M5 — Irregular Timing

**Default: ON** — timezone-aware (uses the country/timezone confirmed in A1's Entity & Country window); absorbs the old "early start" concept.

Confirmed in the Keys & Hours window's Work hours tab, alongside M4: work-hours window (default 7pm–7am flags evenings/nights + weekends), stated as one guess with real partial-accept options (flag both / work-hours only / weekend only) rather than a single accept-or-Other choice. Last date of data collection is a separate fact, confirmed in the Dates, Variables & GPS window instead (it doesn't belong to M5 specifically — it drives the report-wide Last Day tab).

## M6 — Numeric Outliers

**Default: ON** — up to 10 continuous vars (exclude IDs/codes), two-sided SD rule — **fixed at 3, not configurable via the interactive flow**.

Confirmed in the Dates, Variables & GPS window's Variables tab: uses the unified important-variables shortlist directly (no separate module-level variable ask). The SD threshold is a fully silent fixed default now — not mentioned in any tab (same treatment as M9's straightlining threshold and M4's SD rule).

## M7 — Missingness

**Default: ON** — by the unified important-variables shortlist (≤10) PLUS ~20 more agent-picked variables specific to missingness reporting (any type, not just numeric), and by enumerator.

Confirmed in the Dates, Variables & GPS window's Sentinel codes tab, alongside the Variables tab: `guess_sentinel_codes()` speculatively scans the shortlisted variables' value distributions for likely sentinel/missing codes (99, -99, -9999, …). Its own tab, not folded into Variables — one fact per tab.

The ~20 extra missingness-specific variables are agent judgment only, made during the same setup pass and written directly to `hfc/config/role_map.yaml`'s `missingness_extra_vars` — **no `AskUserQuestion` confirmation**; an RA who disagrees corrects it only by editing the yaml directly, not in chat.

**Clean variable labels (`role_map.yaml`'s `var_labels`), same posture, cross-module:** once every column that can surface in a finding is known (the unified shortlist + M7's extras + M11's media columns + M12's assent/consent/audio columns + M2/M3's key/version columns — SKILL.md A2 step 10), the agent writes a short human-readable label for each — e.g. `price_rice_kg` → "Rice price (kg)", from the column name plus its instrument question label — never the bare column name, never the verbatim question text. `utils.R`'s `var_label(colname, roles)` resolves this everywhere a variable name feeds human-facing text: M6's outlier sentence, M7's variable/enumerator stats tables and missingness sentence, M9's straightlining sentence, M11/M12's column-empty sentences, M13's Variable column. It does **not** touch `mk_findings()`'s `variable_name` (→ `issue_tracking.xlsx`'s "Variable (DIME use)" column, `references/issue_tracking_schema.md`) — that stays the raw column name by design, for programmatic reuse. Falls back to the raw column name wherever unset (e.g. a rebuild against an older config).

**Skip-logic-dependent variables are excluded from selection by default (F38):** a candidate with a non-blank `relevant` in the parsed form is a child of some other question — it never gets proposed for either the unified shortlist or the extra ~20, even though `filter_expected_skips()` already keeps its row-level denominator correct. Only an explicit user request to include that specific variable overrides this.

**Three fixed thresholds, stated not asked** (`modules$M7$var_issue_threshold`/`enum_pool_threshold`/`enum_pct_threshold`, defaults 0.5/0.9/0.5): a variable only appears in the by-variable stats table at all if its overall (population) missingness exceeds 50% — "only report the issues." Among those, a variable is only eligible for enumerator-level flagging if its overall missingness is ≥90% — a narrower, worse-off subset. Within that pool, an enumerator is flagged if their own personal missingness on that variable is ≥50%. Skip-logic-expected blanks (via `filter_expected_skips()`/`row_is_relevant()`, the same `hfc_form_map` mechanism M12 uses) are excluded from both the numerator and denominator at every stage, so a legitimately-skipped question never inflates missingness.

Reports: missingness % by variable (issues only, per the 50% gate) and by enumerator×variable (same gate). One aggregate-level finding **per flagged enumerator** (not per enumerator×variable) — every flagged variable listed in the issue text, every personal missingness % joined with " & " in Value — via `mk_aggregate_finding()`. No Entity ID, no per-submission rows.

## M8 — GPS

**Default: ON if coordinates found, else Off.**

Confirmed in the Dates, Variables & GPS window's GPS threshold tab: the coordinate pair + distance threshold (default 300m), stated as a guess.

Map focus for the HTML report (Country / City / World, default Country) is a separate fact, confirmed in the Media, Map & Grouping window's Map focus tab instead — it's a report-display setting, not part of the GPS check itself. On the map, all points are shown; points flagged by M8 render in red, others in the default color.

## M9 — Straightlining

**Default: ON if ordinal-like candidates are detected, else Off.**

Ordinal variables: intersects the confirmed unified important-variables list with the auto-detected ≤7-category ordinal pool; falls back to the full auto-detected pool if that intersection is empty (never silently turns M9 off over a variable-selection choice).

**Threshold is a fixed default, not a choice:** both the enumerator threshold (an enumerator gave the identical single answer on one question in ≥ this share of their own surveys) and the survey threshold (a submission where ≥ this share of the confirmed ordinal variables share one identical value) default to **90%**. A fully silent fixed default now — not mentioned in any tab at all, same treatment as M4/M6/M7's thresholds. Still hand-editable in `modules.yaml` directly if a project genuinely needs a different value.

The enumerator-level check produces one aggregate-level finding per flagged enumerator×variable (no Entity ID, via `mk_aggregate_finding()`) — genuinely different granularity from the survey-level check's per-submission findings, so the two render as separate tables in the HTML report even though both are "M9".

## M10 — Survey-specific

**Default: None.** M10 has no built-in checks — every M10 finding comes from a
custom check the agent writes for this survey's specific content, described
by the user in the Wrap-up window's Extra checks tab.

Custom user-described checks are registered under M10/`custom` and live as
`hfc/code/checks/<name>.R`, with an exported `run_<name>(ds, roles)` — see
`assets/check_templates/custom_check_example.R` for the convention.

## M11 — Media files (audio, pictures, and qualitative text)

**Default: ON if media-indicating columns detected** (audio/image filename columns via `.m4a`/`.mp3`/… or `.jpg`/`.png`/… extensions, or agent-identified qualitative open-text columns).

**Redesigned to a single check, no on-disk file access at all:** flags a media-indicating column only if it is **completely empty across every surveyed row** — a strong signal of a form/coding problem (the field isn't showing up in the enumerator's app, or the question is misconfigured), not a per-row file-hygiene issue. This deliberately drops the old per-row checks (empty cell, file missing on disk, tiny file, bad extension, duplicate basename/hash, duration, flag↔file mismatch) — none of those survive.

Confirmed in the Media, Map & Grouping window's Media columns tab: the media-indicating columns (audio/image filename columns + any qualitative text columns), detected during A1's role profiling and stated here for the first time.

`config.json`'s Media Folder Directory is not read by this check (kept in config for potential future use).

## M12 — Consent / assent / audio flags

**Default: ON if flag columns found.**

Yes/no (or 0/1) **flags only** — not filename columns (those are M11). Respect nested skip-logic for assent/consent follow-ups.

**Confirmed in its own tab, the Wrap-up window's Consent mapping tab, never bundled with anything else** — assent and consent are different concepts (assent = the child/minor's own agreement; consent = the parent/guardian's, or an adult respondent's own) and mixing them up is a real risk worth isolating. States which column maps to assent, consent, and audio-consent, explicitly naming each: *"I found: `assent` → child's own agreement, `consent` → guardian consent, `audio_consent_flag` → recorded-audio consent. Tell me if any of these are swapped."*

## M13 — Summary Statistics

**Default: ON** — purely descriptive, zero findings rows.

Uses the confirmed unified important-variables list directly (no separate module-level variable ask).

Two kinds of tables, both Variable | Mean | SD | Min | Max | NA | Obs, no panel/lettered grouping: an **Overall** table (always first, all rows), plus one additional table **per enumerator** (using the enumerator's display name when available) — not a replacement for Overall, both always render together.

## After confirms

Map confirmed (guessed-then-corrected) values → `hfc/config/modules.yaml` + `hfc/config/role_map.yaml`, then run the builder. No typed mega-reply required.

## Report display labels & descriptions (authoritative)

Source of truth for how modules appear in `hfc/outputs/<MMDD>_HFCs.html` (mirrored as `MODULE_META` in `scripts/lib/build_outputs.R` — keep both in sync). Tab/heading text is the label; the module code still appears alongside it, smaller, since it's used internally (e.g. `issues.csv`). Descriptions are ≤3 plain-English sentences, no raw column names.

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
