# Check modules (M1–M13) — option card specs

Confirm modules with **AskUserQuestion** cards (see `interaction.md`). **2–4 options per question**; Claude Code's free-text **Other** is automatic — do not add an explicit Other option. Do not ask the user to type `M1=Y M2=…`. Do not ask 100 column questions.

Recommended choices are listed first. Star in labels = recommended.

## Required fields (dedicated gate, before module pace)

Five fields are confirmed in sequence, **before any module cards** (see `interaction.md`'s Gate map) — not folded into M1–M13 review:

1. **Entity ID.** AskUserQuestion: single column vs. combine multiple columns (composite key, e.g. `household_id` + `member_id`) — this is the analysis-unit identifier (person/household/school/...), **not necessarily row-unique**.
   - Single: profile shortlists ≤3 candidates using names, labels, and uniqueness stats (`shortlist_entity_ids()`).
   - Composite: `multiSelect: true` over ≤4 candidates (`shortlist_composite_entity_ids()` — pools moderate-uniqueness + roster/member-like columns). After selection, report joint uniqueness inline in chat (not another gate).
2. **Entity Label.** AskUserQuestion: what to call the Entity ID in the HTML report (e.g. "Student ID", "Household ID") — "Entity ID" (generic, recommended) / Other (free text). Display-only: the xlsx/csv exports always keep the fixed generic "Entity ID" header regardless of this answer.
3. **Duplicate-check key.** Check whether Entity ID is already 100% unique per row in the raw data.
   - Already unique: auto-resolve to "Entity ID alone," state it inline in chat, **skip the AskUserQuestion** — don't interrupt the common case.
   - Repeats (e.g. a household surveyed across multiple rounds): AskUserQuestion — Entity ID alone (only if the repeats really are duplicates) / add detected round/wave-like column(s) (`detect_duplicate_key_candidates()`, `multiSelect: true`, ≤4 candidates) / Other. Do not skip when Entity ID repeats (F27) — this feeds M2's actual grouping key, so a household legitimately surveyed twice isn't flagged as a duplicate.
4. **Country(ies) + timezone.** AskUserQuestion: single vs. multiple countries.
   - Single: confirm one country → one global timezone (best-effort guess from any weak signal, e.g. project/folder name, is fine as one option — free-text Other is always available).
   - Multiple: shortlist a country-indicator column (`shortlist_country_columns()`), resolve each distinct value's timezone (`resolve_country_timezone_column()`), and **always show the resolved timezone back for confirmation/override** (F24) — never treat a lookup match as live without showing it. Unmatched countries fall back to asking for a raw IANA timezone string directly.
5. **Last date of data collection.** AskUserQuestion: use the detected max date from the data (recommended) vs. a different date (Other). Do not skip (F25) — this drives report-wide bold-highlighting and the Last Day tab.

Persist to `hfc/config/role_map.yaml`: `entity_id`, `entity_id_sep`, `entity_label`, `dup_key_extra`, `country_mode`, `country`/`country_col`/`country_timezone_map`, `timezone`, `last_date`. (`map_focus`, confirmed later at the build gate if GPS is on, also lives here — see A4 in `SKILL.md`.)

## Nested / skip-logic questions

Parent→child items (e.g. "Are you in school?" → if yes "Which grade?") must be evaluated with SurveyCTO `relevant` / skip logic when a form is available. **Do not flag child blanks as missing when the parent path makes them expected** (F22). Without a form, note weaker nested handling; do not invent relevance.

## Pace (ask first)

AskUserQuestion:

- Accept all recommended defaults (recommended)
- Review module-by-module

**Mandatory, every run, cannot be skipped or silently auto-answered (F23):** after pace / module cards, always ask **Additional checks?** — `No additional checks (recommended)` (Other automatic for a custom check). If Other, design a named check under `hfc/code/checks/<name>.R`, confirm the name/file, register under M11/`custom`, and write a ≤3-sentence plain-English description to `hfc/config/module_notes.yaml` (`custom.<name>.description`) so the HTML report can show it (see "Report display labels & descriptions" below).

## M1 — Completion

**Default: ON** — descriptive (counts + percentages), plus an optional low-completion flag.

1. M1 — Completion variable: use detected candidate (recommended) / pick alternate / derive from missingness (no single indicator column)
2. M1 — Group by (optional, `multiSelect: true`): detected grouping columns (treatment arm, state/district, school) / None (recommended)
3. M1 — Low-completion flag: On, 50% of median (recommended) / Off (descriptive only)

Reports: overall, by group(s), by enumerator, by date — counts **and** percentages, no charts by default (avoid a messy report).

## M2 — Duplicates

**Default: ON** — duplicate submission IDs / keys (DIME ieduplicates spirit); composite-ID aware.

Cards when reviewing:

1. M2 — Duplicates
   - On (recommended)
   - Off
2. M2 — Entity ID column(s) — usually already chosen in the required-fields gate; only re-ask if reviewing
3. M2 — Extra dup keys — usually already chosen in the duplicate-check-key sub-gate (e.g. round/wave); only re-ask if reviewing
   - None (recommended when Entity ID is already unique)
   - [detected round/wave-like column(s)]

## M3 — Form Version

**Default: ON** — best-effort, always propose-then-confirm, never trust silently.

1. M3 — Form version: if a version-like column is detected, `Use detected column (recommended)` / `No version tracking`. If none detected, `Best-guess N version windows from column-availability changes (recommended)` / `Skip form-version tracking`.
2. M3 — Version↔date mapping: `Use detected/inferred mapping (recommended)` / `Edit mapping` (sequential per-version corrections if editing).

Reports: version × date-range × n table. Optional finding when a real version column exists: recorded version doesn't match the expected version for its date.

## M4 — Survey Duration

**Default: ON** — descriptive stats (overall / by section / by enumerator) plus outlier flagging, decoupled from M5's early-start logic. Duration is always converted to and reported in **minutes** (the source column is SurveyCTO's native seconds export).

