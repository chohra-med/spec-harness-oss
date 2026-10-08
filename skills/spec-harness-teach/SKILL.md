---
name: spec-harness-teach
description: Explain a system to a human as one self-contained interactive page: what it is, why it is built this way and how to use it, with diagrams and a learning ladder (principle, theory, anchor, example, use here, real code). Use when the user says 'explain this to me', 'teach me how this works', 'make a learning page', 'onboard someone to this', or wants to understand a codebase, a feature or a decision.
---

# spec-harness-teach

Run commands/teach.md: gather the real source, decide the reader, lay out the sections, build one offline HTML file, then verify it in a real browser at two widths, click every control and have a fresh context check every excerpt and number. Never invent an excerpt or a measurement. Never edit application source.

## Run it
1. **Load the full procedure** — read the command doc and follow it exactly:
   `.claude/commands/spec-harness/teach.md` (this repo) or the spec-harness source `commands/teach.md`.
3. **Stay inside the 3 pillars** — Memory bank (`.memory/`) · Spec-Driven Development · Harness (ratchet `AGENTS.md` + verifier + learning loop). Read `SPEC-HARNESS.md` for how this repo is wired.

## Non-negotiables
- The ratchet only tightens after a reviewed rule change.
- Nothing is "done" until the separate verifier returns PASS against the applicable goal.
- Every correction or FAIL cause goes through `spec-harness-learn` classification.
- Never commit, push or merge unless asked.
