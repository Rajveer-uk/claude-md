---
name: council
description: Convene a 6-member decision council (optimist, pessimist, out-of-the-box, skeptic, pragmatist, chair) to deliberate a question or proposal and return a synthesized verdict. Use for high-stakes or ambiguous decisions.
---

# Council

When invoked with a question or proposal, you (the main session) are the **convener** — the seats are subagents and cannot run each other, so you carry the text between every step.

## Steps

1. **Restate** the question/proposal in one or two neutral sentences.
2. **Fan out — Round 1 (independent + blind).** In a SINGLE message, invoke these five seats in parallel via the Agent tool, giving each the SAME restated question and **none** of the others' answers:
   `council-optimist`, `council-pessimist`, `council-out-of-the-box`, `council-skeptic`, `council-pragmatist`.
   Each returns one independent take (position, reasons, assumptions, confidence).
3. **(Optional) Round 2 — cross-examination.** Only for high-stakes calls: paste the five anonymized takes back to each seat and ask it to challenge or update its view. Skip for routine questions to save cost.
4. **Synthesize.** Invoke `council-chair` once, passing it all five (or ten) takes as context. It returns the verdict: consensus, a disagreements table, one ranked recommendation with a confidence level, the smallest reversible next step, and still-open questions.
5. **Return** the chair's verdict to the user, with the raw takes in a collapsible appendix.

## Rules

- Keep each seat's Round-1 input identical and independent (blind) to prevent anchoring and groupthink.
- The seats reason only over what you pass them — they have no network and cannot fetch data.
- The chair only reconciles; don't let it introduce a position no seat raised.
- For a routine question, one round + chair is enough; reserve Round 2 for consequential decisions.
