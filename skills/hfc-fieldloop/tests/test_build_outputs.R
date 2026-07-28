# Regression test: write_html_report() over the synthetic fixture, checking
# the redesigned report features (Last Day tab, bold last-day rows, GPS
# color-coding, M1-M13 labels, stats-only modules render without findings).
# Run: Rscript tests/test_build_outputs.R   (from the skill root)

this_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))
skill_dir <- normalizePath(file.path(this_dir, ".."))
lib <- file.path(skill_dir, "scripts", "lib")
for (f in c("utils.R", "geo_timezone.R", "media.R", "form_logic.R", "profile_roles.R",
           "run_checks.R", "build_outputs.R")) {
  source(file.path(lib, f))
}
source(file.path(this_dir, "fixture_data.R"))
suppressPackageStartupMessages({ library(dplyr) })

fx <- build_fixture()
cfg <- build_fixture_config(fx$ds, fx$last_date)
res <- run_check_modules(fx$ds, cfg$roles, cfg$modules, project_root = NULL)

project_root <- tempfile("hfc_test_")
dir.create(project_root, recursive = TRUE)
html_path <- write_html_report(
  res$findings, project_root, "fixture-test", open = FALSE,
  roles = cfg$roles, ds = fx$ds, report_cfg = list(map_focus = "country"),
  module_notes = list(custom = list(), overrides = list()), stats = res$stats
)
html <- paste(readLines(html_path, warn = FALSE), collapse = "\n")

checks <- list(
  "Last Day tab present" = grepl("id='lastday'", html, fixed = TRUE),
  "row-bold class appears" = grepl("row-bold", html, fixed = TRUE),
  "GPS map flagged color branch" = grepl("p.flagged?", html, fixed = TRUE),
  "GPS map has red marker color" = grepl("#c0392b", html, fixed = TRUE),
  "M1 Completion label" = grepl(">Completion<", html, fixed = TRUE),
  "M9 Straightlining label" = grepl(">Straightlining<", html, fixed = TRUE),
  "M10 Summary Statistics label" = grepl(">Summary Statistics<", html, fixed = TRUE),
  "M10 has no '0 findings' heading" = !grepl("Summary Statistics</span> · 0 findings", html),
  "M12 Media Files label" = grepl(">Media Files<", html, fixed = TRUE),
  "M13 Consent label" = grepl("Consent &amp; Assent", html, fixed = TRUE),
  "composite ID visible in a table" = grepl("HH0", html, fixed = TRUE)
)
for (nm in names(checks)) {
  status <- if (isTRUE(checks[[nm]])) "PASS" else "FAIL"
  cat(sprintf("%-45s %s\n", nm, status))
}
if (!all(vapply(checks, isTRUE, logical(1)))) stop("one or more build_outputs.R checks failed")

about_pos <- regexpr("#about", html, fixed = TRUE)
summary_pos <- regexpr("#summary", html, fixed = TRUE)
lastday_pos <- regexpr("#lastday", html, fixed = TRUE)
m1_pos <- regexpr("#mod-m1\"", html, fixed = TRUE)
stopifnot(about_pos < summary_pos, summary_pos < lastday_pos, lastday_pos < m1_pos)

unlink(project_root, recursive = TRUE)
cat("ALL build_outputs.R regression checks PASSED\n")
