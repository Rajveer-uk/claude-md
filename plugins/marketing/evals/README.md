# marketing — eval suite (regression guard for the pack)

**Guards:** "write a blog post about <topic>" routes to `content-writer` · drafts and edits carry none of the `ai-writing-tells` banned phrases (`regex` `not_contains`, case-insensitive) · `content-researcher` reaches the plugin-scoped Tavily tool `mcp__plugin_marketing_tavily__tavily_search` — the case that catches a wrong MCP tool name in the agent's `tools:`. No keys needed: `mocks/tavily/tavily_search.md` answers the calls; real MCP servers start only with `--allow-real-servers` or `--mocks off`. Schema: [plugin evals](https://code.claude.com/docs/en/plugin-evals).

**When:** only before a `plugins/marketing` version bump, or after editing an agent/skill `description`, a `tools:` list or `.mcp.json`. Inert otherwise (0 session tokens).

**Run** (repo root): `claude plugin eval plugins/marketing --threshold 0.8 --max-cost-usd 5` (no interactive terminal, e.g. CI/scripts: add `--trust-plugin`)
- Cheap pass: add `--tag smoke --runs 1 --ablation none` · one case: `--case <dir-name>`.
- CI: add `--trust-plugin --json results.json --model sonnet --no-publish`. Exit 0 pass · 1 below threshold · 2 cost ceiling hit (partial).

**Cost:** real model usage — each case runs 3× with and 3× without the plugin; routing cases spawn subagents. `--max-cost-usd` caps the list-price estimate; raise it if the run exits 2.

**Platform:** no case grants a shell. A shell-granting case (`--allow-tools Bash`) needs Linux (`bubblewrap` + `socat`), macOS, WSL2 or CI — native Windows lacks a sandbox backend.

**Maintain:** when a phrase joins `ai-writing-tells` or `brand/banned-phrases.txt`, add it to the `pattern` alternation in every `graders/no-banned-phrases.md` (JavaScript regex; case-insensitivity via `flags: i`). Results go to `evals/results/` (gitignored).
