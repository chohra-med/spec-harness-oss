#!/usr/bin/env bash
# sh-make-skills.sh — generate the Spec Harness skill set into spec-harness/skills/.
# One Claude Code skill per command (SKILL.md w/ trigger-rich description). The installer
# distributes skills/* into each repo's .claude/skills/. Re-run to regenerate after a command
# doc changes — single source of truth stays the command docs; skills are thin invocable entries.
set -euo pipefail
SYS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="$SYS_DIR/skills"
[ ! -L "$OUT" ] || { echo "refusing to generate through a skills symlink: $OUT" >&2; exit 2; }
mkdir -p "$OUT"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/sh-make-skills.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT

# The body of the agent guide skill (spec-harness-guide). Unlike the thin routes below, this skill carries
# its own text: it must work in an install that is older than the source and in the source repository.
guide_body() {
  cat <<'EOF_GUIDE'
Use this skill when the person asks how to use or update Spec Harness, whether an install is current,
what changed between versions, or whether a fix has landed. It answers four things:

1. What Spec Harness is.
2. How to read the installed version.
3. How to update from an older version.
4. How to confirm that the fixes landed.

Reading and checking change nothing. Updating changes the project, so it needs the person's yes.

## Set up the commands once

Run every command here from the root of the project that has Spec Harness installed (the target).
Most agent tools start a new shell for every command, so a variable set in one command is gone in the
next. Start **every** block below with this line, in the same command, with the real folder in place
of the example:

```sh
SRC=/folder/of/the/spec-harness/checkout; SH="bash $SRC/bin/spec-harness"
```

`SRC` is the Spec Harness source checkout (the folder that holds `bin/spec-harness` and
`CHANGELOG.md`). Ask the person when you do not know it. `SH` is the command; write `SH=spec-harness`
instead when that command is on the PATH.

With no checkout on the machine, ask the person. Do not use `npx` unless they say yes: it downloads
the published package, which can be older than the source you were pointed at.

## 1. What Spec Harness is

Spec Harness is a set of markdown procedures, agent role files and a small Bash command. It is
installed into a project. It gives the project a memory bank (`.memory/`), source-backed rules
(`ai_rules/`), a planner, an implementer, independent tester, verifier and reviewer roles, and a
learning loop. It never edits the project's application source during install.

In the installed project:

- `SPEC-HARNESS.md` says whether setup is `PENDING` or ready.
- `/sdd` (file `.claude/commands/sdd.md`) is the procedure for every code ticket. Codex reads
  `.agents/skills/sdd/SKILL.md`.
- `.spec-harness/install.json` records which version and commit were installed.

In the source repository, `AGENTS.md` says which of four jobs you were given, and
`docs/GETTING-STARTED.md` is the human guide.

## 2. Read the installed version

```sh
SRC=/folder/of/the/spec-harness/checkout; SH="bash $SRC/bin/spec-harness"
INSTALLED=$(python3 -I -B -c "import json; print(json.load(open('.spec-harness/install.json'))['harness_version'])" 2>/dev/null)
echo "installed: ${INSTALLED:-unknown (no install record)}"
python3 -I -B -c "import json,sys; print('source:', json.load(open(sys.argv[1]))['version'])" "$SRC/package.json"
$SH status .
```

`status` prints the installed and source versions and commits, a count of files by state, and
`update available : yes` or `no`. It also prints an `Agent guide:` line with the path of this skill.

No `.spec-harness/install.json` means the install is older than 0.4.0. Its version is unknown. Treat
it as the oldest version and read the whole changelog.

## 3. Update from an older version

Steps 1 to 3 only read. Step 4 needs the person's yes.

1. Get the new source. Use the person's checkout. Running `git -C "$SRC" pull --ff-only` needs the
   network, so ask first. Never edit the install by copying files by hand.
2. Make sure the project has no uncommitted work you could lose: `git status --short`. If tracked
   files are modified, stop and tell the person.
3. Read the plan. It writes nothing. Each line is one file and one state:

```sh
SRC=/folder/of/the/spec-harness/checkout; SH="bash $SRC/bin/spec-harness"
$SH update .
```

   - `UNCHANGED`: already current.
   - `UPDATE`: not edited locally; the new file replaces it.
   - `MERGE`: edited locally and changed upstream; a clean three-way merge is written.
   - `CONFLICT`: the merge overlaps. A `.spec-harness-proposed` file is written next to it. Show the
     person both versions in the chat, ask which lines to keep, and write the file only after their yes.
   - `CUSTOMIZED-KEEP`: edited locally; kept as it is.
   - `NEW`: a file the new version adds. `REMOVED-UPSTREAM`: no longer shipped; listed, never deleted.

4. Apply exactly the plan the person approved, with the digest the plan printed:

```text
SRC=/folder/of/the/spec-harness/checkout; SH="bash $SRC/bin/spec-harness"
$SH update . --apply DIGEST
```

5. If the project has a synthesis receipt, the update marks synthesis stale. Run `/sdd init` (guarded
   refresh) and then the check in section 4.

An older install does not have this skill. `status` run from the new source prints its source path in
the `Agent guide:` line, and the update adds it to the project.

## 4. Confirm the fixes landed

1. Read the installed version (section 2).
2. Read the changelog entries between the installed version and the source. This prints every
   entry above the installed version's heading (`Unreleased` is the newest, then each version):

```sh
SRC=/folder/of/the/spec-harness/checkout; SH="bash $SRC/bin/spec-harness"
INSTALLED=$(python3 -I -B -c "import json; print(json.load(open('.spec-harness/install.json'))['harness_version'])" 2>/dev/null)
if [ -z "$INSTALLED" ]; then cat "$SRC/CHANGELOG.md"
else awk -v v="$INSTALLED" '/^## /{ if ($0 == "## " v || index($0, "## " v " ") == 1) exit } {print}' "$SRC/CHANGELOG.md"; fi
```

   With no install record the whole changelog is printed.

3. Run the read-only checks. Before `/sdd init` has run, both can print `PENDING`; that is expected,
   not a fault.

```sh
SRC=/folder/of/the/spec-harness/checkout; SH="bash $SRC/bin/spec-harness"
$SH doctor .
$SH generate-agents --check .
```

4. For each fix in the changelog, find the file it names, then read the installed copy:

```sh
SRC=/folder/of/the/spec-harness/checkout; SH="bash $SRC/bin/spec-harness"
$SH update . | grep -F ".claude/commands/spec-harness/init.md"
grep -n -F "## Run sheet" .claude/commands/spec-harness/init.md
```

   The first line shows the state of that file. The second shows a phrase the fix added (the phrase
   here is an example; take yours from the changelog entry).

5. Report each fix with one word and the output line that shows it:

   - `landed`: the file's state is `UNCHANGED`, or the phrase is in the installed file.
   - `not landed`: the state is `UPDATE`, `MERGE`, `NEW` or `CONFLICT`, or the phrase is missing.
   - `cannot tell`: the state is `CUSTOMIZED-KEEP` (edited locally), the file is a synthesis output,
     or the fix is in the source command only (check it by running that command against the source).

Never report a fix as landed from the changelog alone.
EOF_GUIDE
}

