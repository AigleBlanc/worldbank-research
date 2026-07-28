# hfc-fieldloop regression tests

Synthetic-data tests (no real survey data, no PII) covering the M1–M13 check
modules and the HTML report. Run from the skill root:

```bash
Rscript tests/test_run_checks.R
Rscript tests/test_build_outputs.R
```

- `fixture_data.R` — builds a synthetic dataset (~450 rows) exercising every
  module: composite ID (household × member), multi-country/timezone, GPS with
  seeded off-site points, ordinal straightlining patterns, sentinel-coded
  missingness, a form-version cutover, seeded duration outliers (both
  directions), and consent/assent/media flags. Not shipped as "gold" data —
  regenerated fresh each run (`set.seed()`-based), and safe to extend.
- `test_run_checks.R` — calls `run_check_modules()` directly (bypassing
  AskUserQuestion) and asserts per-module findings/stats match what was
  seeded, plus unit-level checks on `sort_findings_for_display()` and
  `resolve_country_timezone()`.
- `test_build_outputs.R` — calls `write_html_report()` and greps the
  generated HTML for the redesigned report features (Last Day tab, bold
  last-day rows, GPS red/green flagging, M1–M13 labels).

These are fast, dependency-light sanity checks — not a substitute for a final
manual run against a real survey project, especially for AskUserQuestion
sequencing (which can't be exercised outside a live Claude Code session) and
GPS/media performance at realistic scale.
