---
description: "content-researcher reaches the plugin-scoped Tavily tool (mcp__plugin_marketing_tavily__tavily_search) through the MCP mock — no API key. Fails if the agent's tools list uses a name the plugin install doesn't expose."
expected_outcome: "Agent call to marketing:content-researcher; a mocked tavily_search call; the brief cites the mock's example.* eval-mock URLs."
tags: [mcp, routing]
max_turns: 15
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
---

This is a tooling test: the search backend is a stub that returns placeholder `example.*` URLs. Use the content-researcher agent to find three sources on how small accounting firms are automating accounts-payable invoice processing, and give me a short research brief that lists each result's URL exactly as the search tool returned it (label them as stub results — don't present them as real sources). Let the agent do all the searching — don't search yourself. If it reports that it has no search tool, stop and tell me that instead.
