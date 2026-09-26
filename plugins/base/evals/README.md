# base — eval suite (regression guard for the pack)

**Guards:** `regression-guard` fires on a bug fix and on an owner correction (with a test + ledger row) · `caveman` on "be terse" · `work-quality-checker` on "review this email" (verdict line) · a trivial question uses the Agent tool 0 times · a 3-part task routes to subagents. One directory per case: `prompt.md` + `graders/*.md` ([schema](https://code.claude.com/docs/en/plugin-evals)).

**When:** only before a `plugins/base` version bump, or after editing a skill/agent `description` or `hooks/hooks.json`. Inert otherwise — `evals/` isn't a plugin component (0 session tokens).

**Run** (repo root): `claude plugin eval plugins/base --threshold 0.8 --max-cost-usd 10`
- Cheap pass: add `--tag smoke --runs 1 --ablation none` · one case: `--case <dir-name>`.
- CI: add `--trust-plugin --json results.json --model sonnet --no-publish`. Exit 0 pass · 1 below threshold · 2 cost ceiling hit (partial).

**Cost:** every run is real model usage on your account — each case runs 3× with and 3× without the plugin; `multi-part-task-uses-subagents` spawns subagents and costs most. `--max-cost-usd` caps the list-price estimate; raise it if the run exits 2.

**Platform:** no case grants a shell, so the suite runs wherever Claude Code does. A shell-granting case (`--allow-tools Bash`) needs Linux (install `bubblewrap` + `socat`), macOS, WSL2 or CI — native Windows lacks a sandbox backend.

**Reading a fail:** `tool_used: Skill` graders are unscored indicators in a two-arm run; if one fails, the skill's `description` stopped triggering — fix the description, not the case. Results go to `evals/results/` (gitignored).
