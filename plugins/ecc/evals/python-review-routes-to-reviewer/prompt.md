---
description: "Routing guard: when a Python review is delegated, the ecc python-reviewer agent is picked (description: 'Use proactively for Python code changes'), not a general-purpose subagent. A small review with no delegation asked for is answered inline under either wording (measured 2026-09-27), so the prompt asks for a reviewer subagent."
expected_outcome: "An Agent call to python-reviewer; the reply flags the mutable default argument and the SQL built by string formatting."
tags: [routing, ecc, smoke]
max_turns: 12
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Agent]
---

Get me an independent review of this change to our Python service from a reviewer subagent before I merge it. The repo isn't in this workspace, so here is the new code:

```python
import sqlite3


def add_tag(tag, tags=[]):
    tags.append(tag)
    return tags


def find_user(conn: sqlite3.Connection, name: str):
    cur = conn.execute(f"SELECT id, email FROM users WHERE name = '{name}'")
    return cur.fetchone()
```
