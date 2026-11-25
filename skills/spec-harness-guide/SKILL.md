---
name: spec-harness-guide
description: "Explain Spec Harness and keep an install of it current: what it is, how to read the installed version, how to update from an older version, and how to confirm that fixes landed. Use when asked how to use or update Spec Harness, whether an install is current or out of date, what changed between versions, or whether a fix has landed."
---

# spec-harness-guide

Read this whole skill before you act. It answers four things and runs only commands that exist in the harness.

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
