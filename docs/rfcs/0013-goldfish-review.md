# RFC 0013: Goldfish review of the plan, gate briefs in their own file, and a fixed dispatch

Status: proposal, implemented on this branch for review.

## Problem

The gates are fresh contexts by rule ("Independence never bends"), but three paths still let the
orchestrator's view reach them.

- **The dispatch message.** A client composes a prompt when it starts a subagent. A summary or a hint
  in that prompt carries the orchestrator's reasoning into the gate that is meant to check it.
- **The briefs sit inside `plan.md`.** The reviewer's Pass 1 is blind to `## Gate briefs` only because
  it skips one section of a file it must read. Nothing at file level keeps the brief away.
- **No fresh read of the plan before code.** The planner, Grill Me and the owner's approval all sit on
  the side that wrote the plan. A plan with an undefined term, a missing caller, a goal line no task
  covers or a helper that already exists reaches the implementer without a fresh reader.

The elephant-goldfish model (EGM, Apache-2.0; its project states it is not an official Google product) names the
split: one long session holds the context and writes the design (the elephant), and fresh subagents
with no history review it (goldfish). Its rule: "a review in the same context is not a Goldfish review".
This RFC adapts the idea to the existing `/sdd` roles. It copies no EGM code or skill text.

## Proposal

1. **Gate briefs in their own file.** For LITE and FULL the briefs (`### Tester brief`,
   `### Reviewer brief`) move to `specs/<feature>/gate-briefs.md`. `plan.md` keeps `## Gate briefs` as
   one line with that path and its SHA-256. The checkpoint already binds the `plan.md` bytes
   (`plan_sha256` in the run state), so the approved plan now binds the briefs too, with no code change:
   a brief edit changes its hash and needs a new approval. The orchestrator compares the file's hash
   with that line before each gate dispatch that uses a brief, and the tester and the reviewer's Pass 2
   check it again; a mismatch keeps the gate PENDING (`PENDING: brief changed after approval`). Pass 1
   of the reviewer does not open `gate-briefs.md` and reads the diff without it and without `gates/`.
   Because Grep, Glob and Bash get past any path rule, every Pass 1 search and every goldfish grep covers
   source and tests only and excludes `specs/`, `.spec-harness/` and `.memory/`.
