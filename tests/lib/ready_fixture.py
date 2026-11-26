"""Build a small target whose `generate-agents --check` prints READY. Shared by contract tests.

The inventory is written first and the synthesis outputs after it, as in a real initialization, so a
later `index` sees more files: that is the binding-only refresh finalize-init exists for.

schema=2 writes a schema 2 receipt. schema=4 also writes a stack row, a project rule module with one
rule line, an indented cited span (src/lib.ts:2-3) and the instruction files the drift check hashes.
ledger=True adds a prose, a config and a memory policy source with one ledger row per requirement.
"""
import hashlib
import json
import os
import subprocess
from pathlib import Path

CORE = ["spec-harness-architecture", "spec-harness-performance", "spec-harness-packages",
        "spec-harness-quality", "spec-harness-conduct"]
ROLES = ["sdd-planner", "sdd-implementer", "sdd-tester", "sdd-verifier", "sdd-reviewer"]

# Schema 4 instruction files, written before indexing so the inventory hashes them. The rule-pack
# README is a harness-owned file, as the installer stages it.
INSTRUCTION_FILES = {
    "AGENTS.md": "# Agent notes\n\nRead RULES.md before you change code.\n",
    "README.md": "# Ready fixture\n\nA small synthetic project for the readiness check.\n",
    ".claude/spec-harness/rule-packs/README.md": "# Rule packs\n\nCurated rule packs staged by the installer.\n",
}
# Ledger sources: prose, config and memory. Every row's span is one whole item.
LEDGER_SOURCES = {
    "CONTRIBUTING.md": "# Contributing\n\nThank you for helping. Keep every change small and tested.\n\n"
                       "- Export named functions from each source file.\n"
                       "- Run the lint script before you hand over a change.\n",
    "ci/pipeline.yml": "steps:\n  - run: npm test\n  - run: npm run lint\n",
    ".memory/40-active.md": "# Active context\n\n- Keep each release note short and plain.\n",
}
LEDGER_ROWS = [
    ("CONTRIB-1", "CONTRIBUTING.md", 5, {"disposition": "captured", "rule_path": "ai_rules/rules/coding.md", "rule_anchor": "CODE-01"}),
    ("CONTRIB-2", "CONTRIBUTING.md", 6, {"disposition": "not-applicable", "reason": "A working habit, not a code rule."}),
    ("PIPE-1", "ci/pipeline.yml", 2, {"disposition": "not-applicable", "reason": "The pipeline runs the tests; no code rule restates it."}),
    ("PIPE-2", "ci/pipeline.yml", 3, {"disposition": "not-applicable", "reason": "The pipeline runs the linter; no code rule restates it."}),
    ("MEM-1", ".memory/40-active.md", 3, {"disposition": "not-applicable", "reason": "Release notes are not package code."}),
]


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write(path, text):
    path = Path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text if isinstance(text, bytes) else text.encode())
    return path


