---
description: "/council fans the question out to all five seats before the chair synthesizes (tool_order), with no failed seat dispatch, and returns the chair's verdict."
expected_outcome: "Five seat Agent calls, each before the first council-chair call; no 'Agent type ... not found' error; reply includes the chair's smallest reversible next step."
tags: [routing, tool-order]
max_turns: 40
timeout_seconds: 1500
allowed_tools: [Read, Glob, Grep, Skill, Agent]
---

/council:council Should our six-person team split our single Laravel monolith into microservices this quarter? Context: one product, about 40k lines of code, weekly deploys that take 20 minutes, no dedicated ops person, and a customer-facing launch due in ten weeks.
