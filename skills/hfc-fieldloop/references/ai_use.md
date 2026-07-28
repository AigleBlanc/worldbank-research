# AI use and confidentiality (FieldLoop)

FieldLoop helps build HFC checks and apply field feedback. Treat survey microdata as sensitive.

## Do not

- Paste respondent-level rows, names, phone numbers, GPS tracks, or other PII into commercial AI chat tools.
- Upload Official Use / Confidential / Strictly Confidential, partner-restricted, or DUA-covered files to tools not approved for that classification.

## Do

- Prefer column names, types, and aggregate counts when discussing data with an agent.
- Use institutional / approved environments when the full microdata must be in context.
- Document AI assistance in the **project** README when AI-generated text or classifications appear in a deliverable (see World Bank reproducibility AI guidance). Coding help that only produced scripts you ran does not require a full AI log, but a one-line disclosure is encouraged.

## FieldLoop-specific

- Findings and feedback IDs are fine to discuss; raw cell values that identify people are not.
- OneDrive sync stays inside your Microsoft 365 tenant's sharing model (folder access set up once, by hand, for specific people) — still avoid dumping exported feedback files into public AI tools.