# name|doc|agents|description (description = the model-invocation trigger; keep it phrase-rich)
emit() {
  local name="$1" doc="$2" agents="$3" desc="$4" role="$5" shared_route="${6:-no}"
  local dir="$STAGE/$name"; mkdir -p "$dir"
  {
    printf -- '---\n'
    printf 'name: %s\n' "$name"
    printf 'description: %s\n' "$desc"
    printf -- '---\n\n'
    printf '# %s\n\n%s\n\n' "$name" "$role"
    if [ "$shared_route" = guide ]; then
      guide_body
    else
    printf '## Run it\n'
    if [ "$shared_route" = method ]; then
      printf '1. **Load this reusable method owner**: `.claude/commands/spec-harness/%s.md` (installed project) or source `commands/%s.md`. This method is usable during initialization before a synthesis receipt or feature goal exists.\n' "$doc" "$doc"
      printf '2. **Use shared SDD context when applicable**: `.claude/commands/sdd.md`; do not infer role bindings or native discovery from this skill file.\n\n'
    elif [ "$shared_route" = yes ]; then
      printf '1. **Load the shared SDD procedure first**: `.claude/commands/sdd.md` (installed project) or source `commands/sdd.md`.\n'
      printf '2. **Load this stage contract**: `.claude/commands/spec-harness/%s.md` (installed project) or source `commands/%s.md`.\n' "$doc" "$doc"
      printf '3. **Resolve roles from the receipt**: use only `.claude/agents/.init-synthesis.json` selected paths; file presence or model frontmatter does not prove binding or capability.\n'
      printf '4. **Stay inside the 3 pillars**: Memory bank (`.memory/`) · Spec-Driven Development · Harness. Read `SPEC-HARNESS.md` for setup status.\n\n'
    else
      printf '1. **Load the full procedure**: read the command doc and follow it exactly:\n'
      printf '   `.claude/commands/spec-harness/%s.md` (this repo) or the spec-harness source `commands/%s.md`.\n' "$doc" "$doc"
      pillars_step=2
      if [ -n "$agents" ]; then
        printf '2. **Agents**: follow this command and project policy for role selection.\n'
        pillars_step=3
      fi
      printf '%s. **Stay inside the 3 pillars**: Memory bank (`.memory/`) · Spec-Driven Development · Harness (ratchet `AGENTS.md` + verifier + learning loop). Read `SPEC-HARNESS.md` for how this repo is wired.\n\n' "$pillars_step"
    fi
    printf '## Non-negotiables\n'
    if [ "$shared_route" = method ]; then
      printf -- '- Follow the method owner and target project policy; preserve its evidence and write boundaries.\n'
      printf -- '- This route does not prove that a native client discovered or executed the skill.\n'
    elif [ "$shared_route" = yes ]; then
      printf -- '- Preserve failures and classify feedback; rules change only after reviewed learning.\n'
      printf -- '- A ticket is done only after a fresh verifier passes `specs/<feature>/goal.md`.\n'
      printf -- '- Green tests/review do not grant commit, merge, release, or ticket write-back authority.\n'
    else
      printf -- '- The ratchet only tightens after a reviewed rule change.\n'
      printf -- '- Nothing is "done" until the separate verifier returns PASS against the applicable goal.\n'
      printf -- '- Every correction or FAIL cause goes through `spec-harness-learn` classification.\n'
      printf -- '- Never commit, push or merge unless asked.\n'
    fi
    fi
  } > "$dir/SKILL.md"
  echo "  staged $name"
}

