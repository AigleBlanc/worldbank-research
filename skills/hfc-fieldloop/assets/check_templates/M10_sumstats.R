# M10 — Summary Statistics
# Purely descriptive: a flat table (Variable | Mean | SD | Min | Max | Obs)
# for up to 10 confirmed important variables (user can raise the cap).
# No panel/lettered grouping — a clean flat table only. Produces zero
# findings rows; this is the one module with stats only.
# Full implementation: scripts/lib/run_checks.R M10 block.

check_m10_sumstats <- function(ds, roles, vars = character()) {
  vars <- vars[!is.na(vars) & vars %in% names(ds)]
  if (!length(vars)) return(tibble::tibble())
  rows <- lapply(vars, function(vc) {
    v <- safe_num(ds[[vc]]); ok <- is.finite(v)
    tibble::tibble(Variable = vc, Mean = round(mean(v[ok]), 3), SD = round(sd(v[ok]), 3),
                  Min = round(suppressWarnings(min(v[ok])), 3),
                  Max = round(suppressWarnings(max(v[ok])), 3), Obs = sum(ok))
  })
  dplyr::bind_rows(rows)
}
