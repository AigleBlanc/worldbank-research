# Gold-standard Summary narrative example (FieldLoop)

Annotated example of the Slack-register message the FieldLoop agent drafts in A4 step 6 (and again after every "Process HFC feedback" pass, Pipeline B step 7), written to `hfc/config/summary_message.md` and folded into `hfc/outputs/<MMDD>_HFCs.html`. Annotations in [brackets] explain why each line works. Calibrated against a real field RA's daily Slack update, not an idealized one: it focuses on **the most recent day of data collection**, states real numbers for that day specifically (not just cumulative-to-date), and **carries forward anything important that's still unresolved** even when it didn't originate that day. **Shape: lead sentences first (completion + reasons, outliers, duration, duplicates, enumerator roster, in that order), then a bullet list for everything else.** Length follows however many real, distinct points the latest day and any carried-forward issues actually produce — don't pad, but don't compress real points just to hit a target line count. Pair with `SKILL.md`'s A4 step 6 instructions.

---

> Hi @team, here's an update on endline data collection in Bubanza and Bujumbura provinces, with data synced through Aug 12. We received submissions for 3 schools yesterday, all 3 completed. That brings the running total to 16 of 18 planned schools completed (89%) — 2 still pending: School 9 (headteacher unavailable at both visits, a new one is scheduled for Aug 14) and School 14 (declined participation). @fieldteam please keep an eye on School 9's rescheduled visit. Treatment schools are at 92% completed, control at 86%.

[Why this works: dated to the actual latest sync day ("through Aug 12"), states THAT day's own activity first (3 schools received yesterday, all completed) — not only a cumulative total — while still keeping the cumulative-vs-target framing (16 of 18) since a field team needs both "what came in yesterday" and "where do we stand overall." This is M1's completion accounting (target-vs-actual, or primary/secondary composition — whichever completion signal applies) plus the **Reasons for non-completion** breakdown (`stats$by_reason`, gating mode only) folded into the same sentence rather than a separate line, since there are only 2 pending schools — a short list reads more naturally inline; a longer one still gets its own sentence. Completion is also reported BY GROUP, defaulting to Treatment/Control — read straight from M1's by-group stats table, never falling back to a geographic breakdown unless there's no Treatment/Control column at all. The `@fieldteam` mention gives a concrete next action to a concrete audience.]

> One school (School 6) reported a pass rate of 98%, far above the sample average of 61% so far — this could be a genuine top performer, but wanted to flag it in case it's a data entry issue on the test-score sheet. Same as yesterday, I still haven't heard back on whether that's plausible for a school with this profile. Logged on the data issues sheet with school ID, enumerator, arm, test date, and pass rate — happy to pull the underlying records if useful.

[Why this works: a real M6 numeric-outlier flag, narrated in plain language with the actual value and context, **posed as a genuine plausibility question** ("wanted to flag it in case...") rather than a flat "this value is wrong" assertion — the RA doesn't know local context well enough to be sure, so they ask. **"Same as yesterday"** explicitly marks that this was already reported in a prior day's build and is still open (Status not yet Resolved in `issue_tracking.xlsx`, or still mentioned in the most recent prior `<MMDD>_HFCs.html` on disk) — the point of the "focus on the latest day, but carry forward unresolved issues" rule: don't drop something important just because it didn't originate today, but don't re-derive the whole explanation from scratch either, a short "still open" marker is enough. Names the columns available in the data issues sheet and offers to expand — an invitation, not a data dump.]

> Average survey duration is 106 mins (median is 104 mins).

[Why this works: both mean AND median, in minutes, straight from M4's stats — median catches what a mean alone would hide (a few very long or very short interviews dragging the average).]

> There are 2 duplicates for School ID 4 Gashanga - @fieldboss please address them - issue_tracking.xlsx (real path)

[Why this works: names the real entity ("School ID 4 Gashanga," not "a school"), the real count (2), a real file path the reader can actually open, and an `@mention` placeholder aimed at whoever should act on it. This comes from M2's findings in `hfc/outputs/issues.csv`, not a generic "some duplicates were found."]

> Enumerators yesterday: Joan visited 2 schools (2 completed), Bridget 1 school (1 completed). I don't see any submissions from Nassali since Aug 10 — could you check in and remind them to sync by 9pm local time (2pm DC time) so we can flag issues while they're still fresh?

[Why this works: a full daily roster, not just a below-target flag — every enumerator active on the latest day gets an attempted-vs-completed tally (`stats$by_enum_latest_day`, M1), so the reader sees the whole picture, not just who's in trouble. The real value is the **explicit, actionable call-out for anyone who submitted nothing** — named directly, with their actual last-active date and a concrete ask (a real deadline, in both local and reference time zones) rather than a vague "please follow up." This still fires even when `daily_target_per_enum` was never confirmed — it's a roster of who did what, not a threshold check.]

> Other issues:
> - Attendance and test-score sheets were not available for 3 schools - schools 141, 157, and 176.
> - 2 interviews at School 12 were flagged more than 300m from the site's other submissions.

[Why this works: a real bullet list, one theme per line, same "name real entities/counts, never vague" rule as the lead sentences — this is where everything that ISN'T completion/reasons/outliers/duration/duplicates/enumerators belongs (M5, M7-M13, media/data-presence gaps). The data-presence gap statement is translated from M11's (dataset-level) "this column is completely empty" finding and/or M7's missingness findings into a school-by-school list a field team can actually act on — never just restating M11's raw one-line finding ("column X is empty") verbatim, that tells nobody which schools to follow up with.]

---

## What NOT to do

- Don't write "several schools had issues" — name them.
- Don't only report cumulative-to-date totals — state what the LATEST day of data collection itself brought in, then note where that leaves the cumulative-vs-target picture.
- Don't drop something important just because it didn't originate on the latest day — if `issue_tracking.xlsx` still shows it Open, or the most recent prior day's report still mentioned it, carry it forward with a short marker ("Same as yesterday: ..."). Don't re-derive the whole explanation from scratch every day, either — a brief "still open" note is enough unless something material actually changed.
- Don't skip the completion-vs-target framing even when completion looks fine — "17 of 17 schools completed as planned" is still worth stating plainly.
- Don't bury completion, reasons, outliers, duration, duplicates, or the enumerator roster inside the "Other issues" bullet list — they're the lead, stated as sentences, in that order.
- Don't flatly assert an outlier is wrong when you genuinely don't know — pose it as a plausibility question when local-context judgment is needed, same as a field RA would.
- Don't reduce the enumerator report to only who's below target — give the real daily roster, and make sure anyone with zero submissions is named directly with a concrete, actionable ask (not just "some enumerators haven't submitted").
- Don't fabricate narrative detail the pipeline's own findings/data don't actually support — e.g. describing what's visible in a photo, or any other manual-review detail no check module inspects. FieldLoop's checks never look at media content (M11 only flags a fully-empty column); stick to what `issues.csv`/`stats$` actually show.
- Don't omit the `issue_tracking.xlsx` path when naming a specific finding — the point is to get someone to act on it, not just acknowledge it exists.
- Don't pad with anonymized/aggregated-only language when PII is fine here — this message is for the internal field/RA team, not a public report. See `references/ai_use.md` for where PII actually needs care (never pasted into commercial AI tools).
- Don't pad to hit a line-count target, and don't compress real, distinct points just to stay short — length follows the actual number of things worth saying about the latest day plus anything genuinely still open.
