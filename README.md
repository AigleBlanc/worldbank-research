# Claude Code FieldLoop staging

Drop-in skill for **VS Code + Claude Code**, staged here for testing before being copied into a survey project.

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
