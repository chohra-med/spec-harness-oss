#!/usr/bin/env bash
# Skill and role lint. Every generated skill and every role file keeps frontmatter a client can load:
# a name equal to its folder (skill) or file stem (role), and a description of at most 1,024
# characters. A skill's description holds no angle bracket and the file stays under 500 lines; a role
# names its tools and its model. "Use when" is not required: the generated descriptions do not use it.
# The lint runs on the real tree, then on temp copies with one planted fault each, which must fail.
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS_DIR="${SPEC_HARNESS_DIR:-$(cd "$TEST_DIR/.." && pwd -P)}"
# shellcheck source=lib/portable.sh
. "$TEST_DIR/lib/portable.sh"
require_python311
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sh-skill-lint.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

python3 -I -B - "$HARNESS_DIR" "$TMP" <<'PY'
from pathlib import Path
import re
import shutil
import sys

root, tmp = Path(sys.argv[1]), Path(sys.argv[2])
MAX_DESCRIPTION = 1024
MAX_SKILL_LINES = 500

def frontmatter(text):
    match = re.match(r"---\n(.*?)\n---\n", text, re.S)
    if not match:
        return None
    fields = {}
    for line in match.group(1).splitlines():
        key, sep, value = line.partition(":")
        if sep and key and not key[0].isspace():
            fields[key.strip()] = value.strip()
    return fields

def lint(base):
    """Return one defect line per broken rule under base/skills and base/agents."""
    defects = []
    skills = sorted((base / "skills").glob("*/SKILL.md"))
    roles = sorted((base / "agents").glob("sdd-*.md"))
    if not skills:
        defects.append("no skills/*/SKILL.md found")
    if not roles:
        defects.append("no agents/sdd-*.md found")
    for path in skills:
        rel = path.relative_to(base)
        text = path.read_text(encoding="utf-8")
        meta = frontmatter(text)
        if meta is None:
            defects.append(f"{rel}: no frontmatter")
            continue
        if meta.get("name") != path.parent.name:
            defects.append(f"{rel}: name {meta.get('name')!r} differs from its folder {path.parent.name!r}")
        description = meta.get("description", "")
        if not description:
            defects.append(f"{rel}: no description")
        if len(description) > MAX_DESCRIPTION:
            defects.append(f"{rel}: description has {len(description)} characters, more than {MAX_DESCRIPTION}")
        if "<" in description or ">" in description:
            defects.append(f"{rel}: description holds an angle bracket")
        lines = len(text.splitlines())
        if lines >= MAX_SKILL_LINES:
            defects.append(f"{rel}: {lines} lines, {MAX_SKILL_LINES} or more")
    for path in roles:
        rel = path.relative_to(base)
        meta = frontmatter(path.read_text(encoding="utf-8"))
        if meta is None:
            defects.append(f"{rel}: no frontmatter")
            continue
        if meta.get("name") != path.stem:
            defects.append(f"{rel}: name {meta.get('name')!r} differs from its file {path.stem!r}")
        description = meta.get("description", "")
        if not description:
            defects.append(f"{rel}: no description")
        if len(description) > MAX_DESCRIPTION:
            defects.append(f"{rel}: description has {len(description)} characters, more than {MAX_DESCRIPTION}")
        for key in ("tools", "model"):
            if not meta.get(key):
                defects.append(f"{rel}: no {key}: line")
    return defects

failures = 0
def check(condition, label):
    global failures
    print(("PASS: " if condition else "FAIL: ") + label)
    if not condition:
        failures += 1

real = lint(root)
for line in real:
    print("FAIL: " + line)
skill_count = len(list((root / "skills").glob("*/SKILL.md")))
role_count = len(list((root / "agents").glob("sdd-*.md")))
check(not real, f"{skill_count} skills and {role_count} roles pass the lint")

# RED controls: each planted fault, in its own fresh copy, must produce its own defect line.
def planted(label, needle, mutate):
    copy = tmp / re.sub(r"\W+", "-", label).strip("-")
    shutil.copytree(root / "skills", copy / "skills")
    shutil.copytree(root / "agents", copy / "agents")
    mutate(copy)
    check(any(needle in line for line in lint(copy)), f"RED control: {label}")

def edit(rel, old, new):
    def mutate(base):
        path = base / rel
        text = path.read_text(encoding="utf-8")
        assert old in text, (rel, old)
        path.write_text(text.replace(old, new, 1), encoding="utf-8")
    return mutate

def longer(rel):
    description = frontmatter((root / rel).read_text(encoding="utf-8"))["description"]
    padded = (description + "x" * MAX_DESCRIPTION)[:MAX_DESCRIPTION + 1]
    return edit(rel, "description: " + description, "description: " + padded)

SKILL = "skills/spec-harness-plan/SKILL.md"
ROLE = "agents/sdd-verifier.md"
planted("skill description of 1,025 characters", "1025 characters", longer(SKILL))
planted("role description of 1,025 characters", "1025 characters", longer(ROLE))
planted("skill name differs from its folder", "differs from its folder", edit(SKILL, "name: spec-harness-plan", "name: spec-harness-planner"))
planted("role name differs from its file", "differs from its file", edit(ROLE, "name: sdd-verifier", "name: sdd-checker"))
planted("angle bracket in a skill description", "angle bracket", edit(SKILL, "description: ", "description: Writes specs/<feature>/plan.md. "))
planted("role without a tools line", "no tools: line", edit(ROLE, "\ntools: ", "\nx-tools: "))
planted("role without a model line", "no model: line", edit(ROLE, "\nmodel: ", "\nx-model: "))
planted("skill of 500 lines", "500 or more", lambda base: (base / SKILL).write_text((base / SKILL).read_text(encoding="utf-8") + "line\n" * MAX_SKILL_LINES, encoding="utf-8"))

if failures:
    print(f"RED: {failures} skill-lint check(s) failed")
    raise SystemExit(1)
print("GREEN: skill and role lint holds and every planted fault is caught")
PY
