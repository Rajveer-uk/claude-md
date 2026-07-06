---
name: ml-adoption-playbook
description: End-to-end methodology for AI agents and software engineers to add machine learning algorithms to existing non-ML codebases. Covers problem framing, data readiness, architectural decoupling, and baseline model integration.
origin: ECC
---

# ML Adoption Playbook

Adaptive methodology for implementing ML models in existing software projects — bridges traditional SWE and MLOps by structuring how ML is researched, decoupled, trained, and integrated.

## When to Activate

- A user asks to "add ML" or "add an algorithm" to their existing codebase.
- Planning integration of a new model (e.g., recommendation, classification, forecasting) into a non-ML application.
- Structuring a workflow for an agent to build, train, and deploy an ML component adaptively.

## Phase 1: Problem Framing & Feasibility

Establish the "why" and "how" before writing model code.
- **Heuristic Check:** Ask if a simple heuristic (e.g., regex, rule-based sorting) could solve the problem faster. If yes, start there.
- **Metric Definition:** Define the business metric the model should improve (e.g., click-through rate, reduced latency).
- **Mistake Budget:** Define what a "bad" prediction looks like and how the system handles it.

## Phase 2: Data Readiness

ML is useless without clean, accessible data.
- **Audit Data Sources:** Identify where training data lives — live database, static CSV, or API?
- **Data Contract:** Establish an input schema: required features, and behavior when a feature is missing.
- **Leakage Prevention:** Ensure the proposed data split does not leak future information into the training set (e.g., chronological splitting for time-series data).

## Phase 3: Architectural Integration & Decoupling

Do not tightly couple model inference to core business logic.
- **API Boundary:** Place the model behind an API endpoint (e.g., using `fastapi-patterns` or `django-patterns`) or a dedicated service class.
- **Fallback Mechanisms:** Design a default state: on timeout or error, gracefully fall back to a hardcoded rule.
- **Feature Flags:** Wrap the ML inference call in a feature flag for safe rollout and rollback.

## Phase 4: Model Implementation & Training

Structure the code for reproducibility and iteration.
- **Start Simple:** Build a baseline first (e.g., scikit-learn Logistic Regression or a barebones PyTorch linear layer).
- **Reproducibility:** Apply `pytorch-patterns` or similar: fix random seeds, make code device-agnostic, document tensor/array shapes explicitly.
- **Automated Evidence:** Require tests for data transforms and inference schema. Do not accept a model without an evaluation script comparing it against the baseline.

## Phase 5: Handoff to MLOps

With the baseline integrated, shift to continuous operations.
- **Refer to `mle-workflow`:** Guide the user toward experiment tracking, model registries, and drift detection.
- **CI/CD:** Add the model evaluation step to the existing CI pipeline so future commits do not degrade model performance.

## Iterative Agent Workflow

Agents using this playbook should:
1. **Ask clarifying questions** to complete Phase 1 before proposing architectures.
2. **Draft a data contract** in Phase 2 for user approval.
3. **Write the decoupling interface** (API/Service) in Phase 3 *before* the training loop.
4. **Deliver a reproducible script** in Phase 4 that trains the model and saves the artifact.
