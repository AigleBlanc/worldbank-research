# Trigger phrases

After the trigger, the agent confirms via **AskUserQuestion** windows that state the agent's own best guess and offer one free-text correction (Claude Code supplies free-text **Other** automatically). See `interaction.md`. Users should not need to type `M1=Y M2=…`, and should never see a long menu of choices — just a guess to confirm or correct.

Also invokable as `/hfc-fieldloop` in Claude Code.

Built product lands under **`hfc/`**. Right after data discovery, one required-gate window confirms the discovered files, the entity label, and the data-collection country — see `SKILL.md`'s A1.

## Pipeline A — Setup

Use setup flow when the user says (case-insensitive, paraphrase OK):

- Run HFC FieldLoop
- Start FieldLoop
- Start HFC FieldLoop for this project
- Set up FieldLoop
- Build HFC checks / HFC report (when no feedback file exists yet)

No project path needed — every script reads its four directories (Input Data Directory, Media Folder Directory, HFC Output Directory, Code Output Directory) from `skills/hfc-fieldloop/config.json`. If `config.json` isn't fully configured yet, the config pre-flight (`SKILL.md`'s A0) stops and tells the user what to edit before proceeding.

## Pipeline B — Post-feedback

Use post-feedback flow when the user says:

- Process HFC feedback
- Run FieldLoop fixes
- Apply field feedback
- Apply HFC fixes
- Process feedback sheet

If ambiguous, AskUserQuestion: Setup new HFC package / Process existing feedback.
