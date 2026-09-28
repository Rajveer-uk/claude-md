---
description: "Over-delegation guard (token rule 1): a one-line factual question is answered inline; the Agent tool is available but used 0 times."
expected_outcome: "No Agent call; a direct answer that mentions reassignment."
tags: [routing, over-delegation, smoke]
max_turns: 5
allowed_tools: [Read, Glob, Grep, Skill, Agent]
---

What's the difference between `let` and `const` in JavaScript?
