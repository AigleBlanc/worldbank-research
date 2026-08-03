# HFC FieldLoop

FieldLoop runs High-Frequency Checks on your survey data, builds an HTML report, and gives you one shared spreadsheet (`issue_tracking.xlsx`) where the field team, the RA, and the AI agent all track and resolve data-quality issues together.

It never touches your original data file. Every fix is written to a separate copy (`data/intermediate/`), so your raw export always stays exactly as it was collected.

---

## 1. Install it

Copy this folder into your survey project as `.claude/skills/hfc-fieldloop/`:

```
your_survey/
├── .claude/skills/hfc-fieldloop/   ← this skill
├── data/raw/                       ← your survey export (.csv, .dta, .xlsx)
└── hfc/                            ← created automatically once you run it
```

Open `your_survey/` (not a parent folder containing many projects) in VS Code with Claude Code.

## 2. Two things YOU need to run yourself

Everything else in this skill is run automatically by the AI agent when you talk to it — you never type an `Rscript` command by hand for normal use. Only these two setup steps are on you:

**a) Install the R packages** (once, from a terminal in your survey project folder):
```bash
Rscript .claude/skills/hfc-fieldloop/install.R
```

**b) Set up OneDrive** (optional, but recommended if more than one person will edit the tracking file). Skip this if you're fine with everything staying local on your own computer.
1. Open `.claude/skills/hfc-fieldloop/assets/lib/onedrive.json` and set `"enabled": true`. Pick a `folder_path` (e.g. `"HFC Reports"`) — this is where things will be stored in your OneDrive.
2. Sign in once, yourself, outside of Claude Code, in a normal R or RStudio session:
   ```bash
   Rscript .claude/skills/hfc-fieldloop/setup_onedrive_auth.R
   ```
   This opens a browser login. After this one time, the agent can read/write that OneDrive folder automatically — no further sign-ins needed.
3. Share that OneDrive folder with your RA/field team via OneDrive's normal "Share" button, so they can open and edit `issue_tracking.xlsx` directly.

If you skip OneDrive, everything still works — the tracking file just lives locally at `hfc/output/issue_tracking.xlsx` instead of being shared automatically.

## 3. Run it

In Claude Code, just talk to it in plain language. Two things to say:

| Say this | When |
|---|---|
| **"Run HFC FieldLoop"** | First time, or whenever you want to re-check the data (e.g. new submissions came in) |
| **"Process HFC feedback"** | After the field team/RA has written comments on flagged rows in `issue_tracking.xlsx` |

If your VS Code window has more than one survey project open, add the folder name: `"Run HFC FieldLoop for malawi_survey"`.

The agent will ask you questions along the way using clickable option cards (never type long answers — just pick an option, or choose "Other" if nothing fits).

---

## How "Run HFC FieldLoop" works

1. The agent finds your data (and form, if you have one) and confirms it with you.
2. It asks a few required questions: what column identifies each person/household/unit, what to call that in the report, how to check for duplicates, which country/timezone, and the last day of data collection.
3. It proposes which checks to run (M1–M13: duplicates, outliers, GPS, timing, missing data, etc.) — accept the defaults or review them one by one.
4. It builds the report and opens `hfc/report/index.html` in your browser.
5. It creates (or updates) `issue_tracking.xlsx` — one row per flagged issue.

If `issue_tracking.xlsx` already exists (a second run), the agent doesn't overwrite it blindly — it shows you exactly what changed and asks you to confirm before anything is replaced. Nothing the field team already wrote is ever lost or silently dropped.

## How "Process HFC feedback" works

The field team and RA write comments directly into `issue_tracking.xlsx` (RIL Comment column) on any row they want fixed. Once that's done:

1. Say **"Process HFC feedback"**.
2. The agent finds every row that's still `Open` and has a comment, and shows you the list.
3. For each one, the agent writes the fix in code, applies it to a copy of the data, and proposes what the `Status` and `Corrections` should say.
4. Once all rows are handled, it shows you a summary of what will change in the shared tracking file and asks you to confirm.
5. Only after you confirm does the live `issue_tracking.xlsx` actually get updated.

### What the `Status` column means

| Status | What it means | Who sets it |
|---|---|---|
| `Open` | Not yet resolved — the default | Automatic |
| `Accepted` | Field/RA confirms this is a real issue (optional — not required for the agent to act) | Field team / RA |
| `Revise` | Field/RA disagrees with the flag | Field team / RA |
| `Resolved` | The agent applied a fix | Agent, after you confirm |
| `Needs Review` | The agent couldn't confidently fix it — needs a human look | Agent, after you confirm |

You don't have to set `Accepted` before the agent will act — it picks up any `Open` row that has a comment.

---

## Where things end up

| What | Where |
|---|---|
| HTML report | `hfc/report/index.html` |
| Shared tracking file | `issue_tracking.xlsx` — in your OneDrive folder if configured, otherwise `hfc/output/issue_tracking.xlsx` |
| Fixed data (raw is never touched) | `data/intermediate/` |
| Your original data | `data/raw/` — never modified |

## A note on privacy

Don't paste household/respondent-level data into commercial AI chat tools. See [`references/ai_use.md`](references/ai_use.md) for details.
