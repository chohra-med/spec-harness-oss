---
name: spec-harness-learn
description: Capture a human correction, review finding, bug postmortem or verifier/tester failure as one testable rule. Use when Malik says 'learn this', 'remember this', 'capture this lesson', or a separate acceptance role finds a cause.
---

# spec-harness-learn

Run commands/learn.md: capture raw feedback, propose a testable cause and owner, and record the existing human/reviewer decision. Apply a canonical rule only after approval; mark only affected skill/role bindings stale, refresh those bindings and run the synthesis check. Unsupported or pending proposals stay captured and proposed. Report LEARNED only after reviewed application; otherwise report PENDING.

## Run it
1. **Load the full procedure** — read the command doc and follow it exactly:
   `.claude/commands/spec-harness/learn.md` (this repo) or the spec-harness source `commands/learn.md`.
2. **Agents** — follow this command and project policy for role selection.
3. **Stay inside the 3 pillars** — Memory bank (`.memory/`) · Spec-Driven Development · Harness (ratchet `AGENTS.md` + verifier + learning loop). Read `SPEC-HARNESS.md` for how this repo is wired.

## Non-negotiables
- The ratchet only tightens after a reviewed rule change.
- Nothing is "done" until the separate verifier returns PASS against the applicable goal.
- Every correction or FAIL cause goes through `spec-harness-learn` classification.
- Never scaffold the second-brain vault. Never commit a client repo unless asked.
