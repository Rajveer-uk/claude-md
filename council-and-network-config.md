# Council & network connector — config and security model

Two optional additions to the strict config. The default posture (no agent has network tools) is preserved for **all** agents except the two named marketing researchers below.

---

## 1. The LLM council

Six pure-reasoner seats (no network, no `Agent` tool, `Read/Grep/Glob` only) plus a one-command runner.

| Seat | Model | Role |
|------|-------|------|
| `council-optimist` | sonnet | best-case / upside + conditions for success |
| `council-pessimist` | sonnet | failure pre-mortem, tail risks + mitigations |
| `council-out-of-the-box` | opus | reframes the question, lateral alternatives |
| `council-skeptic` | sonnet | devil's advocate; known vs assumed vs hoped |
| `council-pragmatist` | sonnet | real constraints; smallest reversible step |
| `council-chair` | opus | reconciles the takes into one verdict (runs last) |

**How it runs** (the `/council` skill, `.claude/skills/council/SKILL.md`): the **main session** is the convener (subagents can't spawn subagents). It fans the question out to the five seats in parallel (blind/independent), then hands all takes to `council-chair` for synthesis. Design follows Karpathy's `llm-council` (independent → synthesize) plus persona-council patterns (polarity pairs, "lead with unresolved questions").

**Install:** copy the 6 `council-*.md` into `~/.claude/agents/`, and the skill to `~/.claude/skills/council/SKILL.md`. Then run `/council <your question>`.

---

## 2. Network connector (opt-in, MCP-only, scoped to 2 agents)

Live data is granted to **only** `content-researcher` (web, via Tavily) and `seo-rank-monitor` (SEO, via DataForSEO). Every other agent — all 22 engineering, the 6 council seats, and the other marketing writers — keeps **zero** network. The connector is declared **inline in each agent's frontmatter**, so the MCP server is connected only while that agent runs and is invisible to the other agents and the main session.

### Why it's safe

- **Per-agent scoping.** Network is never inherited — only the two agents with an inline `mcpServers` block can reach it.
- **No write + network on one agent.** Both network agents are **read-only** on files; the writing agent (`content-writer`) has **no** network. So no single agent can both read local data and ship it out.
- **Built-ins denied session-wide.** `settings.json` denies `WebFetch`/`WebSearch` (removes them everywhere), so the scoped MCP is the only sanctioned network path — and `Bash(curl/wget/...)` is already denied, so the allowlist can't be bypassed by a shell.
- **Secret deny-list still applies.** The session-wide `Read(...)` denies (`.env`, keys, `secrets/`, etc.) mean a network agent literally cannot read the crown-jewel secrets to exfiltrate them.
- **Untrusted fetched content.** Both agents treat web/SERP results as data, never as instructions (prompt-injection defense).

### Setup

1. **Get keys:** a [Tavily](https://tavily.com) API key; a [DataForSEO](https://dataforseo.com) login. (Optional: Google Search Console via the `mcp-gsc` server for first-party metrics.)
2. **Set them in your environment / secret store** (never inline in the committed files):
   ```powershell
   setx TAVILY_API_KEY "<your-key>"            # Windows
   setx DATAFORSEO_USERNAME "<login>"
   setx DATAFORSEO_PASSWORD "<password>"
   ```
   ```bash
   export TAVILY_API_KEY="<your-key>"          # Linux/macOS (add to your shell profile)
   export DATAFORSEO_USERNAME="<login>"
   export DATAFORSEO_PASSWORD="<password>"
   ```
3. **Install the two agents** into `~/.claude/agents/` (they carry the inline `mcpServers` blocks).
4. **Verify** with `/mcp` in a session — confirm the servers connect and check the **exact** tool names (the `tools:` lists use `mcp__tavily__*` / `mcp__dataforseo__*`; adjust if your server version exposes different names).

### Notes & residuals

- **Residual read+network surface (prompt-mitigated):** each network agent holds Read + a network tool, so it could in principle put a readable (non-deny-listed) file's contents into a search argument and send it out. This is blocked only by the prompt guardrails (no file contents in queries; fetched results treated as untrusted) and the secret deny-list (crown-jewel files are unreadable) — there is no mechanical inspection of MCP arguments. Treat whatever these two agents can read as potentially externally visible, and keep the MCP tools on **"ask"** (don't allowlist them). `content-researcher` ships with `tavily_search` **only** — the arbitrary-URL `tavily_extract` is deliberately omitted to remove the single-hop fetch/exfil primitive.
- **Supply chain:** the inline servers launch via `npx -y` (auto-install), fetching an npm package on first run with the agent's env (including your API keys) and full local privileges. **Both are unpinned** — `tavily-mcp@latest` and the bare `dataforseo-mcp-server` (a bare name also resolves to *latest*). **Pin both to an exact, reviewed version** (`tavily-mcp@x.y.z`, `dataforseo-mcp-server@x.y.z`) — or pre-install reviewed versions into a local `node_modules` — before relying on them. Only install these two agents if you want the connector.
- **Frontmatter env interpolation** (`${VAR}`) is confirmed for `.mcp.json` and very likely works in frontmatter; if a key doesn't resolve, move the server to global `~/.claude.json` and reference it by name from the agent's `mcpServers`.
- **Auto-approve (optional):** to stop per-call prompts on the read-only search tools, add them to `permissions.allow` (e.g. `mcp__tavily__tavily_search`). Never allow any write/post/crawl-mutation MCP tool. Leaving them on "ask" (the default) is safer.
- **No-key fallback (not recommended):** removing `WebFetch`/`WebSearch` from the `settings.json` deny re-enables those built-ins **session-wide — for all 35 agents and the main session**, not just one agent. That discards the whole no-network containment, not merely "per-agent scoping." Prefer the MCP path. If you genuinely need a no-key route, keep the global deny in place and instead scope a web-search MCP into just `content-researcher`.
- Keep these agents **out of plugins** — plugin subagents ignore `mcpServers`.
