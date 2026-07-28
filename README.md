# Claude Code FieldLoop staging

Drop-in skill for **VS Code + Claude Code**. Same product as repo-root [`hfc-fieldloop/`](../hfc-fieldloop/) (Cursor); this copy uses AskUserQuestion instead of AskQuestion.

## Test in a survey project

```bash
mkdir -p /path/to/any_survey/.claude/skills
cp -R CLAUDE/skills/hfc-fieldloop /path/to/any_survey/.claude/skills/
# add data to any_survey/data/raw/
# open any_survey in VS Code → Run HFC FieldLoop  or  /hfc-fieldloop
```

Target layout:

```
any_survey/
├── .claude/skills/hfc-fieldloop/
├── data/raw/
└── hfc/                 # after setup
```

See [`skills/hfc-fieldloop/README.md`](skills/hfc-fieldloop/README.md).
