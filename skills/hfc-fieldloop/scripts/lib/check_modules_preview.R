# Pre-decision HTML preview of proposed check-module defaults — hfc/check_modules.html.
# Shown to the user BEFORE the accept-all/review pace question (SKILL.md A2.3),
# so there's something concrete to look at while deciding. Reuses the same
# tree CSS/dark theme as scripts/lib/product_structure.R's structure.html.

# One leaf <li> per non-empty "key: value" pair. Vector values get truncated
# via fmt_var_list() (module_desc.R) so a 10-variable shortlist doesn't blow
# up the tree. Skips NA/empty/FALSE-default fields entirely — a lean tree
# beats an exhaustive one here.
.preview_leaf <- function(label, value) {
    if (is.null(value) || length(value) == 0) return(NULL)
    if (length(value) > 1) {
        txt <- fmt_var_list(value, n = 6)
    } else {
        if (is.na(value) || (is.character(value) && !nzchar(value))) return(NULL)
        txt <- as.character(value)
    }
    if (!nzchar(txt)) return(NULL)
    sprintf("<li><span class='meta'>%s:</span> %s</li>", label, txt)
}

.preview_leaves <- function(pairs) {
    leaves <- Filter(Negate(is.null), Map(.preview_leaf, names(pairs), pairs))
    if (!length(leaves)) return("")
    paste0("<ul>", paste(unlist(leaves), collapse = ""), "</ul>")
}

# Module-specific "what's actually configured" leaves — mirrors default_modules()'s
# shape in profile_roles.R exactly, one case per module.
.module_config_leaves <- function(code, m) {
    switch(code,
        M1 = .preview_leaves(list("Group by" = m$group_vars, "Low-completion flag" = m$low_completion_on,
                                    "Threshold" = if (isTRUE(m$low_completion_on)) sprintf("%.0f%% of median", 100 * (m$pct_median %||% 0.5)) else NA_character_)),
        M2 = .preview_leaves(list("Key" = c(m$id, m$extra_keys))),
        M3 = .preview_leaves(list("Version column" = m$version_col)),
        M4 = .preview_leaves(list("Duration column" = m$duration, "SD threshold" = m$sd_rule)),
        M5 = .preview_leaves(list("Hours window" = sprintf("%02d:00-%02d:00", m$morning_hour %||% 7, m$evening_hour %||% 19),
                                    "Flag weekends" = m$flag_weekend)),
        M6 = .preview_leaves(list("Variables" = m$vars, "SD threshold" = m$sd_rule)),
        M7 = .preview_leaves(list("Variables" = m$vars, "SD multiplier" = m$sd_multiplier)),
        M8 = .preview_leaves(list("Coordinates" = c(m$x, m$y), "Threshold (m)" = m$threshold_m)),
        M9 = .preview_leaves(list("Ordinal variables" = m$ordinal_vars,
                                    "Enumerator threshold" = sprintf("%.0f%%", 100 * (m$enum_threshold_pct %||% 0.8)),
                                    "Survey threshold" = sprintf("%.0f%%", 100 * (m$survey_threshold_pct %||% 0.8)))),
        M10 = .preview_leaves(list("Variables" = m$vars)),
        M11 = "",
        M12 = .preview_leaves(list("Media folder" = m$media_folder, "Audio cols" = m$audio_cols, "Image cols" = m$image_cols,
                                     "Min duration (s)" = m$min_duration_sec, "Max duration (s)" = m$max_duration_sec)),
        M13 = .preview_leaves(list("Assent col" = m$assent, "Consent col" = m$consent, "Audio col" = m$audio)),
        ""
    )
}

