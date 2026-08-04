# Check templates (M1–M13)
#
# Authority for the underlying logic: ../../scripts/lib/run_checks.R's
# check_mN() functions (+ media.R for M12, geo_timezone.R for M5's timezone
# resolution) — each template here is a thin, real, runnable wrapper around
# the same shared function the build itself calls, not a separate copy of
# the logic.
# write_check_scripts() (build_outputs.R) copies the template for every
# confirmed-on module into hfc/code/checks/<name>.R at build time, with the
# `path <- "your/path/to/survey_project/"` line substituted for the real
# project path — same convention as assets/main.R -> hfc/code/main.R.
# Running the copied file standalone reproduces exactly that module's
# findings for the current data.
#
# Map: see ../../references/check_modules.md