2. **A fixed dispatch template.** Every gate and the plan goldfish is dispatched only as a named role
   subagent in a new context: never a fork, and never a resumed or continued agent. One exception: the
   reviewer is one subagent with two dispatches. It is dispatched with `pass: 1`, does Pass 1 only,
   returns it and stops; the orchestrator copies that return into `gates/reviewer.md` and sends the
   filled `pass: 2` template (with any concerns) to the same reviewer (in Claude Code: `SendMessage`).
   That is the only continuation allowed. A client that cannot continue an agent dispatches a new
   reviewer with `pass: 2`, which first reads the Pass 1 section of `gates/reviewer.md`. The prompt is the filled
   template (role, pass for the reviewer, feature path, source revision, goal SHA-256, allowed files,
   return format, and the implementer's concerns quoted verbatim where `/sdd` already routes them) and
   nothing else. The orchestrator copies it as `## Dispatch` at the top of the gate record. The gate
   first compares its prompt with the template; any other text returns `DISPATCH-CONTAMINATED` and the
   gate stays PENDING.
3. **One channel.** A gate or the goldfish that lacks a fact returns `NEEDS_CONTEXT` with its question.
   The orchestrator answers by editing the packet and dispatches a new fresh gate. It never answers
   into the old context.
4. **The plan goldfish.** A new review-tier role, `sdd-plan-goldfish` (tools `Read, Grep, Glob`), runs
   after the planner and before the checkpoint: always on FULL, on LITE only when a delegated planner
   ran, never on MICRO. It reads `input.md`, `spec.md`, `goal.md`, `plan.md`, `tasks.md` (and `design.md` or
   `research.md` when present), the rules and source, and never opens `gate-briefs.md`, `gates/**`, `.memory/80-feedback.md`,
   `.spec-harness/runs/**` or a transcript. It checks comprehension, readiness (callers and
   signatures), goal-to-task coverage (after the analyze step of GitHub Spec Kit) and reuse (one name
   grep per new symbol against the plan's `## Reuse search` table, RFC 0012). It returns
   `RESULT: READY | NOT-READY | PENDING`, findings labelled `NEEDED` or `ADDITION`, and a `Files read:`
   list. `/sdd` copies the return to `specs/<feature>/gates/plan-goldfish.md`. On `NOT-READY` the
   planner fixes the packet and one new goldfish runs; a second `NOT-READY` goes to the owner at the
   checkpoint. With no fresh context available the goldfish is PENDING and shown at the checkpoint; it
   does not block, so a client without subagents still works. A `Files read:` list naming a forbidden
   file makes the run PENDING, and it is re-dispatched once. It is not a correction round.
5. **Receipt exemption.** Like `sdd-learner`, `sdd-plan-goldfish` and `sdd-router` are harness-owned:
   they bind to no package source and need no receipt row.

## Compatibility

- A packet whose `plan.md` still holds the briefs inline is read as before, and Pass 1 skips that
  section. A plan without briefs stays valid.
- The run-state schema and the checkpoint check do not change. Receipt schemas do not change.
- The role count goes from thirteen to fourteen; the installer already stages `agents/sdd-*.md` by glob,
  and the install manifest gains the one entry.
- The goldfish adds one review-tier subagent per FULL plan, and per LITE plan with a delegated planner.

## Tests

- `tests/sdd-fixtures.sh`: `TIER_ROLES["review"]` holds `plan-goldfish`; the role's `tools:` line is
  exactly `Read, Grep, Glob`; the role holds `NOT-READY`, `gate-briefs.md`, `.memory/80-feedback.md` and
  `Files read`; `/sdd` dispatches `sdd-plan-goldfish` in section 4 before the checkpoint and never on
  MICRO; `/sdd` holds `DISPATCH-CONTAMINATED`, "never a fork" and the one-channel rule; the plan
  contract names the briefs file and its SHA-256; the reviewer says Pass 1 does not open
  `gate-briefs.md`, does Pass 1 only on `pass: 1`, and searches source and tests only; `/sdd` states the
  one reviewer continuation and its fallback; the tester checks the briefs' hash; the goldfish greps
  exclude the packet folders; the MICRO section names neither the goldfish nor `gate-briefs`.
- `tests/skill-lint.sh`: the new role's name, description, tools and model pass the lint.

Red first for each: a planted copy without the token, with `Write` added to the tools, with the role
moved to the fast tier, or with "Pass 1 reads `gate-briefs.md`" fails.

Whether a model returns `NOT-READY` for a planted gap is model behaviour, not a text contract. It
belongs to the eval track, not to these shell tests.

## Later

Cut for this version, with the reason:

- **A read-guard hook.** Hooks declared in agent frontmatter are reported not to fire for subagents (Claude Code issue 18392, January 2026; untested locally); a
  settings-level hook cannot tell which agent calls, so it would also block the orchestrator; Grep, Glob
  and Bash get past a path guard; and one reviewer file cannot tell Pass 1 from Pass 2.
- **A split reviewer by default** (Pass 1 and Pass 2 always as two subagents; today only the fallback for a
  client that cannot continue an agent). It reads the diff twice; file-level
  blindness already gives most of the gain.
- **Hashed read receipts on every gate.** They are self-reported and add hash bookkeeping; the
  goldfish's plain `Files read:` list is enough for now.
- **An intermediate zoom-out after fixes, and a loop until two clean rounds.** Each round costs one more
  subagent run.
- **Dispositions for goldfish findings** (propose a fix, contest, escalate, decline).

Credit: the elephant-goldfish model, https://github.com/google/elephant-goldfish-model, Apache-2.0.