def build(root, harness, index_args=(), schema=2, ledger=False):
    assert schema in (2, 4), f"unsupported fixture schema {schema!r}"
    assert not ledger or schema >= 4, "ledger=True needs schema 4"
    root, harness = Path(root), Path(harness)
    if schema == 2:
        write(root / "package.json", '{"name":"ready-fixture","scripts":{"test":"jest"},"dependencies":{"react":"18.3.1"}}\n')
    else:
        # left-pad is outside the stack-signal dependency set and named by no tool module.
        write(root / "package.json", '{"name":"ready-fixture","scripts":{"lint":"eslint .","test":"jest"},"dependencies":{"left-pad":"1.3.0","react":"18.3.1"}}\n')
    write(root / "src/App.tsx", "export function App() {\n  return null;\n}\n")
    write(root / "ai_rules/context_map.md", "# Team map\nKept as written.\n")
    write(root / "ai_rules/rules/frequent_rules.md", "# Frequent rules\n- Read the package rules before a change.\n")
    if schema >= 4:
        write(root / "src/lib.ts", "export function total(values: number[]): number {\n  let sum = 0;\n  for (const value of values) sum += value;\n  return sum;\n}\n")
        for rel, text in {**INSTRUCTION_FILES, **(LEDGER_SOURCES if ledger else {})}.items():
            write(root / rel, text)
    result = subprocess.run(["bash", str(harness / "bin/sh-index.sh"), str(root), *index_args], capture_output=True, text=True)
    assert result.returncode == 0, result.stderr
    if schema >= 4:
        result = subprocess.run(["bash", str(harness / "bin/spec-harness"), "stack", str(root)], capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
    inventory_path = root / "ai_rules/project_inventory.json"
    inventory = json.loads(inventory_path.read_text())
    inventory_hash = sha(inventory_path.read_bytes())
    samples = [row for row in inventory["packages"][0]["representative_sources"] if row["read_status"] == "read"]
    source = samples[0] if schema == 2 else next(row for row in samples if row["path"] == "src/App.tsx")
    citation = {"package_path": ".", "path": source["path"], "line_start": 1, "line_end": 2, "sha256": source["sha256"]}
    cited = f"{source['path']}:1-2"
    # Schema 2 skills and roles cite the package sample; schema 4 skills and roles cite an indented span.
    output_citation, output_cited = citation, cited
    if schema >= 4:
        lib = next(row for row in samples if row["path"] == "src/lib.ts")
        output_citation = {"package_path": ".", "path": "src/lib.ts", "line_start": 2, "line_end": 3, "sha256": lib["sha256"]}
        output_cited = "src/lib.ts:2-3"
    marker = f"<!-- source-bound: inventory-sha256={inventory_hash} -->\n"
    bound = f" inventory-sha256={inventory_hash}"
    module_text = f"# Coding\n\n{marker}- [OBSERVED] Export named functions. Evidence: {cited}\n"
    if schema >= 4:
        module_text += f"<!-- rule-layer: project -->\n- **CODE-01** Export named functions from each source file. (source: {cited})\n"
    module = write(root / "ai_rules/rules/coding.md", module_text)
    rules = write(root / "RULES.md", "".join(f"## {name}\n- [OBSERVED] Follow the opened source. Evidence: {cited}\n\n" for name in ("Coding", "Architecture", "Packages", "Testing", "Reviewing")) + "## Modules\n- [coding](ai_rules/rules/coding.md)\n")
    skills = []
    for name in CORE:
        path = f".claude/skills/{name}/SKILL.md"
        file = write(root / path, f"# {name}\n\nPackage applicability: .\n\n{marker}Evidence: {output_cited}\n")
        skills.append({"name": name, "status": "READY", "path": path, "sha256": sha(file.read_bytes()),
                       "package_paths": ["."], "citations": [output_citation]})
    roles = []
    for name in ROLES:
        path = f".claude/agents/{name}.md"
        fresh = "Run in a fresh context.\n" if name in ("sdd-tester", "sdd-verifier", "sdd-reviewer") else ""
        file = write(root / path, f"# {name}\n\nRole text outside the generated block.\n\n<!-- GEN:rules START -->\nPackage: .\n[OBSERVED] Follow {output_cited}.\n{fresh}<!-- bound: 2026-10-13{bound} -->\n<!-- GEN:rules END -->\n\nMore role text.\n")
        roles.append({"name": name, "status": "BOUND", "path": path, "sha256": sha(file.read_bytes()),
                      "package_paths": ["."], "citations": [output_citation], "selection_reason": "Required role."})
    receipt = {
        "format": "spec-harness-synthesis", "schema_version": schema, "status": "READY",
        "inventory_path": "ai_rules/project_inventory.json", "inventory_sha256": inventory_hash,
        "package_paths": ["."],
        "packages": [{"path": ".", "status": "READY", "rules_path": "RULES.md", "sha256": sha(rules.read_bytes()),
                      "citations": [citation],
                      "rule_modules": [{"name": "coding", "path": "ai_rules/rules/coding.md", "sha256": sha(module.read_bytes()), "citations": [citation]}]}],
        "skills": skills, "roles": roles, "excluded_roles": [], "pending_reasons": [],
    }
    if schema >= 4:
        receipt["stack"] = {"path": "ai_rules/stack.md", "sha256": sha((root / "ai_rules/stack.md").read_bytes())}
        receipt["rule_conflicts"] = []
    if ledger:
        hashes = {rel: sha((root / rel).read_bytes()) for rel in LEDGER_SOURCES}
        receipt["policy_sources"] = [{"path": rel, "sha256": hashes[rel], "requirement_ids": [row[0] for row in LEDGER_ROWS if row[1] == rel]}
                                     for rel in LEDGER_SOURCES]
        receipt["policy_coverage"] = []
        for requirement, rel, line, fields in LEDGER_ROWS:
            row = {"id": requirement, "path": rel, "sha256": hashes[rel], "line_start": line, "line_end": line}
            if rel.startswith(".memory/"):
                # A memory row carries its text anchor, so an ordinary memory edit keeps it found by text.
                row["text_sha256"] = sha(LEDGER_SOURCES[rel].splitlines()[line - 1].encode())
            row.update(fields)
            receipt["policy_coverage"].append(row)
    write(root / ".claude/agents/.init-synthesis.json", json.dumps(receipt, indent=2) + "\n")
    result = subprocess.run(["bash", str(harness / "bin/sh-gen-agents.sh"), "--check", str(root)], capture_output=True, text=True)
    assert result.returncode == 0, result.stdout + result.stderr
    return receipt


def snapshot(root, with_dirs=False):
    """Map each regular file under root to its bytes. with_dirs=True also lists every directory (value
    None) and every symbolic link (value ("link", target)), so a new folder or link counts as a write."""
    root = Path(root)
    result = {}
    for path in sorted(root.rglob("*")):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            if with_dirs:
                result[rel] = ("link", os.readlink(path))
        elif path.is_file():
            result[rel] = path.read_bytes()
        elif with_dirs and path.is_dir():
            result[rel] = None
    return result
