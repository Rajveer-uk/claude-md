# ecc — eval suite (routing guard for the pack)

**Guards:** a Python review request still routes to `python-reviewer` after its description changed from "MUST BE USED" to "Use proactively" (1.1.2) · a one-line Python fix stays inline (the Agent tool is used 0 times), so the reviewers don't over-trigger on trivial edits. One directory per case: `prompt.md` + `graders/*.md` (same schema as `plugins/base/evals/`).

**When:** only before an `ecc` version bump, or after editing an agent `description`. Inert otherwise — `evals/` isn't a plugin component (0 session tokens).

**Run** (repo root; ecc adds ≈15k always-on tokens per run, so keep it small): `claude plugin eval plugins/ecc --ablation none --runs 1 --max-cost-usd 2 --no-publish` (no interactive terminal: add `--trust-plugin`). Results go to `evals/results/` (gitignored).
