---
description: "Over-triggering guard: a one-line rename gets no clarify pop-up and no AC list — requirements-gate skips edits that fit one sentence; AskUserQuestion is available but used 0 times."
expected_outcome: "No AskUserQuestion call; reply shows the function returning `total` and has no AC1… list."
tags: [skill-trigger, requirements-gate, over-triggering, smoke]
max_turns: 5
allowed_tools: [Read, Glob, Grep, Skill, AskUserQuestion]
---

Rename the variable `tmp` to `total` in `cart_total()`. The file isn't in this workspace, so here is the function — show me the result.

```python
def cart_total(items):
    tmp = 0
    for item in items:
        tmp += item.price * item.qty
    return tmp
```
