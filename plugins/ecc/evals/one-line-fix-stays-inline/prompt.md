---
description: "Over-triggering guard: a one-line Python fix is answered inline; the Agent tool is available but used 0 times even though the ecc reviewers say 'Use proactively'."
expected_outcome: "No Agent call; the corrected function uses range(len(items)) or iterates the list directly."
tags: [routing, ecc, over-triggering, smoke]
max_turns: 5
allowed_tools: [Read, Glob, Grep, Agent]
---

Fix the off-by-one error in this function and show me the corrected version. The file isn't in this workspace:

```python
def last_prices(items):
    out = []
    for i in range(len(items) - 1):
        out.append(items[i].price)
    return out
```