emit spec-harness "build" "" \
"The Spec Harness orchestrator. Spec-driven development wrapped in a harness (reviewed ratchet + independent verifier + learning loop) over a persistent memory bank. Use when the user says 'use spec harness', 'run the spec harness', 'spec-harness this feature', or wants the full /sdd init or ticket → feature spec/goal → plan → tasks → independent gates flow. Routes to the sub-skills and enforces the 3 pillars (Memory bank · SDD · Harness)." \
"You are the orchestrator for a Spec Harness project. Read the shared \`sdd\` procedure first, then route initialization or ticket work through the appropriate stage skill. Resolve every project-specific role from the synthesis receipt. The implementer does not own acceptance. A code ticket is any change to a tracked file outside \`specs/\` and \`.memory/\`. It goes through \`/sdd\` before the first source edit, even when it looks small: the light route is still \`/sdd\`. Keep the ticket's code inside this repository: no worktree, clone or copy elsewhere unless the user asks for one." yes

emit spec-harness-install "init" "researcher" \
"Add or refresh Spec Harness in a repo, greenfield or existing. Use when the user asks to install or initialize Spec Harness. The shell stages files and leaves project synthesis PENDING." \
"Stage the harness, then follow \`.claude/commands/spec-harness/init.md\` as a capable model (source checkout fallback: \`commands/init.md\`): read the inventory, applicable project rules and actual representative source; derive package-scoped rules, the core project skills (five on first initialisation) and a skill per major technology; bind project-aware planner, implementer, fresh tester, verifier and reviewer roles; record evidence and run the structural/provenance check. A separate fresh reviewer must confirm claim support before overall initialization is READY. Shell staging remains PENDING."

emit spec-harness-tickets "tickets" "researcher, planner" \
"Intake exact ticket text or a retrieved body from an explicitly connected provider. Use when the user asks to run /sdd on ticket text, a connected issue, or a feature request. Bare issue names without a retrievable body stop for clarification. Produces a feature-owned packet and goal under specs/." \
"Use \`commands/sdd.md\` for the full route. Preserve exact input, pin its provenance and source/rule state, then create a checkable feature-specific spec and goal. Never write the ticket back without separate approval." yes

emit spec-harness-spec "spec" "researcher" \
"Turn accepted ticket text into a structured, testable feature spec and goal. Use when the user says 'spec this', 'write the spec for X', or asks what the requirements are. First SDD artifact stage." \
"Write \`specs/<feature>/spec.md\` with provenance and checkable acceptance, then derive \`specs/<feature>/goal.md\`. Keep root \`goal.md\` untouched." yes

emit spec-harness-plan "plan" "planner" \
"Plan a ticket against actual source and target rules. Use when the user says 'plan the implementation', 'how should we build this', or 'design this'. Apply full Ponytail, and source-grounded Grill Me for LITE and FULL tickets only (a MICRO ticket never asks Grill Me), before finalizing the plan." \
"Use the bound planner. Record source-backed decisions, the highest successful Ponytail rung, reuse and exclusions, and only material unresolved Grill Me choices (none for a MICRO ticket, which never asks Grill Me). Keep the plan tied to the feature goal and source/rule hashes." yes

