---
description: "'Write a blog post about <topic>' routes to the content-writer agent, and the draft carries none of the ai-writing-tells banned phrases."
expected_outcome: "Agent call to marketing:content-writer; reply is the post itself, on topic, with no banned phrase."
tags: [routing, banned-phrases]
max_turns: 20
timeout_seconds: 900
allowed_tools: [Read, Glob, Grep, Skill, Agent]
---

Write a blog post about how small accounting firms can shorten their month-end close. About 600 words, for firm owners. Reply with only the finished post — no notes before or after it.
