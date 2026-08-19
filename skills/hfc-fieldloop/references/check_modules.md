# Check modules (M1–M14) — specs

Confirm modules via the guess-first-then-correct **AskUserQuestion** windows described in `interaction.md` and `SKILL.md`'s A1/A2 — the agent states its own best guess in plain language, the user gets one free-text way to correct it. Do not ask the user to type `M1=Y M2=…`. Do not ask 100 column questions.

Module order below matches `assets/report_sections.json`'s canonical section order — every project follows this order for whichever modules it actually turns on; a module numbered but off simply doesn't appear.

## Required setup (Windows "Setup" + "Completion Signal", A1 — only 4 gates in the whole pipeline, before the final Review & Approve)

Full flow, guess wording, and the exact `role_map.yaml`/`modules.yaml` fields persisted: `SKILL.md`'s A1 (not re-narrated here — a second copy would just drift out of sync). Signal summary only, for quick reference:

- **Setup** (Gates 2-3): data/form found, plus an open Instructions catch-all — now also the place to name any specific checks wanted, matched to a standard module or authored as an M9 custom check silently. Applied before role profiling, so it can skip inference rather than just skip a tab.
- **Completion Signal** (Gate 4): Gating (preferred — real screening/eligibility questions read from the instrument, `gate_fanout_counts()` as a supporting signal only) > roster > primary/secondary, whichever's credible — one tab, fires whenever any of the three was found. Daily target and Replacement sample are decided silently alongside it.
- Everything else — Entity, Country, duplicate key, media columns, and all of A2's module settings — is decided **silently**: same guess logic, written directly to config, no tab. Replayable via "Walk me through all modules" at A4's Review & Approve gate — see "Deep Review" in `references/interaction.md` for the exact tab wording.

**Never re-ask what's already resolved** — even under a Deep Review replay, every tab checks the Instructions answer and any hand-edited yaml first.

## Nested / skip-logic questions

Parent→child items (e.g. "Are you in school?" → if yes "Which grade?") must be evaluated with SurveyCTO `relevant` / skip logic when a form is available. **Do not flag child blanks as missing when the parent path makes them expected.** Without a form, note weaker nested handling; do not invent relevance.

## Module configuration (A2, fully silent by default)

Every module setting (duplicate key, form version, duration column, work hours, last date, variables/sentinel codes, GPS coordinates, media columns, map focus, geography opt-in, group label, M12 Balance Tables groupings, consent mapping, Excel columns) is decided silently — same guess logic as always, written directly to `modules.yaml`/`role_map.yaml`, no confirmation. Full tab wording (used only for a Deep Review replay) lives in `references/interaction.md`.

An M9 custom check tagging its rows `category = "field_request"` renders in M9's own Info-labeled table; every other custom-check category renders in the adjacent "Other" section (standard Issue-labeled).

## M1 — Completion

**Default: ON.** Redefined from "did this row finish" to "were all planned surveys conducted." Signal type comes from the Completion Signals window (`roles$completion_primary_signal`) — the report's Completion section states which one applies for this project (`module_desc.R`'s `m1_desc()`).

