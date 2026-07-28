# M12 — Media files (audio + pictures)
# Live authority: scripts/lib/media.R -> run_m12_media_checks()

check_m12_media <- function(ds, roles, modules) {
  if (!exists("run_m12_media_checks", mode = "function")) {
    return(empty_findings())
  }
  run_m12_media_checks(ds, roles, modules)
}