1. M4 — Duration stats: Overall + by-section + by-enumerator (recommended) / Overall only
2. M4 — Sections (if a form or column-name clustering finds candidates): Use detected N sections (recommended) / Edit sections
3. M4 — Outlier rule: 3 SD both sides (recommended) / 2.5 SD / 2 SD

## M5 — Irregular Timing

**Default: ON** — timezone-aware (uses the required-fields country/timezone confirm); absorbs the old "early start" concept.

1. M5 — Irregular timing: Flag weekends + evenings/nights, 7pm–7am (recommended) / Custom hours / Off
2. M5 — Hours window (if custom): alternates (e.g. 6pm–8am, 8pm–6am) or Other free text

## M6 — Numeric Outliers

**Default: ON** — up to 10 continuous vars (exclude IDs/codes), two-sided SD rule (default 3, was 2 before this redesign; the old 1%/99% percentile-tail hybrid is dropped for predictability).

1. M6 — Numeric outliers: On (recommended) / Off
2. M6 — Variables: Use recommended shortlist (up to 10) (recommended) / Edit list
   Prefer `multiSelect: true` on the shortlist when offering individual vars (≤4 options per call; split if needed).
3. M6 — SD threshold: 3 SD (recommended) / 2 SD / 2.5 SD

## M7 — Missingness

**Default: ON** — by important variables (≤10) and by enumerator. **Sequential dependency, must be respected in order:**

