# Claude Code FieldLoop staging

This repo *is* the `.claude/` folder for a survey project — clone it directly into place, rename it, and you're set up. It contains the HFC FieldLoop skill (`skills/hfc-fieldloop/`), which runs a configurable set of high-frequency checks (M1–M14 — duplicates, outliers, GPS, timing, missingness, balance tables, and more), and validates its own config, report, and merge steps automatically as it builds. Turn on Claude Code's built-in **Auto** permission mode (`/permissions`, or the mode toggle) so the agent doesn't interrupt you for routine file reads/writes and `Rscript` calls — it's a setting you control yourself, not something this repo ships for you.

## Install into a survey project

Target layout once installed:

```
your_project/
├── .claude/
│   └── skills/hfc-fieldloop/
├── data/raw/            ← your survey export goes here
└── hfc/                 ← created automatically once you run it
```

**Option A — clone directly as `.claude` (recommended):**
```bash
cd /path/to/your_project
git clone https://github.com/AigleBlanc/worldbank-research.git .claude
```

**Option B — already cloned it:**
```bash
mv worldbank-research .claude
mv .claude /path/to/your_project/.claude
```

Then open `your_project/` in VS Code with Claude Code, and follow [`.claude/skills/hfc-fieldloop/README.md`](skills/hfc-fieldloop/README.md) for setup and day-to-day use.



---
## **Simplified usage instructions (in case you don't want to read [`.claude/skills/hfc-fieldloop/README.md`]):**

**a) Install the R packages** (once, from a terminal in your survey project folder):
```bash
Rscript .claude/skills/hfc-fieldloop/install.R
```

**b) Configure `config.json`** (once, at `.claude/skills/hfc-fieldloop/config.json`) — set four directories: **Input Data Directory** (your survey microdata export, never modified), **HFC Output Directory** (a folder the OneDrive desktop app is already syncing on this machine — install/sign in to OneDrive first, then point this at the local folder it syncs to; there's no sign-in step in the skill itself, it just reads/writes that folder like any other local folder), **Code Output Directory** (a folder you manage yourself, ideally a git repo, where the built `hfc/` report lands), and optionally **Media Folder Directory**. Share the OneDrive folder with your RA/field team via OneDrive's normal "Share" button, so they can open and edit `issue_tracking.xlsx` directly. Full details: [`.claude/skills/hfc-fieldloop/README.md`](skills/hfc-fieldloop/README.md).

If `config.json` isn't fully configured yet, the agent will tell you and stop before doing any real work — do steps a and b first.

**c) Run it**

In Claude Code, just talk to it in plain language. Two things to say:

| Say this | When |
|---|---|
| **"Run HFC FieldLoop"** | First time, or whenever you want to re-check the data (e.g. new submissions came in) |
| **"Process HFC feedback"** | After the field team/RA has written comments on flagged rows in `issue_tracking.xlsx` |

If your VS Code window has more than one survey project open, add the folder name: `"Run HFC FieldLoop for <folder_name>"`.

Setup only stops for a handful of quick confirmations (finding your data, gathering any instructions, and a final review before anything is approved) — the agent decides everything else itself, using its own best guess, and you can always ask it to walk you through every module's settings before approving if you'd rather review them all. Whenever it does ask, it's always via clickable option cards (never type long answers — just pick an option, or choose "Other" if nothing fits).
---