# Trigger phrases

After the trigger, the agent confirms via **AskUserQuestion** option cards (Claude Code supplies free-text **Other** automatically). See `interaction.md`. Users should not need to type `M1=Y M2=…`.

Also invokable as `/hfc-fieldloop` in Claude Code.

Built product lands under **`hfc/`**. Unique submission ID is a hard gate (≤3 shortlist) right after data confirm.

## Pipeline A — Setup

Use setup flow when the user says (case-insensitive, paraphrase OK):

- Run HFC FieldLoop
- Start FieldLoop
- Start HFC FieldLoop for this project
- Set up FieldLoop
- Build HFC checks / HFC report (when no feedback file exists yet)

**Project path (required when workspace ≠ survey root):** include the survey folder in the prompt, e.g.:

- Run HFC FieldLoop for `test/malawi1`
- Run HFC FieldLoop for malawi1
- Run HFC FieldLoop project: `path/to/survey`

`project_root` = that folder (must contain `.claude/skills/hfc-fieldloop/` when using this drop-in, and usually `data/raw/`). Do **not** treat the monorepo / workspace root as the survey project unless the user said so or that root itself holds the skill + data.

If the path is still ambiguous, AskUserQuestion with up to 4 candidate folders (Other automatic).

## Pipeline B — Post-feedback

Use post-feedback flow when the user says:

- Process HFC feedback
- Run FieldLoop fixes
- Apply field feedback
- Apply HFC fixes
- Process feedback sheet

Prefer the same project naming: `Process HFC feedback for test/malawi1`.

If ambiguous, AskUserQuestion: Setup new HFC package / Process existing feedback.  
If multiple survey folders and no path given, AskUserQuestion: up to 4 candidate folders.
