#!/usr/bin/env bash
# Line anchors (bin/sh_anchor.py) and the inventory frame (bin/sh_inventory_frame.py). The anchor
# section checks the module on literal text with hashes computed here; every inventory in the frame
# section is written by the real bin/sh-index.sh in a temporary folder.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib/portable.sh
. "$ROOT/tests/lib/portable.sh"
require_tools bash git
require_python311
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sh-anchor-fixtures.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

# Anchor section: text and enclosing-line anchors, the span search, and text blocks outside rows.
python3 -I -B - "$ROOT" <<'PY'
import hashlib
import sys
from collections import Counter
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(sys.argv[1]) / "bin"))
import sh_anchor as sa


def h(text):
    # Expected hashes come from the literal text, never from the module under test.
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# text_sha256 is the span rule the checker has always used: decode with replacement, split lines, join
# the span with LF. LF, CRLF and CR files give the same lines and the same hash.
EXPECTED = "43acbb4eff5917e103f8adf6dbbdecdaecad74822811a5114c2e6c8064105339"
assert EXPECTED == h("export function App() {\n  return null;")
for label, newline in (("LF", "\n"), ("CRLF", "\r\n"), ("CR", "\r")):
    data = newline.join(["export function App() {", "  return null;", "}", ""]).encode()
    lines = sa.lines(data)
    assert lines == ["export function App() {", "  return null;", "}"], (label, lines)
    assert sa.text_sha256(lines, 1, 2) == EXPECTED, label
    existing = hashlib.sha256("\n".join(data.decode("utf-8", errors="replace").splitlines()[0:2]).encode()).hexdigest()
    assert existing == EXPECTED, label
assert sa.text_sha256(sa.lines(b"caf\xff\nnext\n"), 1, 1) == h("caf�"), "an invalid byte is replaced, as the checker does"
print("PASS: text_sha256 equals the existing span rule on LF, CRLF and CR files")

