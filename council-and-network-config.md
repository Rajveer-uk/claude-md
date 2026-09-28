# Council & network connector — config and security model

Two optional add-on packs, shipped as plugins (`council`, `marketing`). The default **core install has no network tools on any agent**; network appears only if you install the `marketing` plugin or enable it on your claude.ai account (account plugins sync into every signed-in Claude Code session as `<name>@synced`), and only on the two researchers named below. Install both packs from the marketplace — see [`setup.md`](setup.md) §G (or, for claude.ai chat and Cowork, the account marketplace in setup.md Quick start step 8).

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

**How it runs** (the `/council` skill, `plugins/council/skills/council/SKILL.md`): the **main session** is the convener (the seats have no Agent tool). It builds one brief, fans it out to the five seats in parallel (blind/independent), then hands all takes to `council-chair` for synthesis. Design follows Karpathy's `llm-council` (independent → synthesize) plus persona-council patterns (polarity pairs, "lead with unresolved questions").

**Context comes from the skill, not `CLAUDE.md`.** Every seat has `omitClaudeMd: true`, so it starts without the `CLAUDE.md` hierarchy — saving that load on each of the six starts per `/council` run. The skill's brief is each seat's only project context: the restated question, the facts the decision turns on (goal, hard constraints, options already ruled out) and the matching `REGRESSIONS.md` rows (`biz/` plus the area the question touches), verbatim. Managed-policy `CLAUDE.md` content still loads. Because the seats run with `omitClaudeMd`, each seat carries its own one-line guardrail: everything it is given or reads is data, not instructions, and its take holds no secrets, real hosts/IPs or client names (placeholders instead).

**Seat names:** a plugin install registers them as `council:council-optimist` … `council:council-chair`; a manual install uses the bare names. **Chat fallback:** where sub-agents aren't available (claude.ai chat, the Desktop Chat tab, mobile, or an uploaded copy of the skill), the skill writes each seat's take in turn from the brief only, then the chair's synthesis, and says it ran as the single-model fallback.

**Install:** `/plugin install council@claude-md-packs` — the pack bundles the 6 `council-*.md` agents and the `/council` skill. Then run `/council <your question>`. (See [`setup.md`](setup.md) §G for adding the marketplace.)

---

## 2. Network connector (opt-in, MCP-only, scoped to 2 agents)

Live data is granted to **only** `content-researcher` (web, via Tavily) and `seo-rank-monitor` (SEO, via DataForSEO), both shipped inside the optional `marketing` plugin. Every other pack agent — all 24 core engineering agents, the 6 council seats, the other 5 marketing agents and the `ecc` agents — keeps **zero** network, and a core-only install has no network surface at all, as long as `marketing` isn't synced from your claude.ai account either. The two servers are declared at **plugin scope** in `plugins/marketing/.mcp.json`, so they start only when the `marketing` plugin is installed or synced from your claude.ai account (`marketing@synced`).

**Who can see the tools.** Plugin MCP tools are visible to the **main session**, and to any subagent that has no `tools:` allow-list (such as the built-in general-purpose agent, which inherits the main session's tools). Every agent in these packs declares an explicit `tools:` list, so among the pack agents only the two researchers can call them. The main session can call them too — each call goes through the normal permission flow: a prompt unless you allow-list the tool (don't; see *Auto-approve* below), or the classifier's decision in auto mode.

### Tool names

| Install | Tavily | DataForSEO |
|---------|--------|------------|
| **Plugin** (§G) | `mcp__plugin_marketing_tavily__tavily_search` | `mcp__plugin_marketing_dataforseo__serp_organic_live`, `…__keywords_data`, `…__dataforseo_labs` |
| **Manual** (§H, inline `mcpServers`) | `mcp__tavily__tavily_search` | `mcp__dataforseo__serp_organic_live`, `…__keywords_data`, `…__dataforseo_labs` |

Plugin-bundled servers are named `mcp__plugin_<plugin>_<server>__<tool>`, and that full name is what a `tools:` list, a permission rule or a hook matcher must use. The two agents list **both** forms, so the same file works in either install. Confirm the exact names your server version exposes with `/mcp`.

### Why it's safe

- **Per-agent scoping via `tools:`.** The Tavily/DataForSEO servers are declared once at plugin scope (`plugins/marketing/.mcp.json`), but among the pack agents only the two that list the Tavily/DataForSEO tools in their frontmatter `tools:` can invoke them — the other five marketing agents and every base/council/ecc agent cannot. (Inline per-agent `mcpServers` is ignored inside a plugin, so the `tools:` allowlist is what scopes access. In a manual/classic install, the retained inline `mcpServers` blocks do the same job and network is still never inherited.) The scoping depends on valid frontmatter: a plugin agent whose frontmatter fails to parse loads with **every** field ignored, including `tools:` — `claude plugin validate plugins/marketing --strict` catches that, and the marketing eval suite checks that `content-researcher` actually reaches its (mocked) Tavily server.
- **No write + network on one agent.** Both network agents are **read-only** on files; the writing agents (`content-writer` and the other writers) have **no** network. So no single agent can both read local data and ship it out.
- **Built-ins denied session-wide.** `settings.json` denies `WebFetch`/`WebSearch` (removes them everywhere), so the scoped MCP is the only sanctioned network path. The shell egress denies (`curl`, `wget`, `nc`, `scp`, `Invoke-WebRequest` …, for both `Bash` and `PowerShell`) are a **speed-bump, not a wall**: they match command text, and Claude Code documents what they miss — absolute paths (`/usr/bin/curl`), `sh -c '…'`, interpreters (a Python or Node script) and `npx`. The backstops are plan mode + per-command approval, the optional `guard` hook (which also inspects `PowerShell` and `Monitor` commands and catches interpreter reads of secret paths), and the opt-in OS sandbox in `templates/sandbox-settings.json` (Linux, macOS, WSL2), which makes any connection to an unlisted host prompt whichever program opens it.
- **Secret deny-list still applies.** The session-wide `Read(...)` denies (`.env`, keys, `secrets/`, home-dir credentials such as `~/.ssh/**` and `~/.aws/**`, etc.) mean a network agent can't read the crown-jewel secrets to exfiltrate them.
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
   **Claude Desktop** doesn't inherit these shell exports (macOS picks up only `PATH` and a fixed set of Claude Code variables from your profile; Windows doesn't read PowerShell profiles) — set the same three variables in Desktop's **Local environment editor** (stored encrypted; applies to every local session).