- **gating (preferred)** — one or more real screening/eligibility questions read from the instrument (`modules$M1$gate_cols`, in form order, each with a confirmed `gate_pass_values` entry). A respondent is complete only if they pass every gate; failing any one means the rest of the survey was never reached. Filters M2–M14 to the completed subset, same as `status` did before. Replaces the old status-column-name-pattern heuristic entirely — reading the actual instrument is more reliable than guessing from a column name. `gate_min_date` (per-gate, optional) exempts submissions dated before a gate existed on the form from failing it. `governing_gate` (optional, at most one) lets a later gate's pass override an earlier gate's still-failed/blank status for that row.
- **roster** — a target/planned-sample file compared against the actual survey data. Only relevant when no credible gate was found. Reports "planned vs. actually surveyed"; every surveyed row still counts as completed for M2–M14's purposes. **Completion-by-strata uses the roster's own target counts as the denominator, and is called Progress, not Completion**: the BY GROUP table's `n` is the roster's planned/target count for that stratum (village, health facility, Treatment Arm, whichever `modules$M1$group_vars` names), `n_complete` is how many of those targeted individuals were actually surveyed, and the ratio column reads **"Progress"** — deliberately distinct from every other completion table on this page (OVERALL/BY ENUMERATOR/BY DATE, which stay "Completion" — Completed/Submitted). A group can be under 100% Progress even once every submission in it is complete, if replacements haven't yet filled every primary slot. Needs the strata column to exist in the roster by the same name as in the survey data; when it doesn't (e.g. survey data's `village` vs. the roster's `village_name`), `roles$completion_roster_group_map` (agent-resolved at setup, SKILL.md A1) bridges the name — without it, that stratum silently drops out of `by_group` instead of computing anything.
- **primary_secondary** — a column marking each surveyed row Primary or Secondary sample, when there's no separate roster. Only relevant when no credible gate was found. Reports the primary/secondary composition instead of a target-vs-actual rate; every row still counts as completed.
- **none detected** — falls back to the original row-missingness heuristic (`row_missing_ratio() <= 0.1`), unchanged from before this redesign.
- **status** (legacy) — `check_m1()` still recognizes an explicit per-row outcome column for a config saved before this change; never proposed as a fresh guess anymore.

**Reasons for non-completion (gating only):** for each incomplete respondent, the reason is the *first failed gate* in confirmed order — later gates were never reached, so they're not evaluated (a row exempted by `gate_min_date` never counts as having failed that gate). The reason label decodes the failing value's own value labels when the gate column is labelled (`decode_labelled_chr()`), else falls back to the gate's own question label (`modules$M1$gate_labels`). Rendered as `stats$by_reason` (Reason | Count), same `render_stats_block()` path as M1's other stats tables.

**Day-by-day enumerator productivity:** a *separate*, opt-in check against a user-stated daily target (`modules$M1$daily_target_per_enum` — never a median). For each enumerator, any day whose submission count falls short of the target is flagged; one aggregate finding per enumerator lists every under-target day (`low_completion_enum_day` category). Unset/declined `daily_target_per_enum` skips this check entirely.

**Replacement-sample analysis:** a *third*, independent add-on — whenever the roster/`target_ds` has confirmed `replacement_status_col`/`replacement_rank_col`/`replacement_group_col` columns, regardless of which `completion_signal` is actually driving completion above. Shared with M12 Balance Tables' own Replacements table via `compute_replacement_roster_summary()` (`scripts/lib/run_checks.R`) — M1 and M12 never join the roster two different ways. For each roster group, compares how many Primary-tagged individuals were targeted against how many completed themselves vs. were filled by a Replacement-tagged individual, rendered as `stats$by_replacement` (Group | Primary targeted | Primary completed | Replaced | % Replaced — `% Replaced = Replaced / Primary targeted`). A group's replacement queue is shared across all its primaries (not one chain per primary) and ranked by `replacement_rank_col`; if the highest-ranked *completed* replacement is K, every rank below K must have a row in the survey data at all (attempted, whether or not it completed) — a rank with no row at all is a genuine gap, one aggregate finding per violating group (`replacement_sequence_gap` category, no Entity ID, naming exactly which rank(s) were skipped).

