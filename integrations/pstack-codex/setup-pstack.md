---
name: setup-pstack
description: Configure pstack roles using models and reasoning settings actually available to Codex. Use when setting up pstack or changing its role assignments.
---

# Set up pstack for Codex

Read [the Codex adapter](../../codex.md) first. Resolve the plugin root from this file, not from a hardcoded installation path.

1. Read the current dedicated models.json described in the adapter, if present. Obtain supported child model and reasoning values from the actual spawn schema or supported model listing; if unavailable offer inheritance only. Do not equate a parent model listing with child override support.
2. Show the current role assignments. Start unconfigured scalar roles with one inherited seat and panel roles with two inherited seats as described in the adapter. Explain that repeated use of one model is not model diversity. Ask which available roles/models/reasoning levels to change and confirm the resulting assignments. Preserve unrelated role choices.
3. Write the proposed configuration and, for explicit overrides, observed capabilities into task-owned verification files. Call `<pstack>/scripts/configure.py --input <proposed.json> --capabilities <observed.json> --output <dedicated models.json>`. For inherited values, capabilities are optional. Never write `.cursor/rules`, global Codex configuration, or AGENTS.md.
4. Read back the saved configuration and report its absolute path and role choices. Each subsequent pstack invocation explicitly reads this file, including children. If a setting later becomes unavailable, stop that role with the reason.
5. Check the project for an existing app verification harness or verify-* skill. If absent, offer once to run the bundled create-verification-skill. Likewise offer create-formal-verification-skill only if no relevant formal verification harness exists. Do not generate either without acceptance.