for method in ponytail grill-me package-finder skill-finder conventions technology-profiles standards; do
  description="Use the portable Spec Harness $method method when initializing a project or planning a ticket that needs this method. Read actual target evidence first; do not install third-party skills or dependencies automatically."
  if [ "$method" = conventions ]; then
    description="Use the portable Spec Harness conventions method to find the repository's branch, commit, pull-request and task-splitting conventions from its own policy and bounded Git history, during initialization or when a ticket touches them. Read actual target evidence first; never create branches or commits."
  fi
  if [ "$method" = technology-profiles ]; then
    description="Use the portable Spec Harness technology-profiles method to select a technology profile and give every package and direct dependency a disposition from manifests, lockfiles and imports, during initialization or planning. Read actual target evidence first; do not install packages or third-party skills."
  fi
  if [ "$method" = standards ]; then
    description="Use the portable Spec Harness standards method to find which named standards and laws (for example the European Accessibility Act with EN 301 549, OWASP MASVS, GDPR, ISO/IEC 27001) the project has, must meet or plans to meet, record the owner's commitment and turn it into rules, during initialization or when a ticket touches accessibility, personal data, payments or security. Read actual target evidence first; it never certifies compliance."
  fi
  if [ "$method" = ponytail ]; then
    description="Use the portable Spec Harness Ponytail method for code or implementation work, project initialization, or ticket planning that needs this method. Read actual target evidence first; do not install third-party skills or dependencies automatically."
  fi
  emit "spec-harness-$method" "$method" "" \
    "$description" \
    "Read the installed method owner at .claude/commands/spec-harness/$method.md and follow it. This skill is only a route; it does not replace the shared SDD procedure or prove native client discovery." method
done

emit spec-harness-guide "" "" \
'"Explain Spec Harness and keep an install of it current: what it is, how to read the installed version, how to update from an older version, and how to confirm that fixes landed. Use when asked how to use or update Spec Harness, whether an install is current or out of date, what changed between versions, or whether a fix has landed."' \
"Read this whole skill before you act. It answers four things and runs only commands that exist in the harness." guide

emit spec-harness-tasks "tasks" "planner" \
"Break an accepted feature plan into ordered, testable tasks. Use when the user says 'break this into tasks' or 'what are the steps'." \
"Use the bound planner. Each task names repo-relative files, a criterion from \`specs/<feature>/goal.md\`, a real test command, dependencies and any authority boundary." yes

emit spec-harness-build "build" "implementer, tester, verifier, reviewer" \
"Execute a feature packet one task at a time with independent acceptance. Use when the user says 'build it', 'run the pipeline', or 'implement the tasks'." \
"Use the bound implementer, then (after its DONE or DONE_WITH_CONCERNS status; \`.claude/commands/sdd.md\` section 6 owns the statuses and briefs) separate fresh tester, verifier and reviewer contexts. Record each result against the same source/rule revisions and \`specs/<feature>/goal.md\`. Failing or unavailable gates stay open; no merger authority is implied." yes

emit spec-harness-verify "verify" "verifier" \
"Run a fresh verifier against the current feature-specific goal. Use when the user says 'verify it', 'is it actually done', or 'check against the goal'. Tests passing ≠ goal met." \
"Resolve the bound verifier from \`.claude/agents/.init-synthesis.json\`; check each literal criterion in \`specs/<feature>/goal.md\` with evidence. Root \`goal.md\` is not a substitute." yes

emit spec-harness-tester "tester" "workflow-tester" \
"Adversarially validate the app's critical workflows. For each journey in workflows/, a clean-context agent RUNS it end-to-end and actively tries to BREAK it (bad inputs, kill mid-flow, races, double-submit, offline, boundary values), then reports which are BROKEN, ranked P0 first. Use when the user says 'test the workflows', 'try to break the app', 'which critical flows are broken', 'run the workflow tester', or 'is checkout/onboarding still working'. The tester checks reality against critical journeys alongside the verifier's goal check. \`--scan\` and \`tester\` with a journey ID use a capable client; the shell reports PENDING/manual. A BROKEN result sends its repro and candidate guard through reviewed learning; policy changes require approval." \
"Load the workflows/ bank (P0 first). For each workflow spawn a fresh sdd-workflow-tester (clean context, no stake): it runs the journey via how_to_run, then attacks its invariants (bad inputs · kill mid-flow · races/double-submit · offline · boundary · replay) and returns PASS or BROKEN with a concrete repro. Aggregate a ranked report; send each BROKEN repro, likely cause and candidate guard through commands/learn.md for capture, classification and review. Apply a policy change only after approval. The shell prints PENDING/manual; a capable client may propose candidate workflows from app evidence (routes/entry points/write paths) for human confirmation."