**No "by enumerator, latest day" stats table** — v1 had one (`stats$by_enum_latest_day`); removed in v2 to match `report_sections.json`'s Completion Notes ("does not include a 'by enumerator, latest day' table"). The equivalent figures (each enumerator's submissions/completions for today) are still needed for the Summary narrative checklist (see `SKILL.md`'s Summary-drafting step) — the drafting agent computes them fresh from the completed dataset (or `hfc/outputs/issues.csv`) at drafting time, not from a dedicated pre-built stats table.

Reports: overall, **by group** (one combined table covering both breakdowns when both apply — defaults to a detected Treatment/Control column — `modules$M1$group_vars`; only falls back to geography when no Treatment/Control column exists, or adds it alongside T/C only if the user opted in, each row tagged with which breakdown it belongs to — the table's own `group` column is labeled dynamically from `roles$group_label`, never left as the generic "Group"), by enumerator (sorted lowest-to-highest completion), by date, by reason (gating only) — counts **and** percentages, no charts by default. A separate, still-valid finding independently flags specific groups (keyed on `roles$group`, labeled with `roles$group_label` — e.g. "Village has fewer completed submissions than…" — falling back to the generic "Group" only when no label was guessed/confirmed at all) whose completion count falls below `modules$M1$pct_median` (default 50%) of the target — the median completion count across all groups. One aggregate-level finding per flagged group (no Entity ID, via `mk_aggregate_finding()`), never broken down by respondent.

## M2 — Duplicates

**Default: ON** — duplicate submission IDs / keys (DIME ieduplicates spirit); composite-ID aware.

Confirmed in the Keys & Hours window's Duplicate key tab: auto-resolved in A1 (Entity ID alone if unique, else + detected round/wave-like columns) and only restated here for visibility, correctable via this tab's free-text box.

## M3 — Form Version

**Default: ON** — best-effort, always propose-then-confirm, never trust silently.

Confirmed in the Keys & Hours window's Form version tab: the version column (or, if none exists, a best-guess of N version windows from column-availability changes) + a date-range↔version mapping, only shown when a form with more than one detected version exists. `scripts/lib/validate_config.R` checks the confirmed windows are date-contiguous — a gap between two windows silently stopped validating for those dates in v1; now flagged as a warning at build time instead.

Reports: version × date-range × n table. Optional finding when a real version column exists: recorded version doesn't match the expected version for its date.

## M4 — Survey Duration

**Default: ON** — descriptive stats (overall / by section / by enumerator / by day-times) plus outlier flagging, decoupled from M5's early-start logic. Duration is always converted to and reported in **minutes** (the source column is SurveyCTO's native seconds export) — including in M11's Summary Statistics table, when the duration column happens to be in that module's variable list (`check_m11()` applies the same conversion, not just `check_m4()`).

Confirmed in the Keys & Hours window's Duration column tab: the guessed column, stated as a guess. The SD rule (fixed at 3) is never mentioned in any tab at all — a fully silent default (same treatment M6/M8/M7's thresholds now also get).

**Daily start/end time table (`stats$by_day_times`) — always present, never confirmed in any tab.** Day | Earliest Start | Latest Start | Earliest End | Latest End, local time, `HH:MM am/pm` format (e.g. `08:00 am`, `09:43 pm`). Needs only `roles$start` (works even with no duration column configured at all; `roles$end` is optional — the End columns are blank without it). Timezone-aware the same way M5 is (`resolve_row_timezone()`), via `local_date_hm()` (`scripts/lib/run_checks.R`) — a per-timezone-group extraction of local date/hour/minute, deliberately never combining `force_tz()`'d POSIXct values into one vector before formatting (a POSIXct vector has exactly one tzone for its whole length; `as.Date.POSIXct()`'s default `tz=""` silently uses the system timezone instead of the value's own attached one — a real, confirmed trap this sidesteps).

## M5 — Irregular Timing

**Default: ON** — timezone-aware (uses the country/timezone confirmed in A1's Entity & Country window); absorbs the old "early start" concept.

Confirmed in the Keys & Hours window's Work hours tab, alongside M4: work-hours window (default 7pm–7am flags evenings/nights + weekends), stated as one guess with real partial-accept options (flag both / work-hours only / weekend only) rather than a single accept-or-Other choice. Last date of data collection is a separate fact, confirmed in the Dates, Variables & GPS window instead (it doesn't belong to M5 specifically — it drives the report-wide Last Day tab).

## M6 — Numeric Outliers

**Default: ON** — up to 10 continuous vars (exclude IDs/codes), two-sided SD rule — **fixed at 3, silent by default**.

Confirmed in the Dates, Variables & GPS window's Variables tab: uses the unified important-variables shortlist directly (no separate module-level variable ask). `modules$M6$outlier_mode` (`"sd"` default, or `"fixed"`) picks between the relative SD rule and a fixed absolute range per variable (`fixed_thresholds[[var]] = list(low=, high=)`, one-sided when either bound is NA) — for a survey where a relative rule doesn't make sense (e.g. a known plausible age/score range independent of what this sample happens to contain). Only proposed/confirmed when the user's own Instructions name specific numeric bounds; otherwise stays silently on `"sd"`.

