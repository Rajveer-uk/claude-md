---
description: "Delegation guard (token rule 2): a task with 3 independent parts routes to subagents (Agent used at least once), ideally base pack specialists."
expected_outcome: "At least one Agent call (a base: specialist in the with-plugin arm); reply contains the schema, the API contract and the webhook checklist."
tags: [routing, subagents]
max_turns: 25
timeout_seconds: 1200
allowed_tools: [Read, Glob, Grep, Skill, Agent]
---

We're starting a small invoicing service: PostgreSQL plus a JSON REST API. No code exists yet. I need three deliverables, and none of them depends on the others:

1. A PostgreSQL schema for customers, invoices, invoice line items and payments — keys, constraints and the indexes you'd add.
2. A REST API contract for creating an invoice, listing a customer's invoices (paginated) and recording a payment — endpoints, request/response JSON and error codes.
3. A security checklist for the inbound payment-provider webhook endpoint — signature verification, replay protection, idempotency and secret handling.

Return all three in your reply; don't write files.
