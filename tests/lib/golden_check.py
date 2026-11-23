"""Compare the readiness check's output on schema 1 to 4 receipts with recorded golden files.

Usage: python3 -I -B tests/lib/golden_check.py [--checker <sh-gen-agents.sh>] [--golden <dir>] [--record <dir>]

Each case is built with ready_fixture in a new temporary folder outside the repository, then
`bash <checker> --check <case>` runs with stderr merged into stdout. The result, `exit <code>` on its
own line followed by the output, must equal `<golden dir>/<case>.txt` byte for byte. The golden files
were recorded once with the 0.7.0 checker, before any checker edit; --record refuses a folder that
is not empty, so a recorded file is never overwritten. --checker runs another checker (for example
one taken from the 0.7.0 release with git archive) on the same cases.
"""
import sys

sys.dont_write_bytecode = True
import argparse
import json
import subprocess
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
import ready_fixture

REPO = HERE.parent.parent
RECEIPT = ".claude/agents/.init-synthesis.json"
MEMORY = ".memory/40-active.md"
MEMORY_ROW = "- Keep each release note short and plain.\n"
NOTE = "- Session note: the tests passed.\n"
# The reject case: a changed non-memory ledger source fails, as it did in 0.7.0.
RED_CASE = "s4-ledger-source-changed"
RED_LINE = b"- policy source is missing, unsafe or stale: CONTRIBUTING.md\n"


def edit_receipt(root, change):
    value = json.loads((root / RECEIPT).read_text())
    change(value)
    ready_fixture.write(root / RECEIPT, json.dumps(value, indent=2) + "\n")


def edit_file(root, rel, change):
    old = (root / rel).read_text()
    new = change(old)
    assert new != old, f"the case edit left {rel} unchanged"
    ready_fixture.write(root / rel, new)


def schema1(root):
    # Schema 1 keeps three core skills; it would read the other two as badly named technology skills.
    ready_fixture.build(root, REPO)
    def change(value):
        value["schema_version"] = 1
        value["skills"] = [row for row in value["skills"] if row["name"] in ready_fixture.CORE[:3]]
    edit_receipt(root, change)


def schema3(root):
    # Schema 3 does not read the stack and rule_conflicts keys.
    ready_fixture.build(root, REPO, schema=4, ledger=True)
    def change(value):
        value["schema_version"] = 3
        del value["stack"], value["rule_conflicts"]
    edit_receipt(root, change)


def schema2(root):
    ready_fixture.build(root, REPO)


def schema4(root):
    ready_fixture.build(root, REPO, schema=4)


def schema4_ledger(root):
    ready_fixture.build(root, REPO, schema=4, ledger=True)


def then(base, *edits):
    def case(root):
        base(root)
        for edit in edits:
            edit(root)
    return case


def memory(change):
    return lambda root: edit_file(root, MEMORY, change)


CASES = {
    "s1-ready": schema1,
    "s2-ready": schema2,
    "s3-ledger-ready": schema3,
    "s3-memory-appended": then(schema3, memory(lambda text: text + NOTE)),
    "s4-ready": schema4,
    "s4-ledger-ready": schema4_ledger,
    "s4-memory-moved": then(schema4_ledger, memory(lambda text: text.replace(MEMORY_ROW, NOTE + MEMORY_ROW))),
    "s4-memory-ambiguous": then(schema4_ledger, memory(lambda text: text.replace(MEMORY_ROW, NOTE + MEMORY_ROW + MEMORY_ROW))),
    "s4-memory-changed": then(schema4_ledger, memory(lambda text: text.replace("short and plain", "short"))),
    "s2-stale-sample": then(schema2, lambda root: edit_file(root, "src/App.tsx", lambda text: text.replace("function App()", "function Main()", 1))),
    "s4-stale-module": then(schema4, lambda root: edit_file(root, "ai_rules/rules/coding.md", lambda text: text.replace("# Coding\n", "# Coding rules\n", 1))),
    "s4-missing-role": then(schema4, lambda root: edit_receipt(root, lambda value: value.__setitem__(
        "roles", [row for row in value["roles"] if row["name"] != "sdd-tester"]))),
    RED_CASE: then(schema4_ledger, lambda root: edit_file(root, "CONTRIBUTING.md", lambda text: text.replace("small and tested.", "small.", 1))),
}