## M7 — Missingness

**Default: ON, descriptive only — never produces findings, on either the question or the enumerator level** (`report_sections.json`'s Missingness Notes). By the unified important-variables shortlist (≤10) PLUS ~20 more agent-picked variables specific to missingness reporting (any type, not just numeric).

Confirmed in the Dates, Variables & GPS window's Sentinel codes tab, alongside the Variables tab: the agent scans the shortlisted variables' value distributions for likely sentinel/missing codes (99, -99, -9999, …), cross-checked against the form's choice labels when available. Its own tab, not folded into Variables — one fact per tab.

The ~20 extra missingness-specific variables are agent judgment only, made during the same setup pass and written directly to `hfc/config/role_map.yaml`'s `missingness_extra_vars` — **no `AskUserQuestion` confirmation**; an RA who disagrees corrects it only by editing the yaml directly, not in chat.

**Clean variable labels (`role_map.yaml`'s `var_labels`), same posture, cross-module:** once every column that can surface in a finding is known (the unified shortlist + M7's extras + M13's media columns + M14's assent/consent/audio columns + M2/M3's key/version columns — SKILL.md A2 step 10), the agent writes a short human-readable label for each — e.g. `price_var_kg` → "Unit price (kg)", from the column name plus its instrument question label — never the bare column name, never the verbatim question text. `utils.R`'s `var_label(colname, roles)` resolves this everywhere a variable name feeds human-facing text: M6's outlier sentence, M7's variable/enumerator stats tables, M8's straightlining sentence, M13/M14's column-empty sentences, M11's Variable column. It does **not** touch `mk_findings()`'s `variable_name` (→ `issue_tracking.xlsx`'s "Variable (DIME use)" column, `references/issue_tracking_schema.md`) — that stays the raw column name by design, for programmatic reuse. Falls back to the raw column name wherever unset (e.g. a rebuild against an older config).

**Skip-logic-dependent variables are excluded from selection by default (F38):** a candidate with a non-blank `relevant` in the parsed form is a child of some other question — it never gets proposed for either the unified shortlist or the extra ~20, even though `filter_expected_skips()` already keeps its row-level denominator correct. Only an explicit user request to include that specific variable overrides this.

**Descriptive tables, no default flagging:** reports missingness % by variable (`stats$by_variable`: Variable | % Missing | N Missing | Obs, every configured variable, whether or not it crosses any threshold) and by enumerator×variable (`stats$by_enumerator`). Skip-logic-expected blanks (via `filter_expected_skips()`/`row_is_relevant()`, the same `hfc_form_map` mechanism M14 uses) are excluded from both the numerator and denominator at every stage, so a legitimately-skipped question never inflates missingness. Non-substantive sentinel codes count as missing, same shared list used project-wide.

**Advanced, opt-in enumerator-level flagging** (`modules$M7$advanced_enum_flag$on`, default `FALSE`): if a project specifically wants it, the same three-gate logic from v1 is still available — a variable only becomes eligible for enumerator-level flagging once its own population missingness clears `enum_pool_threshold` (default 0.9), and within that pool an enumerator is flagged if their own missingness clears `enum_pct_threshold` (default 0.5). One aggregate-level finding **per flagged enumerator** (not per enumerator×variable) — every flagged variable listed in the issue text, every personal missingness % joined with " & " in Value — via `mk_aggregate_finding()`. Not proposed by default in any tab; only surfaced if the project's Instructions specifically ask for missingness to be flagged as an issue, not just reported.

## M8 — Straightlining

**Default: ON if ordinal-like candidates are detected, else Off.** Reports enumerators who gave the same answer on a question in most of their interviews on a single day, and individual submissions where most ordinal/Likert-style questions share one identical value.

Ordinal variables: intersects the confirmed unified important-variables list with the auto-detected ≤7-category ordinal pool; falls back to the full auto-detected pool if that intersection is empty (never silently turns M8 off over a variable-selection choice).

**Thresholds are fixed defaults, not a choice, and the two checks are scoped differently:**
- **Enumerator-level** (`enum_threshold_pct`, default **100%**): evaluated **per enumerator, per day** — an enumerator gave the identical single answer on one question in every one of their surveys that day. Only evaluated on a day with **at least 3** completed surveys for that enumerator (`check_m8()`'s `min_n_per_enum_day`); a day with 2 or fewer is skipped as too few data points to mean anything.
- **Survey-level** (`survey_threshold_pct`, default **90%**, unchanged): a single submission where ≥ this share of the confirmed ordinal variables share one identical value — unrelated to the enumerator-level check, not day-scoped (it's already at the single-submission granularity).

Both are fully silent fixed defaults — not mentioned in any tab at all, same treatment as M4/M6/M7's thresholds. Still hand-editable in `modules.yaml` directly if a project genuinely needs a different value. Non-substantive sentinel codes are excluded before computing the "same answer" share, same shared list used project-wide.

The enumerator-level check produces one finding per flagged (enumerator, day, variable-set) — a real date now (the day being flagged), but still no Entity ID (`mk_aggregate_finding()`, `unit_type = "enumerator"`) since it's not tied to one specific submission. Genuinely different granularity from the survey-level check's per-submission findings, so the two render as separate tables in the HTML report even though both are "M8".

## M9 — Field Request

**Default: none built-in.** M9 has no built-in checks — every M9 finding comes from a custom check the agent writes for this survey's specific content, described by the user in A1's Instructions tab (Setup window) and authored silently right after.

The field team's own daily reconciliation view — a status snapshot, not a problem to fix. A custom check whose rows are genuinely a field-request/reconciliation item tags them `category = "field_request"`; the render loop splits M9's findings by that tag: matching rows render in M9's own section with an **"Info"** column label (not "Issue") and a **"N entries"** heading (not "N issues found"); every other M9 category renders in the adjacent **"Other"** section instead, with the standard "Issue" label and "N issues found" heading. Respondent-ID sample status in a Field Request check is scoped to the primary sample only (replacements excluded from the target), and is cumulative as of the report, not a per-day snapshot.

Custom checks are registered under `modules$M9$custom` (character vector of names) and live as `hfc/code/checks/<name>.R`, with an exported `run_<name>(ds, roles)` — see `assets/check_templates/custom_check_example.R` for the convention. A custom check that needs the FULL, unfiltered dataset (not just the completed/surveyed subset every other module sees) opts in via `modules$M9$custom_full_data` (character vector of check names).

## M10 — GPS Map

**Default: ON if coordinates found, else Off.** Purely a visualization by default (`report_sections.json`: "no distance threshold, no flagged points, no findings table") — plots every submission with a valid coordinate on an interactive map (OpenStreetMap base layer, up to 2,000 points, randomly sampled if more, for browser performance; clicking a point pops up its Respondent ID), for visual review only.

Confirmed in the Dates, Variables & GPS window: the coordinate pair, when GPS data is detected. **The distance-outlier threshold is not asked in any standard tab anymore** — GPS Map never flags a point as an issue by default, matching every future project's real needs regardless of sector (not tuned to any one pilot).

Map focus for the HTML report (Country / City / World, default Country) is a separate fact, confirmed in the Media, Map & Grouping window's Map focus tab instead — it's a report-display setting, asked whenever coordinates exist, independent of the advanced flag below.

**Advanced, opt-in distance flagging** (`modules$M10$advanced_distance_flag$on`, default `FALSE`, `threshold_m` default 300): the v1 median-reference distance-outlier logic (flag a submission more than `threshold_m` from the median location of other submissions in the same `roles$group`) is still available and tested, but only runs if a project's own Instructions specifically ask for it. When on, flagged points render red on the map and also appear as a normal findings table beneath it, same conventions as every other module.

## M11 — Summary Statistics

**Default: ON** — purely descriptive, zero findings rows, ever.

Uses the confirmed unified important-variables list directly (no separate module-level variable ask).

Two kinds of tables, both Variable | Mean | SD | Min | Max | NA | Obs, no panel/lettered grouping: an **Overall** table (always first, all rows), plus one additional table **per enumerator** (using the enumerator's display name when available) — not a replacement for Overall, both always render together.

## M12 — Balance Tables

**Default: OFF — no auto-detection.** Standard RCT balance check: for each confirmed grouping, compares baseline covariates across group values, alongside a completed-vs-submitted reconciliation and a differential-completion regression. Descriptive only, never produces findings — this section describes the randomization and attrition pattern, it doesn't flag a data-quality problem. Only offered in the Media, Map & Grouping window when a Treatment/Control-like column exists and the project looks like a randomized/multi-arm design — most projects aren't, and should never see this tab at all.

`modules$M12$groupings` — a list, one entry per comparison the project wants (e.g. one for extension arm, a second for a data-incentive treatment): `group_col` (the arm/group column in the survey data), `group_label` (display label), `covariates` (character vector of columns to balance-check), `other_group_col` (optional — a second grouping included in the same regression as a control), `roster_group_col` (optional — the corresponding column name in the roster/`target_ds`, when it differs from `group_col`), `roster_value_map` (optional — remaps a roster-side raw group value to the survey data's own coding, e.g. roster `"1,2,3"` vs data `"Control,Treat1,Treat2"`; unmapped values pass through unchanged).

Rendered with the `gt` R package for a polished, publication-style look (real spanning column headers, a stacked Mean/SD cell) rather than the plain searchable-table look every other section on this page uses. Appears once per configured grouping, each as **four tables in a fixed order**, right before "All Issues":

1. **Completed interviews by \<group\>** — Submitted Surveys / Completed Interviews / Completion Rate (Completed ÷ Submitted), one column per group value plus a Total column. Shares `compute_completion_flag()` with M1 (`scripts/lib/run_checks.R`) — the two never compute completion two different ways.
2. **By \<group\>** — per-covariate Mean(SD)/N per group value among completed interviews only, plus a Welch ANOVA p-value (`stats::oneway.test`, reduces to a Welch two-sample t-test at exactly 2 groups). Bolded and colored red when below .05.
3. **Completion regression by \<group\>** — does group predict whether a submission was ever completed at all (not just covariate balance among completers) — the standard "differential attrition" check. Linear probability model of completion on the group (plus `other_group_col`, when configured, in the same joint model) with `roles$group` (this survey's own stratification/site unit) fixed effects, SEs clustered by `roles$group` — `sandwich`+`lmtest`, not `estimatr` (already-available dependencies, see `install.R`). One row per non-reference group level, difference expressed in percentage points relative to the reference level. A source note states the model spec, cluster count, sample size, and the joint test that no group differs from the reference.
4. **Replacements by \<group\>** — Non-Completed Primary / Replacements N / Replacement Success % (`Replacements N ÷ Non-Completed Primary` — deliberately a different denominator/formula from M1's own `% Replaced`, which divides by Primary Targeted instead). Shares the roster join with M1 via `compute_replacement_roster_summary()`.

## M13 — Media files (audio, pictures, and qualitative text)

**Default: ON if media-indicating columns detected** (audio/image filename columns via `.m4a`/`.mp3`/… or `.jpg`/`.png`/… extensions, or agent-identified qualitative open-text columns).

**A single check, no on-disk file access at all:** flags a media-indicating column only if it is **completely empty across every surveyed row** — a strong signal of a form/coding problem (the field isn't showing up in the enumerator's app, or the question is misconfigured), not a per-row file-hygiene issue. Deliberately no per-row checks (empty cell, file missing on disk, tiny file, bad extension, duplicate basename/hash, duration, flag↔file mismatch).

Confirmed in the Media, Map & Grouping window's Media columns tab: the media-indicating columns (audio/image filename columns + any qualitative text columns), detected during A1's role profiling and stated here for the first time.

`config.json`'s Media Folder Directory is not read by this check (kept in config for potential future use).

## M14 — Consent / assent / audio flags

**Default: ON if flag columns found.**

Yes/no (or 0/1) **flags only** — not filename columns (those are M13). Respect nested skip-logic for assent/consent follow-ups.

**Confirmed in its own tab, the Wrap-up window's Consent mapping tab, never bundled with anything else** — assent and consent are different concepts (assent = the child/minor's own agreement; consent = the parent/guardian's, or an adult respondent's own) and mixing them up is a real risk worth isolating. States which column maps to assent, consent, and audio-consent, explicitly naming each: *"I found: `assent` → child's own agreement, `consent` → guardian consent, `audio_consent_flag` → recorded-audio consent. Tell me if any of these are swapped."*

## After confirms

Map confirmed (guessed-then-corrected) values → `hfc/config/modules.yaml` + `hfc/config/role_map.yaml`, then run the builder. No typed mega-reply required. `scripts/lib/validate_config.R`'s `validate_modules_config()` runs automatically at the start of the build and fails fast with a readable, collected error list if anything's structurally broken (a configured column that doesn't exist in the data, an ungoverned/misconfigured gate, a version_map date gap, …) — rather than a module silently producing an empty table three steps later.

## Report display labels & descriptions (authoritative)

Source of truth for how modules appear in `hfc/outputs/<MMDD>_HFCs.html` (mirrored as `MODULE_META` in `scripts/lib/build_outputs.R` — keep both in sync). Tab/heading text is the label; the module code still appears alongside it, smaller, since it's used internally (e.g. `issues.csv`). Descriptions are ≤3 plain-English sentences, no raw column names.

| Code | Label | Description |
|---|---|---|
| M1 | Completion | Reports how many submissions are complete overall, and by group, enumerator, and date, so gaps in fieldwork show up early. By default, also flags any group whose completed-submission count falls below 50% of the target — the median completion count across all groups — one finding per flagged group, never broken down by respondent. |
| M2 | Duplicates | Flags submissions that share the same unique ID or survey key, which usually means the same interview was uploaded or entered more than once. |
| M3 | Form Version | Tracks which version of the survey instrument was in use on each date, and flags any submission whose recorded version doesn't match the expected window for its date. |
| M4 | Survey Duration | Reports how long interviews took, in minutes, overall and by enumerator, and flags individual interviews that were unusually long or short. |
| M5 | Irregular Timing | Flags interviews conducted at unusual times — weekends or outside normal working hours — using each submission's local time zone. |
| M6 | Numeric Outliers | Flags unusually high or low values on key numeric questions against fixed, literature/analyst-supplied thresholds. |
| M7 | Missingness | A reference table of missingness on key survey questions — descriptive only, never produces findings, on either the question or the enumerator level. |
| M8 | Straightlining | Flags enumerators who gave the same answer on a question in 100%+ of their interviews on a single day (min. 3 that day), and submissions where 90%+ of ordinal/Likert-style questions share one identical value. |
| M9 | Field Request | The field team and user's own daily reconciliation view — a custom, survey-specific check whose rows are a status snapshot, not a problem to fix. Any finding that isn't a Field Request reconciliation item renders in "Other" instead. |
| M10 | GPS Map | An interactive map plotting every submission's GPS location, for visual review — descriptive only, this section never flags an issue by default. |
| M11 | Summary Statistics | A simple reference table of mean, SD, min, max, and observation count for the survey's most important numeric variables. |
| M12 | Balance Tables | Standard RCT balance check: compares baseline covariates across treatment arms and other configured splits, alongside a completed-vs-submitted reconciliation and a differential-completion regression. Descriptive only, never produces findings. |
| M13 | Media Files | Flags a media-indicating column (audio, image, or qualitative-capture) that is completely empty across every surveyed row — usually a form/coding problem, not a per-row file issue. |
| M14 | Consent & Assent | Flags cases missing a required consent (guardian agreement) or assent (the child's own agreement) flag, which the survey should always capture before proceeding. |

Custom/M9 checks requested via A1's Instructions tab get their own description, authored at creation time and persisted to `hfc/config/module_notes.yaml`:

```yaml
custom:
  <name>:
    label: "Short human name"
    description: "≤3 sentences, plain English, no raw column names."
overrides:        # optional — replaces a default M1-M14 description above for this survey
  M6: "Custom text replacing the default M6 description."
```