emit spec-harness-learn "learn" "learner" \
"Capture a human correction, review finding, bug postmortem or verifier/tester failure as one testable rule. Use when the user says 'learn this', 'remember this', 'capture this lesson', or a separate acceptance role finds a cause." \
"Run commands/learn.md: capture raw feedback, propose a testable cause and owner, and record the existing human/reviewer decision. Apply a canonical rule only after approval; report affected skill/role bindings as stale for the orchestrator's guarded refresh. Unsupported or pending proposals stay captured and proposed. Report LEARNED only after reviewed application; otherwise report PENDING."

emit spec-harness-teach "teach" "" \
"Explain a system to a human as one self-contained page: a two-minute quick guide first (what they get, how to start), then the longer version with diagrams. Use when the user says 'explain this to me', 'teach me how this works', 'make a learning page', 'onboard someone to this', or wants to understand a codebase, a feature or a decision." \
"Run commands/teach.md: read the real source, write the quick guide and cut it to two minutes, write the longer version underneath, then check it in a real browser at two widths and click every control. Never invent an excerpt or a number. Never edit application source."

emit spec-harness-rules "rules" "researcher, implementer" \
"Derive or review package-scoped rules from an inventory, applicable policies, actual source, tests and configuration. Use during initialization or when a mixed-stack package needs its own rules." \
"Read \`.claude/commands/spec-harness/rules.md\` (source checkout fallback: \`commands/rules.md\`). Open every cited source file and separate OBSERVED facts from RECOMMENDATIONS. Preserve populated policies; fill only explicit scaffolds. Unknown manifests and missing citations remain visible PENDING. Run generate-agents and its --check for structural/provenance readiness; use a separate fresh reviewer to confirm claim support before reporting overall initialization READY."

emit spec-harness-generate-agents "generate-agents" "researcher" \
"Bind applicable SDD roles to project rules and source evidence. Use during initialization or after a changed rule/source requires a binding refresh. Role selection must distinguish project need from installed templates." \
"Run \`spec-harness generate-agents <target>\` (with no install: \`npx -y github:chohra-med/spec-harness-oss#v0.7.0 generate-agents <target>\`), then follow its work order using the inventory, existing policies and actual representative code. Bind the required project-aware planner, implementer, fresh tester, verifier and reviewer roles; select merger, design and workflow roles only when evidence supports them. Edit only GEN:rules blocks, cite package paths and source line/hash evidence, write the synthesis receipt, and run \`spec-harness generate-agents --check <target>\` (with no install: \`npx -y github:chohra-med/spec-harness-oss#v0.7.0 generate-agents --check <target>\`). A separate fresh reviewer must confirm claim support before overall initialization is READY. Staging alone is PENDING."

emit spec-harness-audit "audit" "researcher" \
"Health-check the memory bank, rules, and index: flag stale or contradictory entries and spec↔code drift. Use when the user says 'audit the bank', 'is the memory stale', 'check spec harness health', or 'clean up the rules'." \
"Cross-check the bank, ai_rules, and index for staleness, contradiction, and drift from the real code. Report fixes; promote durable learnings up into the curated bank."

for staged in "$STAGE"/*; do
  [ -d "$staged" ] || continue
  name="${staged##*/}"
  destination="$OUT/$name"
  [ ! -L "$destination" ] || { echo "refusing to write through skill symlink: $destination" >&2; exit 2; }
  if [ -e "$destination" ] && [ ! -d "$destination" ]; then
    echo "refusing to replace non-directory skill path: $destination" >&2
    exit 2
  fi
  mkdir -p "$destination"
  skill_file="$destination/SKILL.md"
  [ ! -L "$skill_file" ] || { echo "refusing to write through skill-file symlink: $skill_file" >&2; exit 2; }
  temp_file="$(mktemp "$destination/.SKILL.md.XXXXXX")"
  cp "$staged/SKILL.md" "$temp_file"
  mv "$temp_file" "$skill_file"
done
count="$(find "$STAGE" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
echo "✅ regenerated $count owned command skills into $OUT; other skill paths were preserved"
