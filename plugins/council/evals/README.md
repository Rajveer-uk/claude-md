# council — eval suite (regression guard for the pack)

**Guards:** `/council:council <question>` (the plugin's full name for `/council`) fans out to all five seats before `council-chair` (five `tool_order` graders), no seat dispatch fails with "Agent type … not found", and the reply carries the chair's verdict. One directory per case: `prompt.md` + `graders/*.md` ([schema](https://code.claude.com/docs/en/plugin-evals)).

**When:** only before a `plugins/council` version bump, or after editing the `council` skill or a seat agent. Inert otherwise (0 session tokens).

**Run** (repo root): `claude plugin eval plugins/council --threshold 0.8 --max-cost-usd 10` (no interactive terminal, e.g. CI/scripts: add `--trust-plugin`)
- Cheap pass: add `--runs 1 --ablation none` (the no-plugin arm only shows an unknown command).
- CI: add `--trust-plugin --json results.json --model sonnet --no-publish`. Exit 0 pass · 1 below threshold · 2 cost ceiling hit (partial).

**Cost:** each run spawns six subagents (the chair on opus) — the most expensive suite in the repo; 3 runs with + 3 without the plugin by default. `--max-cost-usd` caps the list-price estimate; raise it if the run exits 2.

**Platform:** no case grants a shell. A shell-granting case (`--allow-tools Bash`) needs Linux (`bubblewrap` + `socat`), macOS, WSL2 or CI — native Windows lacks a sandbox backend.

Results go to `evals/results/` (gitignored).
