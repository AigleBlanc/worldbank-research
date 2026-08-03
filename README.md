# Claude Code FieldLoop staging

This repo *is* the `.claude/` folder for a survey project — clone it directly into place, rename it, and you're set up. It contains the HFC FieldLoop skill (`skills/hfc-fieldloop/`) plus a `settings.json` that pre-approves the permissions the skill needs, so Claude Code doesn't interrupt you for every file read or `Rscript` call.

## Install into a survey project

Target layout once installed:

```
your_project/
├── .claude/
│   ├── settings.json
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

**b) Set up OneDrive** 
1. Open `.claude/skills/hfc-fieldloop/assets/lib/onedrive.json` and set `"enabled": true`. Pick a `folder_path` (e.g. `"HFC Reports"`) — this is where things will be stored in your OneDrive.
2. Sign in once, yourself, outside of Claude Code, in a normal R or RStudio session:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/setup_onedrive_auth.R
   ```
   This opens a browser login. After this one time, the agent can read/write that OneDrive folder automatically — no further sign-ins needed.
3. Share that OneDrive folder with your RA/field team via OneDrive's normal "Share" button, so they can open and edit `issue_tracking.xlsx` directly.

If you skip OneDrive, everything still works — the tracking file just lives locally at `hfc/output/issue_tracking.xlsx` instead of being shared automatically.

**c) Run it**

In Claude Code, just talk to it in plain language. Two things to say:

| Say this | When |
|---|---|
| **"Run HFC FieldLoop"** | First time, or whenever you want to re-check the data (e.g. new submissions came in) |
| **"Process HFC feedback"** | After the field team/RA has written comments on flagged rows in `issue_tracking.xlsx` |

If your VS Code window has more than one survey project open, add the folder name: `"Run HFC FieldLoop for <folder_name>"`.

The agent will ask you questions along the way using clickable option cards (never type long answers — just pick an option, or choose "Other" if nothing fits).
---