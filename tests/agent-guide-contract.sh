#!/usr/bin/env bash
# Contract for the agent guide skill (skills/spec-harness-guide/SKILL.md).
# - The skill answers four things, each under its own heading: what Spec Harness is, how to read the
#   installed version, how to update from an older version, how to confirm that the fixes landed.
# - AGENTS.md (Job 4) and the installed SPEC-HARNESS.md section point to it, and the link resolves.
# - The skill, the Job 4 section and the installed section hold no local path, person or company name.
# - Every command in a `sh` block of the skill runs as written against a fresh fixture install:
#   exit codes are the ones the skill promises, and the output holds the line the skill says it prints.
# Each rule has a planted-fault control that must fail. No network.
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS_DIR="${SPEC_HARNESS_DIR:-$(cd "$TEST_DIR/.." && pwd -P)}"
# shellcheck source=lib/portable.sh
. "$TEST_DIR/lib/portable.sh"
require_tools bash git awk grep
require_python311
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sh-agent-guide.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

python3 -I -B - "$HARNESS_DIR" "$TMP" <<'PY'
import os, re, subprocess, sys
from pathlib import Path

root, tmp = Path(sys.argv[1]), Path(sys.argv[2])
guide_path = root / "skills/spec-harness-guide/SKILL.md"
skill = guide_path.read_text(encoding="utf-8")
agents = (root / "AGENTS.md").read_text(encoding="utf-8")
status_file = (root / "templates/install/SPEC-HARNESS.md").read_text(encoding="utf-8")
failures = []


def require(condition, message):
    print(("PASS: " if condition else "FAIL: ") + message)
    if not condition:
        failures.append(message)


HEADINGS = ("## 1. What Spec Harness is", "## 2. Read the installed version",
            "## 3. Update from an older version", "## 4. Confirm the fixes landed")
STATES = ("landed", "not landed", "cannot tell")


def guide_ok(text):
    """Front matter, the four headings in order, and the three report words."""
    match = re.match(r'---\nname: spec-harness-guide\ndescription: "([^"<>]+)"\n---\n', text)
    positions = [text.find(heading) for heading in HEADINGS]
    return (
        match is not None and 40 < len(match.group(1)) <= 1024
        and all(word in match.group(1) for word in ("update", "installed version", "fixes landed"))
        and all(p >= 0 for p in positions) and positions == sorted(positions)
        and all(f"`{state}`" in text for state in STATES)
        and len(text.splitlines()) < 500
    )


def agents_ok(text):
    section = text.split("## Job 4:", 1)
    link = re.search(r"\]\(\./(skills/spec-harness-guide/SKILL\.md)\)", section[1]) if len(section) == 2 else None
    return bool(link) and (root / link.group(1)).is_file() and "four jobs" in text


def status_ok(text):
    return ("## Version and update" in text and ".claude/skills/spec-harness-guide/SKILL.md" in text
            and ".agents/skills/spec-harness-guide/SKILL.md" in text and "install.json" in text)


# Generic shapes only: a home folder, a ticket key, an email address. Names of a person or a
# company never go in this public file; a maintainer may add their own words, separated by "|",
# in SPEC_HARNESS_PRIVATE_WORDS when running the test locally.
_extra = "|".join(re.escape(w) for w in os.environ.get("SPEC_HARNESS_PRIVATE_WORDS", "").split("|") if w.strip())
PRIVATE = re.compile(r"/Users/|/home/|C:\\|(?-i:\b[A-Z][A-Z0-9]{1,9}-\d+\b)|@[\w.-]+\.[a-z]{2,}\b" + ("|" + _extra if _extra else ""), re.I)


def clean(text):
    return PRIVATE.search(text) is None


job4 = agents.split("## Job 4:", 1)[1].split("## Quick answers", 1)[0]
installed_section = status_file.split("## Version and update", 1)[1]
require(guide_ok(skill), "the guide skill has a quoted description, the four headings in order and the three report words")
require(not guide_ok(skill.replace("## 3. Update from an older version", "## 3. Other")), "RED control: an answer heading removed")
require(not guide_ok(skill.replace("`cannot tell`", "`unknown`")), "RED control: a report word removed")
require(agents_ok(agents), "AGENTS.md names four jobs and Job 4 links to the guide skill, which exists")
require(not agents_ok(agents.replace("./skills/spec-harness-guide/SKILL.md", "./skills/no-such/SKILL.md")), "RED control: a dead guide link in AGENTS.md")
require(status_ok(status_file), "the installed status file points to the guide skill (Claude and other agent tools) and the install record")
require(not status_ok(status_file.replace("## Version and update", "## Other")), "RED control: the installed section removed")
require(clean(skill) and clean(job4) and clean(installed_section), "the skill, Job 4 and the installed section hold no local path, person, company or ticket name")
require(not clean(skill + "\n/" + "Users/" + "someone/work\n"), "RED control: a local path in the skill")
require(not clean(skill + "\nSee ABC-123 for details.\n"), "RED control: a ticket key in the skill")

