# Gold-standard Summary narrative example (FieldLoop)

Annotated example of the short Slack-register message the FieldLoop agent drafts in A4 step 6 (and again after every "Process HFC feedback" pass, Pipeline B step 7), written to `hfc/config/summary_message.md` and folded into `hfc/outputs/report.html`. Annotations in [brackets] explain why each line works. Pair with `SKILL.md`'s A4 step 6 instructions.

---

> Hi @team, here is an update from Day 1 of endline data collection in Bubanza and Bujumbura provinces. The team started with Bujumbura. We have data from 17 schools. If 18 schools were completed as planned, then please follow up with the pending school for submission @fieldteam

[Why this works: names real places (Bubanza, Bujumbura), a real count (17 schools), and states the target explicitly (18 planned) — this is M1's completion accounting (target-vs-actual, or primary/secondary composition — whichever completion signal applies), not a vague "most schools are done." The `@fieldteam` mention gives a concrete next action to a concrete audience, not just a status report.]

> 12% treatment and 19% control schools were surveyed on Day 1

[Why this works: completion reported BY GROUP, defaulting to Treatment/Control — read straight from M1's by-group stats table. Never falls back to a geographic breakdown here unless there's no Treatment/Control column at all.]

> There are 2 duplicates for School ID 4 Gashanga - @fieldboss please address them - issue_tracking.xlsx (real path)

[Why this works: names the real entity ("School ID 4 Gashanga," not "a school"), the real count (2), a real file path the reader can actually open, and an `@mention` placeholder aimed at whoever should act on it. This comes from M2's findings in `hfc/registry/findings.csv`, not a generic "some duplicates were found."]

> Average survey duration is 106 mins (median is 104 mins).

[Why this works: both mean AND median, in minutes, straight from M4's stats — median catches what a mean alone would hide (a few very long or very short interviews dragging the average).]

> Attendance, baseline ledger, and/or test scores were not available in 4 schools - schools 141, 157, 176, and 192.

[Why this works: this is the data/media-presence gap statement, at entity/group granularity — translated from M12's (now dataset-level) "this column is completely empty" finding and/or M7's missingness findings into a school-by-school list a field team can actually act on. Never just restates M12's raw one-line finding ("column X is empty") verbatim — that tells nobody which schools to follow up with.]

---

## What NOT to do

- Don't write "several schools had issues" — name them.
- Don't skip the completion-vs-target framing even when completion looks fine — "17 of 17 schools completed as planned" is still worth stating plainly.
- Don't omit the `issue_tracking.xlsx` path when naming a specific finding — the point is to get someone to act on it, not just acknowledge it exists.
- Don't pad with anonymized/aggregated-only language when PII is fine here — this message is for the internal field/RA team, not a public report. See `references/ai_use.md` for where PII actually needs care (never pasted into commercial AI tools).
- Don't make it long. Five to seven lines, one fact per line, is the target — this is a morning Slack update, not the full report.
