---
type: tool_order
before:
  tool: Agent
  input_match: '"subagent_type"\s*:\s*"(?:council:)?council-out-of-the-box"'
after:
  tool: Agent
  input_match: '"subagent_type"\s*:\s*"(?:council:)?council-chair"'
---
