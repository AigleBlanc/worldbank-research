# Regression test: run_check_modules() over the synthetic fixture.
# Run: Rscript tests/test_run_checks.R   (from the skill root)

this_dir <- dirname(sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE)))
skill_dir <- normalizePath(file.path(this_dir, ".."))
lib <- file.path(skill_dir, "scripts", "lib")
for (f in c("utils.R", "geo_timezone.R", "media.R", "form_logic.R", "profile_roles.R", "run_checks.R")) {
  source(file.path(lib, f))
}
source(file.path(this_dir, "fixture_data.R"))
suppressPackageStartupMessages({ library(dplyr) })

fx <- build_fixture()
cfg <- build_fixture_config(fx$ds, fx$last_date)

res <- run_check_modules(fx$ds, cfg$roles, cfg$modules, project_root = NULL)
findings <- res$findings
stats <- res$stats

stopifnot(any(findings$check_module == "M2"))                                    # duplicates
stopifnot(any(findings$check_module == "M4" & findings$category == "long_duration"))
stopifnot(any(findings$check_module == "M4" & findings$category == "short_duration"))
stopifnot(any(findings$check_module == "M5"))                                    # irregular timing
stopifnot(any(findings$check_module == "M6"))                                    # numeric outliers
stopifnot(any(findings$check_module == "M8"))                                    # GPS outliers
stopifnot(any(findings$check_module == "M9" & findings$category == "straightlining_enum"))
stopifnot(any(findings$check_module == "M9" & findings$category == "straightlining_survey"))
stopifnot(any(findings$check_module == "M13"))                                   # consent/assent

stopifnot(!is.null(stats$M1$overall), nrow(stats$M1$overall) == 1)
stopifnot(!is.null(stats$M3), nrow(stats$M3) >= 1)
stopifnot(!is.null(stats$M4$overall), nrow(stats$M4$overall) == 1)
stopifnot(!is.null(stats$M7$by_variable), nrow(stats$M7$by_variable) == 2)
stopifnot(!is.null(stats$M10), nrow(stats$M10) >= 1)

# Composite ID must render as a pasted display string, not a raw column dump.
stopifnot(any(grepl(" / ", findings$submission_id[findings$check_module == "M2"])))

# check_id must never carry a leftover numeric prefix (decoupled by design).
stopifnot(!any(grepl("^[0-9]+_", findings$check_id)))

# sort_findings_for_display() 3-key order (enumerator, id, date desc), with
# blanks grouped last for enumerator/id.
source(file.path(lib, "build_outputs.R"))
tst <- tibble::tibble(
  finding_id = c("a", "b", "c", "d", "e"),
  enumerator = c("E2", "", "E1", "E1", ""),
  submission_id = c("S9", "S5", "", "S1", "S2"),
  start_date = c("2026-01-05", "2026-01-01", "2026-01-10", "2026-01-01", "2026-01-02"),
  end_date = rep("", 5)
)
ord <- sort_findings_for_display(tst)$finding_id
stopifnot(identical(ord, c("d", "c", "a", "e", "b")))

# resolve_country_timezone(): known match + unknown fallback
r1 <- resolve_country_timezone("Malawi")
stopifnot(identical(r1$tz, "Africa/Blantyre"))
r2 <- resolve_country_timezone("Neverland")
stopifnot(is.na(r2$tz))

cat("ALL run_checks.R regression checks PASSED (", nrow(findings), "findings)\n")