# context_line: the first non-blank line at or after the span start sets the indent; the nearest
# non-blank line above with a smaller indent is the enclosing line, stripped.
lib = ["export function total(values: number[]): number {", "  let sum = 0;", "  for (const value of values) sum += value;", "  return sum;", "}"]
assert sa.context_line(lib, 2) == "export function total(values: number[]): number {"
assert sa.context_sha256(lib, 2) == "456f90d9d1c4334cc51acd7af6e8fc71106c676fb7e80a0409925d5542ca25a2" == h(lib[0])
assert sa.context_line(lib, 3) == lib[0], "a sibling line at the same indent is skipped"
bullets = ["- Release", "  - Tag the build.", "    - Sign the tag.", "- Docs"]
assert sa.context_line(bullets, 2) == "- Release" and sa.context_line(bullets, 3) == "- Tag the build."
assert sa.context_line(lib, 1) == "" and sa.context_sha256(lib, 1) == h("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
assert sa.context_line(bullets, 4) == "", "a top-level span has no enclosing line"
blank_start = ["def run():", "", "", "    return 1"]
assert sa.context_line(blank_start, 2) == "def run():", "a span that starts with blank lines takes its indent from its first text line"
assert sa.context_line(["", "  "], 1) == ""
print("PASS: context_sha256 is the nearest less-indented non-blank line above the span, stripped, or empty for a top-level span")

# locate: at its recorded lines first; otherwise one window of the same length is a move, more is
# ambiguous, none is changed. With a context anchor, a different enclosing line is context-changed.
span_text = sa.text_sha256(lib, 2, 3)
context = sa.context_sha256(lib, 2)
assert sa.locate(lib, 2, 3, span_text) == ("same", 2)
assert sa.locate(lib, 2, 3, span_text, context) == ("same", 2)
copy_elsewhere = lib + ["export function other() {"] + lib[1:3] + ["}"]
assert sa.locate(copy_elsewhere, 2, 3, span_text) == ("same", 2), "a span at its lines passes even with a copy elsewhere"
moved = ["// header", "", *lib]
assert sa.locate(moved, 2, 3, span_text) == ("moved", 4)
assert sa.locate(moved, 2, 3, span_text, context) == ("moved", 4)
twice = ["// header", *lib, "export function again() {", *lib[1:3], "}"]
assert sa.locate(twice, 2, 3, span_text) == ("ambiguous", None)
edited = [lib[0], "  let sum = 1;", *lib[2:]]
assert sa.locate(edited, 2, 3, span_text) == ("changed", None)
assert sa.locate(lib[:2], 2, 3, span_text) == ("changed", None), "a span past the end of a shorter file is changed"
renamed = ["export function sum(values: number[]): number {", *lib[1:]]
assert sa.locate(renamed, 2, 3, span_text) == ("same", 2), "without a context anchor only the span text counts"
assert sa.locate(renamed, 2, 3, span_text, context) == ("context-changed", 2)
assert sa.locate(["// header", *renamed], 2, 3, span_text, context) == ("context-changed", 3)
print("PASS: locate finds a span at its lines, moved to one place, more than once, changed, or under a changed enclosing line")

# blocks: maximal runs of non-blank lines that hold no line of a ledger row, each with its hash.
prose = ["# Contributing", "", "Thank you for helping.", "Keep every change small.", "", "- Row one.", "- Row two."]
rows = [(6, 6), (7, 7)]
found = sa.blocks(prose, rows)
assert found == [(1, 1, h("# Contributing")), (3, 4, h("Thank you for helping.\nKeep every change small."))], found
recorded = Counter(digest for _, _, digest in found)
moved_paragraph = ["# Contributing", "", "- Row one.", "- Row two.", "", "Thank you for helping.", "Keep every change small."]
assert Counter(digest for _, _, digest in sa.blocks(moved_paragraph, [(3, 3), (4, 4)])) == recorded, "a moved paragraph is the same text"
deleted = ["# Contributing", "", "- Row one.", "- Row two."]
assert not Counter(digest for _, _, digest in sa.blocks(deleted, [(3, 3), (4, 4)])) - recorded, "a deleted block is not new text"
split = ["# Contributing", "", "Thank you for helping.", "", "Keep every change small.", "", "- Row one.", "- Row two."]
new_text = Counter(digest for _, _, digest in sa.blocks(split, [(7, 7), (8, 8)])) - recorded
assert set(new_text) == {h("Thank you for helping."), h("Keep every change small.")}, "a split paragraph reports both halves"
around = ["Text directly above.", "- The row.", "Text directly below."]
assert sa.blocks(around, [(2, 2)]) == [(1, 1, h("Text directly above.")), (3, 3, h("Text directly below."))], "a row line ends a run"
assert sa.is_prose("CONTRIBUTING.md") and sa.is_prose("docs/Guide.MDX") and sa.is_prose("notes.txt")
assert not sa.is_prose("ci/pipeline.yml") and not sa.is_prose("package.json")
print("PASS: text blocks outside rows are the runs of non-blank lines, and a deleted block is not new text")

missing = h("- A requirement.")
for label, data in (("empty", b""), ("blank-only", b"\n  \n\t\n")):
    lines = sa.lines(data)
    assert sa.blocks(lines, []) == [], label
    assert sa.locate(lines, 1, 1, missing) == ("changed", None), label
    assert sa.context_line(lines, 1) == "", label
print("PASS: an empty file and a file with only blank lines give no span and no block")

# The whole-file search is bounded in characters: min(span, windows) x (characters + lines), what it joins and hashes,
# at most MAX_LOCATE_WORK. Over the bound only the recorded lines are hashed and the status is too-large; at the bound
# each window is hashed once. Sizes come from the bound; the test counts hash calls, not time.
import math
real_text_sha256, calls = sa.text_sha256, []
def counted_text_sha256(lines, start, end):
    calls.append((start, end))
    return real_text_sha256(lines, start, end)
sa.text_sha256 = counted_text_sha256
bound = sa.MAX_LOCATE_WORK
# The largest span that divides the bound with as many windows as lines: 2 x span - 1 lines holding bound / span
# characters and line breaks, so the search work is exactly the bound.
span = max(divisor for divisor in range(1, math.isqrt(bound // 2) + 1) if bound % divisor == 0)
count = 2 * span - 1
small, extra = divmod(bound // span - count, count)
at_bound = ["x" * (small + 1)] * extra + ["x" * small] * (count - extra)
windows = count - span + 1
assert windows == span and min(span, windows) * (sum(map(len, at_bound)) + len(at_bound)) == bound
absent = h("Text that is in no window.")
calls.clear()
assert sa.locate(at_bound, 1, span, absent) == ("changed", None)
assert calls == [(first, first + span - 1) for first in [1] + list(range(1, windows + 1))], len(calls)
over = ["x" + at_bound[0]] + at_bound[1:]
calls.clear()
assert sa.locate(over, 1, span, absent) == ("too-large", None) and calls == [(1, span)], len(calls)
calls.clear()
assert sa.locate(over, 1, span, real_text_sha256(over, 1, span)) == ("same", 1) and calls == [(1, span)], "a span at its lines is always found"
# A one-line span is one pass over the file, however many lines it has: min(span, windows), not the line count.
single = [str(number) for number in range(math.isqrt(bound) + 1)]
assert len(single) * (sum(map(len, single)) + len(single)) > bound
calls.clear()
assert sa.locate(single, 1, 1, real_text_sha256(single, len(single), len(single))) == ("moved", len(single)) and len(calls) == 1 + len(single)
sa.text_sha256 = real_text_sha256
print("PASS: locate stops at its character work bound without searching and returns too-large; at the bound it hashes each window once")
PY

# Frame section: key coverage, fail-closed projection, and which inventory changes move the frame.
python3 -I -B - "$ROOT" "$TMP/frame" <<'PY'
import copy
import json
import shutil
import subprocess
import sys
from pathlib import Path

sys.dont_write_bytecode = True
root, tmp = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(root / "bin"))
sys.path.insert(0, str(root / "tests/lib"))
import ready_fixture as fx
import sh_inventory_frame as sf

INVENTORY = "ai_rules/project_inventory.json"
RECEIPT = ".claude/agents/.init-synthesis.json"


def index(target, *args):
    result = subprocess.run(["bash", str(root / "bin/sh-index.sh"), str(target), *args], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return json.loads((target / INVENTORY).read_text())


def git(target, *args):
    subprocess.run(["git", "-c", "user.email=t@t", "-c", "user.name=t", "-c", "commit.gpgsign=false", *args],
                   cwd=target, capture_output=True, text=True, check=True)


def seen_keys(value, prefix=""):
    # Every key path present, descending only where the table says "walk", as the module does.
    found = set()
    if isinstance(value, list):
        for item in value:
            found |= seen_keys(item, prefix + "[]")
    elif isinstance(value, dict):
        for key, child in value.items():
            path = f"{prefix}.{key}" if prefix else key
            found.add(path)
            if sf.KEY_CLASSES.get(path) == "walk":
                found |= seen_keys(child, path)
    return found


def changed_parts(before, after):
    return {name for name in before["parts"] if before["parts"][name] != after["parts"][name]}


# The shared schema 4 fixture: its receipt-time inventory is the frame's reference.
base = tmp / "base"
fx.build(base, root, schema=4)
receipt = json.loads((base / RECEIPT).read_text())
outputs = sf.receipt_outputs(receipt)
assert outputs == {"RULES.md", "ai_rules/rules/coding.md"}, outputs
assert sf.receipt_outputs({"packages": "x"}) == set() and sf.receipt_outputs({"packages": [1, {"rules_path": 2, "rule_modules": "y"}]}) == set()
assert all(sf.is_harness_owned(path) for path in ("ai_rules/rules/frequent_rules.md", ".claude/spec-harness/rule-packs/README.md", "ai_rules/index/cards/a.md"))
assert not sf.is_harness_owned("AGENTS.md") and not sf.is_harness_owned("docs/ai_rules/index/a.md")
receipt_time = json.loads((base / INVENTORY).read_text())
reference = sf.frame(receipt_time, outputs)
assert reference["version"] == sf.FRAME_VERSION == 1, reference
assert list(reference["parts"]) == ["packages", "workspace", "scan", "limitations", "policy_files"], reference
assert all(len(value) == 64 and set(value) <= set("0123456789abcdef") for value in reference["parts"].values()), reference

# Exact installed rule filenames are harness-owned; lookalikes remain project policy.
exact_names = ("ai_rules/rules/core.md", "ai_rules/rules/context_management.md")
near_names = tuple(name + suffix for name in exact_names for suffix in ("-extra.md", ".bak", "/nested.md"))
assert all(sf.is_harness_owned(name) for name in exact_names)
assert all(not sf.is_harness_owned(name) for name in near_names), near_names
assert sf.is_harness_owned(".agents/skills/x.md") and sf.is_harness_owned("ai_rules/index/card.md")
assert not sf.is_harness_owned(".agentsx/x.md") and not sf.is_harness_owned("ai_rules/indexx/card.md")
for name in exact_names:
    sample = copy.deepcopy(receipt_time)
    sample["rule_files"].append({"path": name, "read_status": "read"})
    assert sf.frame(sample, outputs) == reference, name
for name in near_names:
    sample = copy.deepcopy(receipt_time)
    sample["rule_files"].append({"path": name, "read_status": "read"})
    added = sf.frame(sample, outputs)
    assert changed_parts(reference, added) == {"policy_files"}, name
    sample["rule_files"][-1]["read_status"] = "unreadable"
    assert changed_parts(added, sf.frame(sample, outputs)) == {"policy_files"}, name
    assert sf.frame(sample, outputs | {name}) == reference, name
print("PASS: exact harness names and project lookalikes retain distinct policy frame boundaries")

# A target that writes every optional key: a workspace declaration and file, a pyproject.toml, an
# unsupported manifest (status and reason), a receipt-generated rule file (re-index after synthesis),
# an unreadable instruction file (over the read limit), --exclude-dir and --source.
coverage = tmp / "coverage"
fx.build(coverage, root, schema=4)
fx.write(coverage / "package.json", '{"name":"ready-fixture","workspaces":["packages/*"],"scripts":{"lint":"eslint .","test":"jest"},"dependencies":{"left-pad":"1.3.0","react":"18.3.1"}}\n')
fx.write(coverage / "pnpm-workspace.yaml", "packages:\n  - packages/*\n")
fx.write(coverage / "services/api/pyproject.toml", '[project]\nname = "api-fixture"\ndependencies = ["fastapi>=0.1"]\n')
fx.write(coverage / "services/api/main.py", "def run():\n    return 'api'\n")
fx.write(coverage / "tools/java/pom.xml", "<project/>\n")
fx.write(coverage / "docs/CLAUDE.md", "# Notes\n" + "x" * (300 * 1024) + "\n")
fx.write(coverage / "vendor-copy/copied.ts", "export const copied = 1;\n")
full = index(coverage, "--exclude-dir", "vendor-copy", "--source", "src/lib.ts")
rows = {row["path"]: row for row in full["rule_files"]}
assert rows["RULES.md"].get("ownership") == "receipt-generated" and "reason" in rows["docs/CLAUDE.md"], rows
assert full["scan"].get("excluded_directories") == ["vendor-copy"] and full["scan"].get("explicit_sources") == ["src/lib.ts"], full["scan"]

seen = set()
for label, inventory in (("schema 4 fixture", receipt_time), ("coverage target", full)):
    assert sf.unknown_keys(inventory) == [], (label, sf.unknown_keys(inventory))
    sf.frame(inventory, outputs)
    seen |= seen_keys(inventory)
assert set(sf.KEY_CLASSES.values()) == {"walk", "frame", "drop"}, set(sf.KEY_CLASSES.values())
assert seen == set(sf.KEY_CLASSES), {"in the table, never written": sorted(set(sf.KEY_CLASSES) - seen), "written, not in the table": sorted(seen - set(sf.KEY_CLASSES))}
print("PASS: every inventory key the index writes is classified as frame or dropped")

# A key the table does not classify fails closed wherever it appears, and passes once it is classified.
places = {
    "planted": lambda value: value,
    "scan.planted": lambda value: value["scan"],
    "packages[].planted": lambda value: value["packages"][0],
    "packages[].manifests[].planted": lambda value: value["packages"][0]["manifests"][0],
    "rule_files[].planted": lambda value: value["rule_files"][0],
}
for key, place in places.items():
    planted = copy.deepcopy(full)
    place(planted)["planted"] = []
    assert sf.unknown_keys(planted) == [key], (key, sf.unknown_keys(planted))
    try:
        sf.frame(planted, outputs)
    except sf.FrameError as error:
        assert (error.kind, error.key) == ("unknown", key), (key, error.kind, error.key)
    else:
        raise AssertionError(f"frame() accepted the unclassified key {key}")
    sf.KEY_CLASSES[key] = "drop"
    try:
        assert sf.unknown_keys(planted) == [] and sf.frame(planted, outputs) == sf.frame(full, outputs), key
    finally:
        del sf.KEY_CLASSES[key]
print("RED control observed: a planted new inventory key fails the key-coverage check until it is classified")

# A projected key that is missing or has the wrong type raises FrameError naming its key path; any
# other exception (KeyError, TypeError, AttributeError) propagates here and fails this test.
def set_item(path, value):
    def mutate(inventory):
        *parents, last = path
        target = inventory
        for part in parents:
            target = target[part]
        target[last] = value
    return mutate

malformed = {
    "packages deleted": (lambda value: value.pop("packages"), "packages"),
    "packages a string": (set_item(["packages"], "x"), "packages"),
    "a package row a list": (set_item(["packages", 0], ["."]), "packages[]"),
    "a package path a number": (set_item(["packages", 0, "path"], 1), "packages[].path"),
    "a manifest row a list": (set_item(["packages", 0, "manifests", 0], ["package.json"]), "packages[].manifests[]"),
    "manifests a string": (set_item(["packages", 0, "manifests"], "package.json"), "packages[].manifests"),
    "scan a list": (set_item(["scan"], []), "scan"),
    "scan.complete missing": (lambda value: value["scan"].pop("complete"), "scan.complete"),
    "a rule_files path a number": (set_item(["rule_files", 0, "path"], 7), "rule_files[].path"),
    "workspace_files missing": (lambda value: value.pop("workspace_files"), "workspace_files"),
    "a workspace declaration a string": (set_item(["workspace_declarations", 0], "packages/*"), "workspace_declarations[]"),
    "limitations a string": (set_item(["limitations"], "none"), "limitations"),
    "the inventory a list": (None, "inventory"),
}
for label, (mutate, key) in malformed.items():
    value = copy.deepcopy(full)
    if mutate is None:
        value = [value]
    else:
        mutate(value)
    try:
        sf.frame(value, outputs)
    except sf.FrameError as error:
        assert (error.kind, error.key) == ("type", key), (label, error.kind, error.key)
    else:
        raise AssertionError(f"frame() accepted a malformed inventory: {label}")
print(f"PASS: {len(malformed)} missing or wrong-type inventory keys raise FrameError naming the key path")

# Ordinary evolution: each step changes the raw inventory bytes and none changes any frame part.
stable = tmp / "stable"
shutil.copytree(base, stable, symlinks=True)
steps = []
def step(label, change):
    before = (stable / INVENTORY).read_bytes()
    change()
    after = index(stable)
    assert (stable / INVENTORY).read_bytes() != before, f"{label}: the inventory did not change, so the step proves nothing"
    assert sf.frame(after, outputs) == reference, (label, changed_parts(reference, sf.frame(after, outputs)))
    steps.append(label)

step("a commit", lambda: (git(stable, "init", "-q"), git(stable, "add", "-A"), git(stable, "commit", "-q", "-m", "first")))
step("another commit", lambda: git(stable, "commit", "-q", "--allow-empty", "-m", "second"))
step("a visit-count change", lambda: fx.write(stable / "notes/todo.txt", "plain notes\n"))
step("new exclusion rows", lambda: (fx.write(stable / "build/out.js", "x\n"), fx.write(stable / ".DS_Store", "x"), fx.write(stable / "node_modules/a/index.js", "x\n")))
step("a lockfile row", lambda: fx.write(stable / "package-lock.json", '{"name":"ready-fixture","lockfileVersion":3,"packages":{}}\n'))
step("a manifest hash change", lambda: fx.write(stable / "package.json", (stable / "package.json").read_text().replace('"react":"18.3.1"', '"react":"18.3.2"')))
step("dependency and script edits outside the stack-signal set", lambda: fx.write(stable / "package.json", (stable / "package.json").read_text()
     .replace('"left-pad":"1.3.0"', '"is-even":"1.0.0"').replace('"lint":"eslint ."', '"build":"tsc","lint":"eslint ."')))
step("a sample edit", lambda: fx.write(stable / "src/lib.ts", (stable / "src/lib.ts").read_text().replace("let sum = 0;", "let sum = 0; // running total")))
assert len(steps) == 8, steps
print("PASS: commit, visit counts, exclusion rows, lockfile rows, manifest hashes, dependency and script lists and sample hashes leave the inventory frame unchanged")

fx.write(stable / "ai_rules/index/cards/a.md", "# Card a\n- exports a\n")
fx.write(stable / "ai_rules/index/stamp", "v1\n")
assert sf.frame(index(stable), outputs) == reference, "creating ai_rules/index changed the frame"
fx.write(stable / "ai_rules/index/cards/a.md", "# Card a\n- exports a and b\n")
fx.write(stable / "ai_rules/index/tables/b.json", '{"rows":[]}\n')
assert sf.frame(index(stable), outputs) == reference, "refreshing ai_rules/index changed the frame"
print("PASS: creating and refreshing ai_rules/index leaves the inventory frame unchanged")

# Structural changes move exactly the part that names them.
def changed_copy(name, change):
    target = tmp / name
    shutil.copytree(stable, target, symlinks=True)
    change(target)
    return changed_parts(reference, sf.frame(index(target), outputs))

parts = changed_copy("new-package", lambda target: fx.write(target / "packages/extra/package.json", '{"name":"extra-fixture"}\n'))
assert parts == {"packages"}, parts
print("RED control observed: a new package boundary changes the packages part of the frame")
parts = changed_copy("new-agents", lambda target: fx.write(target / "docs/AGENTS.md", "# Docs agents\nKeep examples short.\n"))
assert parts == {"policy_files"}, parts
parts = changed_copy("new-readme", lambda target: fx.write(target / "docs/README.md", "# Docs\nHow the docs are built.\n"))
assert parts == set(), parts
print("RED control observed: a new policy-class instruction file changes the policy_files part of the frame; a new README.md does not")
PY
printf 'All anchor fixtures passed.\n'