def run_cases(checker):
    """Build every case in a new temporary folder and return {case: b"exit <code>\\n" + output}."""
    results = {}
    with tempfile.TemporaryDirectory(prefix="sh-golden.") as tmp:
        base = Path(tmp).resolve()
        if base == REPO.resolve() or REPO.resolve() in base.parents:
            raise SystemExit(f"refusing to build golden cases inside the repository: {base}")
        for name, make in CASES.items():
            root = base / name
            make(root)
            check = subprocess.run(["bash", str(checker), "--check", str(root)], stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            output = f"exit {check.returncode}\n".encode() + check.stdout
            for folder in {tmp, str(base)}:
                if folder.encode() in output:
                    raise SystemExit(f"case {name}: the output names its temporary folder; a golden file must not hold an absolute path")
            results[name] = output
    return results


def red_case_holds(results):
    output = results.get(RED_CASE, b"")
    return output.startswith(b"exit 1\n") and RED_LINE in output


def first_difference(recorded, current):
    old, new = recorded.decode("utf-8", "replace").splitlines(), current.decode("utf-8", "replace").splitlines()
    for number in range(1, max(len(old), len(new)) + 1):
        a = old[number - 1] if number <= len(old) else "<end of file>"
        b = new[number - 1] if number <= len(new) else "<end of output>"
        if a != b:
            return number, a, b
    return len(old), "<same lines>", "<different line endings or final newline>"


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--checker", default=str(REPO / "bin/sh-gen-agents.sh"))
    parser.add_argument("--golden", default=str(REPO / "tests/fixtures/checker-golden"))
    parser.add_argument("--record", metavar="DIR")
    args = parser.parse_args()
    if args.record:
        folder = Path(args.record)
        if folder.exists() and (not folder.is_dir() or any(folder.iterdir())):
            print(f"REFUSED: {folder} is not an empty folder; golden files are recorded once and never overwritten")
            return 1
        results = run_cases(args.checker)
        if not red_case_holds(results):
            print(f"REFUSED: case {RED_CASE} did not fail with the stale policy source line; nothing was recorded")
            return 1
        folder.mkdir(parents=True, exist_ok=True)
        for name, output in results.items():
            (folder / f"{name}.txt").write_bytes(output)
        print(f"RECORDED: {len(results)} golden files in {folder}")
        return 0
    golden = Path(args.golden)
    results = run_cases(args.checker)
    failed = 0
    for name, current in results.items():
        path = golden / f"{name}.txt"
        if not path.is_file():
            print(f"FAIL: golden case {name} has no recorded file: {path}")
            failed += 1
            continue
        recorded = path.read_bytes()
        if recorded != current:
            number, old, new = first_difference(recorded, current)
            print(f"FAIL: golden case {name} differs from {path} at line {number}")
            print(f"  recorded: {old}")
            print(f"  current:  {new}")
            failed += 1
    if failed:
        print(f"FAIL: {failed} of {len(results)} schema 1 to 4 receipts differ from the recorded 0.7.0 checker output")
        return 1
    if not red_case_holds(results):
        print(f"FAIL: case {RED_CASE} no longer fails with the stale policy source line")
        return 1
    print(f"PASS: {len(results)} schema 1 to 4 receipts match the recorded 0.7.0 checker output byte for byte")
    print("RED control observed: a schema 4 receipt with a changed non-memory ledger source still fails exactly as the 0.7.0 checker did")
    return 0


if __name__ == "__main__":
    sys.exit(main())
