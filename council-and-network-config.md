# Council & network connector — config and security model

Two optional add-on packs, shipped as plugins (`council`, `marketing`). The default **core install has no network tools on any agent**; network appears only if you install the `marketing` plugin, and only on the two researchers named below. Install both packs from the marketplace — see [`setup.md`](setup.md) §G.

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

**How it runs** (the `/council` skill, `plugins/council/skills/council/SKILL.md`): the **main session** is the convener (subagents can't spawn subagents). It fans the question out to the five seats in parallel (blind/independent), then hands all takes to `council-chair` for synthesis. Design follows Karpathy's `llm-council` (independent → synthesize) plus persona-council patterns (polarity pairs, "lead with unresolved questions").

**Install:** `/plugin install council@claude-md-packs` — the pack bundles the 6 `council-*.md` agents and the `/council` skill. Then run `/council <your question>`. (See [`setup.md`](setup.md) §G for adding the marketplace.)

---

## 2. Network connector (opt-in, MCP-only, scoped to 2 agents)

Live data is granted to **only** `content-researcher` (web, via Tavily) and `seo-rank-monitor` (SEO, via DataForSEO), both shipped inside the optional `marketing` plugin. Every other agent — all 23 core engineering, the 6 council seats, and the other 5 marketing writers — keeps **zero** network, and a core-only install has no network surface at all. The two servers are declared at **plugin scope** in `plugins/marketing/.mcp.json`, so they connect only when the plugin is installed and one of those agents runs, and are invisible to every other agent and the main session.

### Why it's safe

- **Per-agent scoping via `tools:`.** The Tavily/DataForSEO servers are declared once at plugin scope (`plugins/marketing/.mcp.json`), but only the two agents that list the `mcp__tavily__*` / `mcp__dataforseo__*` tools in their frontmatter `tools:` can actually invoke them — the other five marketing agents and every base/council agent cannot. (Inline per-agent `mcpServers` is ignored inside a plugin, so the `tools:` allowlist is what scopes access. In a manual/classic install, the retained inline `mcpServers` blocks do the same job and network is still never inherited.)
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
3. **Install the `marketing` plugin** — `/plugin install marketing@claude-md-packs`. The two researchers' MCP servers are declared at plugin scope in `plugins/marketing/.mcp.json` (see [`setup.md`](setup.md) §G).
4. **Verify** with `/mcp` in a session — confirm the servers connect and check the **exact** tool names (the `tools:` lists use `mcp__tavily__*` / `mcp__dataforseo__*`; adjust if your server version exposes different names).

### Notes & residuals

- **Residual read+network surface (prompt-mitigated):** each network agent holds Read + a network tool, so it could in principle put a readable (non-deny-listed) file's contents into a search argument and send it out. This is blocked only by the prompt guardrails (no file contents in queries; fetched results treated as untrusted) and the secret deny-list (crown-jewel files are unreadable) — there is no mechanical inspection of MCP arguments. Treat whatever these two agents can read as potentially externally visible, and keep the MCP tools on **"ask"** (don't allowlist them). `content-researcher` ships with `tavily_search` **only** — the arbitrary-URL `tavily_extract` is deliberately omitted to remove the single-hop fetch/exfil primitive.
- **Supply chain:** the inline servers launch via `npx -y` (auto-install), fetching an npm package on first run with the agent's env (including your API keys) and full local privileges. **Both are unpinned** — `tavily-mcp@latest` and the bare `dataforseo-mcp-server` (a bare name also resolves to *latest*). **Pin both to an exact, reviewed version** (`tavily-mcp@x.y.z`, `dataforseo-mcp-server@x.y.z`) — or pre-install reviewed versions into a local `node_modules` — before relying on them. Only install these two agents if you want the connector.
- **Env interpolation** (`${VAR}`) is confirmed for `.mcp.json` — which is exactly what the `marketing` plugin uses (`plugins/marketing/.mcp.json`) — and very likely works in agent frontmatter too; if a key doesn't resolve, move the server into global `~/.claude.json` and reference it by name.
- **Auto-approve (optional):** to stop per-call prompts on the read-only search tools, add them to `permissions.allow` (e.g. `mcp__tavily__tavily_search`). Never allow any write/post/crawl-mutation MCP tool. Leaving them on "ask" (the default) is safer.
- **No-key fallback (not recommended):** removing `WebFetch`/`WebSearch` from the `settings.json` deny re-enables those built-ins **session-wide — for all 36 agents and the main session**, not just one agent. That discards the whole no-network containment, not merely "per-agent scoping." Prefer the MCP path. If you genuinely need a no-key route, keep the global deny in place and instead scope a web-search MCP into just `content-researcher`.
- **Inline `mcpServers` is ignored inside a plugin** — a plugin's subagents don't read per-agent `mcpServers` frontmatter. That's why the `marketing` plugin declares Tavily/DataForSEO at **plugin scope** in `plugins/marketing/.mcp.json` instead. The two agents keep their inline blocks as well, so they still work if you copy them out for a classic, non-plugin install into `~/.claude/agents/`.
