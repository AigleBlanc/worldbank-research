# Check templates (M1–M13)
#
# Authority for the underlying logic: ../../scripts/lib/run_checks.R's
# check_mN() functions (+ media.R for M11, geo_timezone.R for M5's timezone
# resolution) — each template here is a thin, real, runnable wrapper around
# the same shared function the build itself calls, not a separate copy of
# the logic.
# write_check_scripts() (build_outputs.R) copies the template for every
# confirmed-on module into hfc/code/checks/<name>.R at build time, with the
# `skill <- "your/path/to/hfc-fieldloop/"` and
# `code_output_dir <- "your/path/to/hfc/output/"` lines substituted for the
# real paths — same convention as assets/main.R -> hfc/code/main.R.
# input_data_dir is read live from config.json (not frozen at generation
# time), so a later config.json edit is honored without regenerating.
# Running the copied file standalone reproduces exactly that module's
# findings for the current data.
#
# Map: see ../../references/check_modules.md
