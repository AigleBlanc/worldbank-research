# Write hfc/structure.html — product tree map for user review before Continue.

write_product_structure_html <- function(project_root, open = FALSE) {
  hfc <- hfc_root(project_root)
  dir.create(hfc, recursive = TRUE, showWarnings = FALSE)
  html_path <- file.path(hfc, "structure.html")
  proj_name <- basename(normalizePath(project_root, mustWork = FALSE))

  html <- paste0(
'<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>HFC FieldLoop — product structure (', proj_name, ')</title>
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
    li { position: relative; padding: 0.18rem 0; color: var(--file); }
    .dir > .name { color: var(--dir); font-weight: 500; }
    .meta { color: var(--muted); font-size: 0.8rem; margin-left: 0.5rem; }
    footer { margin-top: 2rem; font-size: 0.85rem; color: var(--muted); }
  </style>
  <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500&family=IBM+Plex+Sans:wght@400;500;600&family=IBM+Plex+Serif:wght@600&display=swap" rel="stylesheet" />
</head>
<body>
  <main>
    <h1>FieldLoop product — ', proj_name, '</h1>
    <p class="lede">Built artifacts for this survey live under <code>hfc/</code>. Raw microdata stays in <code>data/raw/</code>; the skill stays in <code>hfc-fieldloop/</code>. The shared <code>issue_tracking.xlsx</code> — and its dated snapshot/resolutions subfolders — live entirely in your configured OneDrive folder, not shown in this local tree.</p>
    <p class="note"><strong>Review in browser, then Continue.</strong> Confirm this layout via AskUserQuestion before the full build writes checks, the report, and the shared issue tracking file.</p>
    <div class="tree" aria-label="Product folder tree">
      <ul class="tree-root">
        <li class="dir"><span class="name">', proj_name, '/</span>
          <ul>
            <li class="dir"><span class="name">data/raw/</span><span class="meta">originals (never mutated)</span></li>
            <li class="dir"><span class="name">hfc-fieldloop/</span><span class="meta">skill (drop-in)</span></li>
            <li class="dir"><span class="name">hfc/</span>
              <ul>
                <li><span class="name">structure.html</span><span class="meta">this map</span></li>
                <li><span class="name">project.yaml</span></li>
                <li class="dir"><span class="name">config/</span>
                  <ul>
                    <li>modules.yaml · role_map.yaml</li>
                    <li>onedrive.json · module_cards.txt</li>
                  </ul>
                </li>
                <li class="dir"><span class="name">instruments/</span><span class="meta">optional form copy</span></li>
                <li class="dir"><span class="name">registry/</span><span class="meta">findings.csv</span></li>
                <li class="dir"><span class="name">outputs/</span><span class="meta">report.html</span></li>
                <li class="dir"><span class="name">code/</span><span class="meta">main.R</span>
                  <ul>
                    <li class="dir"><span class="name">checks/</span><span class="meta">M1–M13 (runnable) + custom (e.g. example_check.R)</span></li>
                    <li class="dir"><span class="name">resolutions/</span><span class="meta">post-feedback fix scripts</span></li>
                  </ul>
                </li>
              </ul>
            </li>
          </ul>
        </li>
      </ul>
    </div>
    <footer>HFC FieldLoop · product structure · confirm Continue in chat after reviewing</footer>
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
