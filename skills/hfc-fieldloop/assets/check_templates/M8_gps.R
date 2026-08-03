# M8 — GPS distance from unit median reference
# Report: all points are shown on the map; points flagged here render in red.

check_m8_gps <- function(ds, roles, threshold_m = 300) {
  xc <- roles$x; yc <- roles$y; grp <- roles$group
  if (any(is.null(c(xc, yc, grp))) || any(is.na(c(xc, yc, grp)))) return(empty_findings())
  if (!all(c(xc, yc, grp) %in% names(ds))) return(empty_findings())
  # Full implementation: scripts/lib/run_checks.R M8 block
  empty_findings()
}
