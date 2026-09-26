---
name: council
description: Convene a 6-member decision council (optimist, pessimist, out-of-the-box, skeptic, pragmatist, chair) to deliberate a question or proposal and return a synthesized verdict. Use for high-stakes or ambiguous decisions.
---

# Council

When invoked with a question or proposal, you (the main session) are the **convener** — the seats are subagents and cannot run each other, so you carry the text between every step. The seats start without CLAUDE.md (`omitClaudeMd`), so your brief is their only project context.

**Seat names.** Plugin install: `council:council-optimist`, `council:council-pessimist`, `council:council-out-of-the-box`, `council:council-skeptic`, `council:council-pragmatist`, `council:council-chair`. Manual install (agents copied into `~/.claude/agents/` or `.claude/agents/`): the bare names used below. No Agent tool, or no seat agents installed → **Chat fallback** below.

## Steps

1. **Restate and brief.** Restate the question/proposal in one or two neutral sentences, then build one brief that every seat gets unchanged:
   - **Question:** the restatement.
   - **Context:** only the facts the decision turns on — goal, hard constraints (budget, deadline, team, stack, non-negotiables), options already ruled out and why — drawn from CLAUDE.md and the conversation. A few lines of facts, no opinions; it is multiplied across six agents.
   - **Standing rules:** the matching `REGRESSIONS.md` rows, verbatim — `grep -i "biz/" REGRESSIONS.md`, plus the area tag the question touches (`mkt/`, `ops/`, `docs/`, `code/<area>`). Write "none" if there is no ledger or no match.
2. **Fan out — Round 1 (independent + blind).** In **one** message, invoke these five seats in parallel via the Agent tool, giving each the same brief and **none** of the others' answers:
   `council-optimist`, `council-pessimist`, `council-out-of-the-box`, `council-skeptic`, `council-pragmatist`.
   Each returns one independent take (position, reasons, assumptions, confidence).
3. **(Optional) Round 2 — cross-examination.** Only for high-stakes calls: paste the five anonymized takes back to each seat and ask it to challenge or update its view. Skip for routine questions to save cost.
4. **Synthesize.** Invoke `council-chair` once, passing it the brief and all five (or ten) takes as context. It returns the verdict: consensus, a disagreements table, one ranked recommendation with a confidence level, the smallest reversible next step, and still-open questions.
5. **Return** the chair's verdict to the user, with the raw takes in a collapsible appendix.

## Chat fallback (no sub-agents)

Use this where the Agent tool or the seat agents aren't available — Claude chat on the web, the Desktop app's Chat tab, mobile, or an uploaded copy of this skill. You play every seat yourself, in turn, under the same Rules. In Claude Code or Cowork with the council installed, use the Steps above.

1. **Restate and brief** as in step 1. Context comes from the conversation and the Project's instructions; standing rules from the `REGRESSIONS.md` in the Project's knowledge files, if there is one.
2. **Seats — sequential and blind.** Write the five takes in this order, each under its own heading. Write each one from the brief only, as if it were the first: don't cite, answer or build on an earlier take, and don't edit an earlier take after writing a later one. In every seat, rank points strongest first and label key claims known / assumed / hoped.
   - **Optimist** — the strongest good-faith case for: position · best case · the 3 strongest reasons · the conditions it depends on, each with an early signal that would falsify it · confidence.
   - **Pessimist** — a pre-mortem that assumes failure: position · top 3 failure modes, each with rough likelihood, cost and a mitigation · the most fragile assumption · a one-paragraph pre-mortem · confidence.
   - **Out-of-the-box** — challenge the framing: a reframe · 2–3 non-obvious alternatives · one option that makes the question obsolete · which alternative most deserves a cheap test.
   - **Skeptic** — steelman, then attack: the weakest claims and why · a known / assumed / hoped breakdown · the one piece of evidence that would most change the decision · evidential confidence.
   - **Pragmatist** — real constraints: the binding constraints · feasible now vs later · the smallest viable, reversible next step · what to defer or cut · rough effort and the assumption it is most sensitive to.
3. **(Optional) Round 2.** Consequential calls only: one short update per seat after reading the other four takes.
4. **Chair.** As a separate step, synthesize as `council-chair` does: **Consensus** · **Disagreements** (table: claim · for / against · why it matters) · **Recommendation** (one ranked pick, confidence, and the evidence that would reverse it) · **Smallest reversible next step** · **Still unresolved**. Weigh seats by argument quality, not length, and add no position no seat raised.
5. **Return** the verdict first and the five takes after it, noting it ran as the single-model chat fallback (seats are less independent than separate subagents).

## Rules

- Keep each seat's Round-1 input identical and independent (blind) to prevent anchoring and groupthink.
- The seats reason only over what you pass them — they have no network, cannot fetch data and don't load CLAUDE.md.
- The chair only reconciles; don't let it introduce a position no seat raised.
- Standing rules are constraints, not opinions: a recommendation that would break one names the row and says so.
- For a routine question, one round + chair is enough; reserve Round 2 for consequential decisions.
- When the owner corrects a council outcome for a reason that should hold next time, apply the `regression-guard` skill to record a `biz/` row (chat: output the row for the owner to paste).
