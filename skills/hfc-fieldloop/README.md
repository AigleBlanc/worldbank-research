# HFC FieldLoop

FieldLoop runs High-Frequency Checks on your survey data, builds an HTML report, and gives you one shared spreadsheet (`issue_tracking.xlsx`) where the field team, the RA, and the AI agent all track and resolve data-quality issues together.

It never touches your original data file. Every fix is written to a separate copy (a sibling `intermediate/` folder next to your data), so your raw export always stays exactly as it was collected.

---

## 1. Install it

Clone this skill anywhere as `.claude/skills/hfc-fieldloop/` — it doesn't need to sit next to your survey data, and doesn't need to live inside a "survey project" folder at all:

```bash
git clone https://github.com/AigleBlanc/worldbank-research.git .claude
```

Open the folder containing `.claude/` in VS Code with Claude Code. Turn on Claude Code's built-in **Auto** permission mode (`/permissions`, or the mode toggle) so the agent doesn't interrupt you for routine file reads/writes and `Rscript` calls — it's a setting you control yourself, not something this repo changes for you.

## 2. Two things YOU need to run yourself

Everything else in this skill is run automatically by the AI agent when you talk to it — you never type an `Rscript` command by hand for normal use. Only these two setup steps are on you, and **both are required**. There's no working local-only mode `issue_tracking.xlsx` lives in OneDrive:

**a) Install the R packages** (once, from a terminal at the parent directory of .claude/):
```bash
Rscript .claude/skills/hfc-fieldloop/install.R
```

**b) Configure `config.json`** (once, at `.claude/skills/hfc-fieldloop/config.json`) — four directories:
```json
{
    "Input Data Directory": "/path/to/your/survey/data",
    "Media Folder Directory": "",
    "HFC Output Directory": "/Users/you/OneDrive - Your Org/HFC Reports",
    "Code Output Directory": "/path/to/a/git/repo/you/manage"
}
```
- **Input Data Directory** — the folder containing your survey microdata export (never modified)
- **Media Folder Directory** — optional; your SurveyCTO audio/photo attachments folder
- **HFC Output Directory** — a folder the OneDrive desktop app is syncing, for the shared `issue_tracking.xlsx` (make sure the OneDrive desktop app is installed and signed in on this machine first, and use the local folder it syncs to — there's no sign-in step in this skill itself, it just reads/writes that folder like any other local folder). Share that folder with your RA/field team via OneDrive's normal "Share" button, so they can open and edit `issue_tracking.xlsx` directly.
- **Code Output Directory** — a folder you manage yourself (ideally a git repo, this is where World Bank practice prefers versioned code/config output to live); the built `hfc/` report and checks land here. This skill only ever writes plain files there; it never runs git for you.

If `config.json` isn't fully configured yet, the agent will tell you and stop before doing any real work — do this first.

## 3. Run it

In Claude Code, just talk to it in plain language. Two things to say:

| Say this | When |
|---|---|
| **"Run HFC FieldLoop"** | First time, or whenever you want to re-check the data (e.g. new submissions came in) |
| **"Process HFC feedback"** | After the field team/RA has written comments on flagged rows in `issue_tracking.xlsx` |

The agent will ask you questions along the way using clickable option cards (never type long answers — just pick an option, or choose "Other" if nothing fits).

---

## How "Run HFC FieldLoop" works

1. The agent finds your data (and form, if you have one) and shows you its own best guess for a handful of things: what column identifies each respondent, what to call it in the report, and the data-collection country, all in one screen. Type a correction if anything's wrong; otherwise just confirm it looks right.
2. It proposes how it'll run each check (M1–M13: duplicates, outliers, GPS, timing, missing data, etc.); again as its own best guess, grouped into a couple of screens, never a long list of options to choose from.
3. It builds the report and opens `hfc/outputs/<MMDD>_HFCs.html` in your browser.
4. It creates (or updates) `issue_tracking.xlsx` — one row per flagged issue.

If `issue_tracking.xlsx` already exists (a second run), the agent doesn't overwrite it blindly — it shows you exactly what changed and asks you to confirm before anything is replaced. Nothing the field team already wrote is ever lost or silently dropped.

## How "Process HFC feedback" works

The field team and RA write comments directly into `issue_tracking.xlsx` (Comment column) on any row they want fixed. Once that's done:

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
| HTML report | `<Code Output Directory>/hfc/outputs/<MMDD>_HFCs.html` |
| Shared tracking file | `issue_tracking.xlsx` — in your configured **HFC Output Directory** (required, no local copy) |
| Fixed data (raw is never touched) | a sibling `intermediate/` folder next to your **Input Data Directory** |
| Your original data | your **Input Data Directory** — never modified |

## A note on privacy

Don't paste respondent-level data into commercial AI chat tools. See [`references/ai_use.md`](references/ai_use.md) for details.