write_check_modules_preview_html <- function(project_root, roles, modules, open = FALSE) {
    hfc <- hfc_root(project_root)
    dir.create(hfc, recursive = TRUE, showWarnings = FALSE)
    html_path <- file.path(hfc, "check_modules.html")
    proj_name <- basename(normalizePath(project_root, mustWork = FALSE))

    esc <- function(x) {
        x <- as.character(x)
        x <- gsub("&", "&amp;", x, fixed = TRUE)
        x <- gsub("<", "&lt;", x, fixed = TRUE)
        x <- gsub(">", "&gt;", x, fixed = TRUE)
        x
    }

    nodes <- vapply(MODULE_ORDER, function(code) {
        m <- modules[[code]] %||% list()
        is_on <- isTRUE(m$on)
        badge <- if (is_on) "<span class='badge on'>&#10003; ON</span>" else "<span class='badge off'>&minus; OFF</span>"
        label <- module_label(code)
        rationale <- esc(module_desc(code, modules))
        leaves <- .module_config_leaves(code, m)
        sprintf(
            "<li class='dir'><span class='name'>%s %s</span> %s<div class='rationale'>%s</div>%s</li>",
            code, esc(label), badge, rationale, leaves
        )
    }, character(1))

    html <- paste0(
'<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>HFC FieldLoop — proposed check modules (', proj_name, ')</title>
  <style>
    :root {
      --bg: #0f1419;
      --panel: #1a222c;
      --line: #2d3a47;
      --text: #e7eef5;
      --muted: #8b9aab;
      --accent: #3d9a7a;
      --accent2: #c4a35a;
      --dir: #6eb5ff;
      --file: #d4dde6;
      --on: #3d9a7a;
      --off: #5b6b7a;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      font-family: "IBM Plex Sans", "Source Sans 3", "Segoe UI", sans-serif;
      background:
        radial-gradient(1200px 600px at 10% -10%, #1c3340 0%, transparent 55%),
        radial-gradient(900px 500px at 100% 0%, #2a2418 0%, transparent 50%),
        var(--bg);
      color: var(--text);
      line-height: 1.45;
    }
    main { max-width: 920px; margin: 0 auto; padding: 2.5rem 1.5rem 4rem; }
    h1 {
      font-family: "IBM Plex Serif", Georgia, serif;
      font-weight: 600;
      font-size: clamp(1.6rem, 3vw, 2.1rem);
      margin: 0 0 0.4rem;
    }
    .lede { color: var(--muted); max-width: 40rem; margin: 0 0 1.75rem; }
    .note {
      border-left: 3px solid var(--accent);
      padding: 0.65rem 1rem;
      background: rgba(61, 154, 122, 0.08);
      color: var(--muted);
      font-size: 0.92rem;
      margin-bottom: 1.5rem;
    }
    .note strong { color: var(--accent2); font-weight: 600; }
    .tree {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 10px;
      padding: 1.25rem 1.35rem 1.4rem;
      font-family: "IBM Plex Mono", ui-monospace, monospace;
      font-size: 0.86rem;
      overflow-x: auto;
    }
    ul.tree-root, ul.tree-root ul { list-style: none; margin: 0; padding-left: 1.15rem; }
    ul.tree-root { padding-left: 0; }
    ul.tree-root > li.dir { padding: 0.55rem 0; border-bottom: 1px solid var(--line); }
    ul.tree-root > li.dir:last-child { border-bottom: none; }
    li { position: relative; padding: 0.18rem 0; color: var(--file); }
    .dir > .name { color: var(--dir); font-weight: 500; }
    .meta { color: var(--muted); font-size: 0.8rem; }
    .rationale { color: var(--file); font-size: 0.84rem; margin: 0.25rem 0 0.15rem; font-family: "IBM Plex Sans", sans-serif; }
    .badge { display: inline-block; font-size: 0.7rem; font-weight: 600; border-radius: 999px; padding: 0.05rem 0.55rem; margin-left: 0.5rem; font-family: "IBM Plex Sans", sans-serif; }
    .badge.on { background: rgba(61, 154, 122, 0.18); color: var(--on); border: 1px solid var(--on); }
    .badge.off { background: rgba(91, 107, 122, 0.18); color: var(--off); border: 1px solid var(--off); }
    footer { margin-top: 2rem; font-size: 0.85rem; color: var(--muted); }
  </style>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Serif:wght@600&display=swap" rel="stylesheet" />
</head>
<body>
  <main>
    <h1>Proposed check modules — ', proj_name, '</h1>
    <p class="lede">Every check module (M1&ndash;M13), with its proposed on/off default, why, and the key thresholds/variables it would use if built as-is.</p>
    <p class="note"><strong>Nothing is written yet.</strong> This reflects the profiler\'s recommended defaults, before you\'ve chosen Accept-all or Review-by-module in chat &mdash; use it to sanity-check the plan either way.</p>
    <div class="tree" aria-label="Check modules tree">
      <ul class="tree-root">
', paste(nodes, collapse = "\n"), '
      </ul>
    </div>
    <footer>HFC FieldLoop &middot; proposed check modules &middot; answer the pace question in chat next</footer>
  </main>
</body>
</html>
')
    writeLines(html, html_path)

    if (isTRUE(open) && !identical(Sys.getenv("CI"), "true") &&
        !identical(Sys.getenv("FIELDLOOP_NO_OPEN"), "1")) {
        try(utils::browseURL(html_path), silent = TRUE)
    }
    normalizePath(html_path)
}