# Run every `sh` block of the skill against a fresh fixture install.
target = tmp / "target"
target.mkdir()
subprocess.run(["git", "init", "-q", str(target)], check=True)
install = subprocess.run(["bash", str(root / "bin/spec-harness"), "init", str(target), "integrate", "demo"], capture_output=True, text=True)
require(install.returncode == 0, "fixture install exits 0")
# An agent app starts a fresh shell for every command: SRC, SH and INSTALLED are never set beforehand.
# Each block must carry its own setup line, so the environment here has none of them.
env = {k: v for k, v in os.environ.items() if k not in ("SRC", "SH", "INSTALLED")}
PLACEHOLDER = "/folder/of/the/spec-harness/checkout"
SETUP_LINE = 'SRC=' + PLACEHOLDER + '; SH="bash $SRC/bin/spec-harness"'


def run_block(body, cwd=None):
    """Run one block as an agent would: the example folder replaced by the real one, nothing else set."""
    result = subprocess.run(["bash", "-c", body.replace(PLACEHOLDER, str(root))], cwd=cwd or target, env=env, capture_output=True, text=True)
    return result.returncode, result.stdout + result.stderr


blocks = re.findall(r"```sh\n(.*?)```", skill, re.S)
require(len(blocks) == 6 and all(b.startswith(SETUP_LINE + "\n") for b in blocks),
        f"the skill has six sh blocks and every one starts with the setup line (found {len(blocks)})")
setup_only, version_block, update_block, changelog_block, checks_block, fix_block = blocks
require(not any(re.search(r"INSTALLED|\$SH|\$SRC", b.replace(SETUP_LINE, "")) is None for b in blocks[1:]), "every runnable block uses the variables its own setup line defines")

rc, out = run_block(version_block)
require(rc == 0 and re.search(r"installed: \d+\.\d+\.\d+", out) and "source: " in out and "installed version :" in out
        and "update available  : no" in out and "Agent guide       : " in out and "spec-harness-guide/SKILL.md" in out,
        "block 2 (versions and status) exits 0 and prints installed, source, update available and the Agent guide line")
installed = re.search(r"installed: (\d+\.\d+\.\d+)", out).group(1) if re.search(r"installed: \d+\.\d+\.\d+", out) else ""
rc, out = run_block(update_block)
require(rc == 0 and "Spec Harness update plan (nothing was written)" in out and "PLAN DIGEST:" in out and "Nothing to apply." in out,
        "block 3 (update plan) exits 0, writes nothing and shows a digest")
rc, out = run_block(changelog_block)
require(rc == 0 and "## Unreleased" in out and f"## {installed}" not in out and len(out.splitlines()) > 5,
        "block 4 (changelog between installed and source) reads the installed version itself and prints the entries above it")
# A project with no install record: the whole changelog is printed, never an empty or 5-line answer.
bare = tmp / "no-record"
bare.mkdir()
changelog_lines = len((root / "CHANGELOG.md").read_text(encoding="utf-8").splitlines())
rc, out = run_block(changelog_block, cwd=bare)
require(rc == 0 and len(out.splitlines()) == changelog_lines and "## 0.3.0" in out,
        "block 4 with no install record prints the whole changelog")
old_form = SETUP_LINE + """\nINSTALLED=$(python3 -I -B -c "import json; print(json.load(open('.spec-harness/install.json'))['harness_version'])" 2>/dev/null)\nawk -v v="$INSTALLED" '/^## /{ if (index($0, "## " v) == 1) exit } {print}' "$SRC/CHANGELOG.md\""""
rc, out = run_block(old_form, cwd=bare)
require(len(out.splitlines()) < changelog_lines, "RED control: the earlier changelog command, with no install record, hides every entry")
rc, out = run_block(update_block.replace(SETUP_LINE + "\n", ""))
require(rc != 0, "RED control: a block without its setup line fails when the variables are not passed in")
rc, out = run_block(checks_block)
require(rc in (0, 1) and ("READY" in out or "PENDING" in out) and '"structural"' in out,
        "block 5 (doctor, generate-agents --check) runs; PENDING or READY is printed")
rc, out = run_block(fix_block)
require(rc == 0 and "UNCHANGED" in out and "## Run sheet" in out,
        "block 6 (per-file state and phrase check) exits 0, shows UNCHANGED and finds the phrase in the installed file")
rc, out = run_block(fix_block.replace("## Run sheet", "## No such heading"))
require(rc == 1, "RED control: a phrase that is not in the installed file makes the check exit 1 (not landed)")
rc, out = run_block(update_block.replace("update .", "no-such-command ."))
require(rc != 0, "RED control: a command that does not exist fails the block")

sys.exit(1 if failures else 0)
PY