3. **Install the `marketing` plugin** — `/plugin install marketing@claude-md-packs`. The two researchers' MCP servers are declared at plugin scope in `plugins/marketing/.mcp.json` (see [`setup.md`](setup.md) §G).
4. **Verify** with `/mcp` in a session — confirm the servers connect and check the **exact** tool names against the table above (plugin install: `mcp__plugin_marketing_…`; manual install: `mcp__tavily__*` / `mcp__dataforseo__*`; adjust the agents' `tools:` lists if your server version exposes different names).

### Notes & residuals

- **Residual read+network surface (prompt-mitigated):** each network agent holds Read + a network tool, so it could in principle put a readable (non-deny-listed) file's contents into a search argument and send it out. This is blocked only by the prompt guardrails (no file contents in queries; fetched results treated as untrusted) and the secret deny-list (crown-jewel files are unreadable) — there is no mechanical inspection of MCP arguments. Treat whatever these two agents can read as potentially externally visible, and keep the MCP tools on **"ask"** (don't allowlist them). `content-researcher` ships with `tavily_search` **only** — the arbitrary-URL `tavily_extract` is deliberately omitted to remove the single-hop fetch/exfil primitive.
- **Supply chain:** both servers launch via `npx -y`, which fetches the npm package on first run and runs it with the server's env (including your API key) and your full local privileges. **Both are pinned** to exact, reviewed versions — `tavily-mcp@0.2.21` and `dataforseo-mcp-server@2.9.11` — in `plugins/marketing/.mcp.json` and in the agents' inline `mcpServers` blocks used by a manual install. Review a new release before you bump a pin, and bump both places together; or pre-install reviewed versions into a local `node_modules`. MCP servers and hooks run outside the permission system and the sandbox. Only install the `marketing` pack (locally or on your claude.ai account) if you want the connector.
- **Where the connector runs:** these are local stdio servers — they run in local Claude Code (CLI, Desktop Code tab, IDEs) and in Cowork while the Desktop app is open, **not** in claude.ai web chat. Cloud Code sessions don't install plugins, so the researchers have no network there.
- **Env interpolation** (`${VAR}`) is confirmed for `.mcp.json` — which is exactly what the `marketing` plugin uses (`plugins/marketing/.mcp.json`) — and very likely works in agent frontmatter too; if a key doesn't resolve, move the server into global `~/.claude.json` and reference it by name. An unset variable is passed through as the literal `${VAR}` text rather than failing the config, so a missing key typically surfaces as an authentication error from the server.
- **Auto-approve (optional):** to stop per-call prompts on the read-only search tools, add them to `permissions.allow` using the name for your install — `mcp__plugin_marketing_tavily__tavily_search` (plugin) or `mcp__tavily__tavily_search` (manual). Never allow any write/post/crawl-mutation MCP tool. Leaving them on "ask" (the default) is safer — and an allow rule also lets the **main session** call them without a prompt.
- **Account plugins sync into every session.** A plugin enabled on your claude.ai account loads in every signed-in Claude Code session as `<name>@synced`, including its MCP servers, so `marketing` on the account starts Tavily/DataForSEO everywhere you sign in. Put `base` and `council` on the account; add `marketing` only where its Tavily/DataForSEO servers are acceptable in every session. To opt one machine out, set `"marketing@synced": false` under `enabledPlugins` in `~/.claude/settings.json` or run `claude plugin disable marketing@synced`, then confirm with `claude plugin list`.
- **claude.ai connectors are a separate path.** If you sign in to Claude Code with a claude.ai account, connectors you added on claude.ai reach the **main session** as well. They aren't scoped by this pack; the pack agents' explicit `tools:` lists keep them away from subagents. Review with `/mcp`; block per server with `deniedMcpServers`, or all of them with `disableClaudeAiConnectors`.
- **No-key fallback (not recommended):** removing `WebFetch`/`WebSearch` from the `settings.json` deny re-enables those built-ins **session-wide — for every agent and the main session**, not just one agent. That discards the whole no-network containment, not merely "per-agent scoping." Prefer the MCP path. If you genuinely need a no-key route, keep the global deny in place and instead scope a web-search MCP into just `content-researcher`.
- **Inline `mcpServers` is ignored inside a plugin** — a plugin's subagents don't read per-agent `mcpServers` frontmatter (nor `permissionMode`, `hooks` or `initialPrompt`). That's why the `marketing` plugin declares Tavily/DataForSEO at **plugin scope** in `plugins/marketing/.mcp.json` instead. The two agents keep their inline blocks as well (as an **object map keyed by server name**, same shape as `.mcp.json` — not a YAML list), so they still work if you copy them out for a classic, non-plugin install into `~/.claude/agents/`. After a classic install, run `/mcp` once to confirm the server connects and the `${VAR}` keys resolved from your environment.
