---
name: mcp-server-patterns
description: Build MCP servers with Node/TypeScript SDK — tools, resources, prompts, Zod validation, stdio vs Streamable HTTP. Use when building or reviewing MCP server code; check Context7 or official MCP docs for latest API.
metadata:
  origin: ECC
---

# MCP Server Patterns

The Model Context Protocol (MCP) lets AI assistants call tools, read resources, and use prompts from your server. Use when building or maintaining MCP servers. The SDK API evolves; check Context7 (query-docs for "MCP") or the official MCP docs for current method names and signatures.

## When to Use

Use when: implementing a new MCP server, adding tools or resources, choosing stdio vs HTTP, upgrading the SDK, or debugging MCP registration and transport issues.

## How It Works

### Core concepts

- **Tools**: Actions the model can invoke (e.g. search, run a command). Register with `registerTool()` or `tool()` per SDK version.
- **Resources**: Read-only data the model can fetch (e.g. file contents, API responses). Register with `registerResource()` or `resource()`; handlers typically receive a `uri` argument.
- **Prompts**: Reusable, parameterised prompt templates the client can surface (e.g. in Claude Desktop). Register with `registerPrompt()` or equivalent.
- **Transport**: stdio for local clients (e.g. Claude Desktop); Streamable HTTP preferred for remote (Cursor, cloud); legacy HTTP/SSE for backward compatibility only.

The Node/TypeScript SDK has changed over time — it may expose `tool()` / `resource()` or `registerTool()` / `registerResource()`. Always verify against the current [MCP docs](https://modelcontextprotocol.io) or Context7.

### Connecting with stdio

For local clients, create a stdio transport and pass it to your server’s connect method. The exact API varies by SDK version (constructor vs factory) — see the official MCP docs or query Context7 for "MCP stdio server".

Keep server logic (tools + resources) transport-independent so the entrypoint can plug in stdio or HTTP.

### Remote (Streamable HTTP)

For Cursor, cloud, or other remote clients, use **Streamable HTTP** (single MCP HTTP endpoint per current spec). Support legacy HTTP/SSE only when backward compatibility requires it.

## Examples

### Install and server setup

```bash
npm install @modelcontextprotocol/sdk zod
```

```typescript
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { z } from "zod";

const server = new McpServer({ name: "my-server", version: "1.0.0" });
```

Register tools and resources with the API your SDK version provides: some use `server.tool(name, description, schema, handler)` (positional args), others `server.tool({ name, description, inputSchema }, handler)` or `registerTool()`. Same for resources — include a `uri` in the handler when the API provides it. Check the official MCP docs or Context7 for current `@modelcontextprotocol/sdk` signatures to avoid copy-paste errors.

Validate input with **Zod** (or the SDK’s preferred schema format).

## Best Practices

- **Schema first**: Input schemas for every tool; document parameters and return shape.
- **Errors**: Return structured errors the model can interpret; no raw stack traces.
- **Idempotency**: Prefer idempotent tools so retries are safe.
- **Rate and cost**: For tools calling external APIs, consider rate limits and cost; document in the tool description.
- **Versioning**: Pin SDK version in package.json; check release notes when upgrading.

## Official SDKs and Docs

- **JavaScript/TypeScript**: `@modelcontextprotocol/sdk` (npm). Use Context7 with library name "MCP" for current registration and transport patterns.
- **Go**: Official Go SDK on GitHub (`modelcontextprotocol/go-sdk`).
- **C#**: Official C# SDK for .NET.