1. M7 — Variables: Use recommended shortlist (up to 10) (recommended) / Edit list
2. M7 — Missing codes **(this question's text must name the variables confirmed in step 1)**: `No special codes, blanks only (recommended)` / `Yes, same code(s) for all` / `Yes, different codes per variable`. If "same for all," one follow-up (Other) captures the shared code list. If "different per variable," loop per-variable (≤4 per call), each question naming the specific variable from step 1 — this cannot be authored as a static card set ahead of time, since it depends on step 1's answer.

Reports: missingness % by variable and by enumerator. Flags enumerators whose missingness on a variable is far above the survey-wide average.

## M8 — GPS

**Default: ON if coordinates found, else Off** — logic unchanged from the prior GPS module.

1. M8 — GPS: On (recommended if found) / Off
2. Coordinate pair: recommended pair / alternate
3. Threshold meters: 300 (recommended) / 100 / 500

When GPS is on, also AskUserQuestion **map focus** for the HTML report: Country / City / World. On the map, all points are shown; points flagged by M8 render in red, others in the default color.

## M9 — Straightlining

**Default: ON if ordinal-like candidates are detected, else Off.** Two independently-confirmed definitions (redefined properly from the prior design):

1. M9 — Straightlining: On (recommended if candidates found) / Off
2. M9 — Ordinal variables: Use detected ≤7-category variables (recommended) / Edit list
3. M9 — Enumerator threshold: 80% (recommended) / 70% / 90% — flags an enumerator who gave the identical single answer on one question in ≥ this share of their own surveys (per-question, not an overall pattern comparison).
4. M9 — Survey threshold: 80% (recommended) / 70% / 90% — flags a submission where ≥ this share of the confirmed ordinal variables share one identical value.

## M10 — Summary Statistics

**Default: ON** — purely descriptive, zero findings rows.

1. M10 — Variables: Use recommended shortlist (up to 10) (recommended) / Edit list / Increase beyond 10
2. M10 — How many (if increasing): 15 / 20 / Other for a custom count

Flat table only: Variable | Mean | SD | Min | Max | Obs — no panel/lettered grouping (the `assets/check_templates/sum stats.png` reference image is a formatting style cue only).

## M11 — Survey-specific

**Default: None.** M11 has no built-in checks — every M11 finding comes from a
custom check the agent writes for this survey's specific content, described
by the user at the Additional checks gate.

Custom user-described checks are registered under M11/`custom` and live as
`hfc/code/checks/<name>.R`, with an exported `run_<name>(ds, roles)` — see
`assets/check_templates/custom_check_example.R` for the convention.

## M12 — Media files (audio + pictures)

**Default: ON if filename columns detected** (`.m4a`/`.mp3`/… or `.jpg`/`.png`/…)

Checks: empty cell; file missing on disk; tiny file; bad extension; duplicate basename/hash; optional duration (`av`/`ffprobe`); flag↔file mismatch. No ML blur/speech in v1.

1. M12 — Media files: On (recommended if cols found) / Off
2. Audio columns: use detected set (recommended)
3. Image columns: use detected set (recommended)
4. Media folder: use discovered (recommended) / Column-only (no folder)
5. Duration window: 5–3600 s (recommended)

## M13 — Consent / assent / audio flags

**Default: ON if flag columns found**

Yes/no (or 0/1) **flags only** — not filename columns (those are M12). Respect nested skip-logic for assent/consent follow-ups.

1. M13 — Flags module: On (recommended if found) / Off
2. Assent / Consent / Audio flag columns: each as options + none (split asks if >4 choices)

## After cards

Map selections → `hfc/config/modules.yaml` + `hfc/config/role_map.yaml`, then run the builder. No typed mega-reply required.

## Report display labels & descriptions (authoritative)

Source of truth for how modules appear in `hfc/outputs/report.html` (mirrored as `MODULE_META` in `scripts/lib/build_outputs.R` — keep both in sync). Tab/heading text is the label; the module code still appears alongside it, smaller, since it's used internally (e.g. `findings.csv`). Descriptions are ≤3 plain-English sentences, no raw column names.

| Code | Label | Description |
|---|---|---|
| M1 | Completion | Reports how many submissions are complete overall, and by group, enumerator, and date, so gaps in fieldwork show up early. Can also flag sites whose completion falls far below the survey median. |
| M2 | Duplicates | Flags submissions that share the same unique ID or survey key, which usually means the same interview was uploaded or entered more than once. |
| M3 | Form Version | Tracks which version of the survey instrument was in use on each date, and flags any submission whose recorded version doesn't match the expected window for its date. |
| M4 | Survey Duration | Reports how long interviews took, in minutes, overall and by enumerator, and flags individual interviews that were unusually long or short. |
| M5 | Irregular Timing | Flags interviews conducted at unusual times — weekends or outside normal working hours — using each submission's local time zone. |
| M6 | Numeric Outliers | Flags unusually high or low values on key numeric questions (e.g. ages, scores) that fall outside the normal range for this survey. |
| M7 | Missingness | Flags variables and enumerators with unusually high rates of missing or sentinel-coded (e.g. 99, -9999) responses on key survey questions. |
| M8 | GPS Location | Flags submissions recorded far from where other submissions at that site were recorded, which can mean the interview happened somewhere unexpected. |
| M9 | Straightlining | Flags enumerators who gave the same answer on a question in most of their interviews, and submissions where most ordinal/Likert-style questions share one identical value. |
| M10 | Summary Statistics | A simple reference table of mean, SD, min, max, and observation count for the survey's most important numeric variables. |
| M11 | Survey-Specific | Flags logic issues specific to this survey's content (for example, a mismatch between a record saying something happened and the respondent's own answer), including any custom checks requested for this project. |
| M12 | Media Files | Flags problems with recorded audio/photo files: missing files, empty filename cells, unexpectedly small files, wrong file types, or duplicates. |
| M13 | Consent & Assent | Flags cases missing a required consent (guardian agreement) or assent (the child's own agreement) flag, which the survey should always capture before proceeding. |

Custom/M11 checks confirmed via the Additional-checks gate get their own description, authored at confirm time and persisted to `hfc/config/module_notes.yaml`:

```yaml
custom:
  <name>:
    label: "Short human name"
    description: "≤3 sentences, plain English, no raw column names."
overrides:        # optional — replaces a default M1-M13 description above for this survey
  M6: "Custom text replacing the default M6 description."
```
