"""The inventory frame: the structural part of ai_rules/project_inventory.json that package rules rely on.

frame(inventory, outputs) returns {"version": FRAME_VERSION, "parts": {part: sha256}} with one hash per
part (packages, workspace, scan, limitations, policy_files), so a refusal can name the part that
changed. A commit, visit counts, exclusion rows, lockfile rows, manifest hashes, dependency and script
names and sample hashes are not in it. KEY_CLASSES classifies every key the indexer writes as "walk" (a
container whose children are classified), "frame" or "drop"; an unclassified key, or a projected key
that is missing or has the wrong type, raises FrameError, so an inventory this table does not know
fails closed. Key paths write list items as [], for example packages[].manifests[].path.

Standard library only: no clock, no randomness, no subprocess.
"""
import hashlib
import json
FRAME_VERSION = 1
# The frame's parts, in the order a changed-parts message lists them.
FRAME_PARTS = ("packages", "workspace", "scan", "limitations", "policy_files")

# Files the harness installs or generates. They are never project policy, whatever their bytes.
HARNESS_POLICY_PATHS = {"ai_rules/rules/frequent_rules.md", "ai_rules/globalRules.md", "ai_rules/updated_rules.md", "ai_rules/review-lens.md", "ai_rules/stack.md", "ai_rules/rules/core.md", "ai_rules/rules/context_management.md"}
HARNESS_POLICY_PREFIXES = (".claude/commands/", ".claude/spec-harness/", ".claude/agents/", ".claude/skills/", ".agents/", "ai_rules/index/")

KEY_CLASSES = {
    # Identity and integrity: checked by the readiness check itself.
    "format": "drop", "schema_version": "drop", "generated_by": "drop", "integrity": "drop",
    "project_root_name": "drop",
    "scan": "walk",
    "scan.scope": "frame", "scan.source_scan_read_only": "frame", "scan.complete": "frame", "scan.limits": "frame",
    "scan.excluded_directories": "frame", "scan.explicit_sources": "frame",
    "scan.visited_directories": "drop", "scan.visited_files": "drop", "scan.source_head": "drop",
    "packages": "walk",
    "packages[].path": "frame", "packages[].names": "frame", "packages[].stack_signals": "frame", "packages[].entrypoints": "frame",
    # Names are compared against a recorded baseline; samples are bound by citation anchors.
    "packages[].scripts": "drop", "packages[].dependencies": "drop", "packages[].representative_sources": "drop",
    "packages[].applicable_instructions": "drop",
    "packages[].manifests": "walk",
    "packages[].manifests[].path": "frame", "packages[].manifests[].format": "frame", "packages[].manifests[].status": "frame",
    "packages[].manifests[].workspace_patterns": "frame",
    "packages[].manifests[].reason": "drop", "packages[].manifests[].name": "drop", "packages[].manifests[].scripts": "drop",
    "packages[].manifests[].dependencies": "drop", "packages[].manifests[].stack_signals": "drop",
    "packages[].manifests[].entrypoints": "drop", "packages[].manifests[].sha256": "drop",
    "rule_files": "walk",
    # Path and read status count only for policy-class rows (see frame()).
    "rule_files[].path": "frame", "rule_files[].read_status": "frame",
    "rule_files[].kind": "drop", "rule_files[].ownership": "drop", "rule_files[].sha256": "drop", "rule_files[].bytes": "drop",
    "rule_files[].reason": "drop",
    "workspace_declarations": "walk",
    "workspace_declarations[].owner": "frame", "workspace_declarations[].pattern": "frame",
    "workspace_files": "walk",
    "workspace_files[].path": "frame", "workspace_files[].format": "frame", "workspace_files[].status": "drop",
    "lockfiles": "drop", "exclusions": "drop", "limitations": "frame",
}


class FrameError(ValueError):
    """The frame cannot be computed. kind is "unknown" (a key KEY_CLASSES does not classify) or "type"
    (a projected key is missing or has the wrong type); key is that key path."""

    def __init__(self, kind, key):
        super().__init__(f"{kind}: {key}")
        self.kind, self.key = kind, key


def is_harness_owned(path):
    return path in HARNESS_POLICY_PATHS or path.startswith(HARNESS_POLICY_PREFIXES)


def receipt_outputs(receipt):
    """Every rules_path and rule_modules[].path of the receipt. Malformed rows are skipped; the readiness
    check reports them with its own messages."""
    outputs = set()
    rows = receipt.get("packages") if isinstance(receipt, dict) else None
    for row in rows if isinstance(rows, list) else []:
        if not isinstance(row, dict):
            continue
        if isinstance(row.get("rules_path"), str):
            outputs.add(row["rules_path"])
        modules = row.get("rule_modules")
        for module in modules if isinstance(modules, list) else []:
            if isinstance(module, dict) and isinstance(module.get("path"), str):
                outputs.add(module["path"])
    return outputs


def unknown_keys(inventory):
    """Every key path present in the inventory that KEY_CLASSES does not classify, sorted."""
    found = set()

    def walk(value, prefix):
        if isinstance(value, list):
            for item in value:
                if isinstance(item, dict):
                    walk(item, prefix + "[]")
        elif isinstance(value, dict):
            for key, child in value.items():
                path = f"{prefix}.{key}" if prefix else key
                kind = KEY_CLASSES.get(path)
                if kind is None:
                    found.add(path)
                elif kind == "walk":
                    walk(child, path)

    walk(inventory, "")
    return sorted(found)


def _row(value, path):
    if not isinstance(value, dict):
        raise FrameError("type", path)
    return value


def _get(row, key, kind, path, default=None):
    value = row.get(key, default)
    if not isinstance(value, kind):
        raise FrameError("type", path)
    return value


def _digest(value):
    # The canonical form the readiness check uses for the inventory's integrity.
    return hashlib.sha256(json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")).encode("utf-8")).hexdigest()


def frame(inventory, outputs):
    """The versioned frame of an inventory. outputs are the receipt's rule outputs (receipt_outputs)."""
    _row(inventory, "inventory")
    unknown = unknown_keys(inventory)
    if unknown:
        raise FrameError("unknown", unknown[0])
    packages = []
    for row in _get(inventory, "packages", list, "packages"):
        row = _row(row, "packages[]")
        manifests = []
        for manifest in _get(row, "manifests", list, "packages[].manifests"):
            manifest = _row(manifest, "packages[].manifests[]")
            manifests.append({
                "path": _get(manifest, "path", str, "packages[].manifests[].path"),
                "format": _get(manifest, "format", str, "packages[].manifests[].format"),
                "status": _get(manifest, "status", str, "packages[].manifests[].status"),
                "workspace_patterns": _get(manifest, "workspace_patterns", list, "packages[].manifests[].workspace_patterns", []),
            })
        packages.append({
            "path": _get(row, "path", str, "packages[].path"),
            "names": _get(row, "names", list, "packages[].names"),
            "stack_signals": _get(row, "stack_signals", list, "packages[].stack_signals"),
            "entrypoints": _get(row, "entrypoints", list, "packages[].entrypoints"),
            "manifests": manifests,
        })
    declarations = []
    for row in _get(inventory, "workspace_declarations", list, "workspace_declarations"):
        row = _row(row, "workspace_declarations[]")
        declarations.append({"owner": _get(row, "owner", str, "workspace_declarations[].owner"),
                             "pattern": _get(row, "pattern", str, "workspace_declarations[].pattern")})
    files = []
    for row in _get(inventory, "workspace_files", list, "workspace_files"):
        row = _row(row, "workspace_files[]")
        files.append({"path": _get(row, "path", str, "workspace_files[].path"),
                      "format": _get(row, "format", str, "workspace_files[].format")})
    scan_row = _get(inventory, "scan", dict, "scan")
    scan = {
        "scope": _get(scan_row, "scope", str, "scan.scope"),
        "source_scan_read_only": _get(scan_row, "source_scan_read_only", bool, "scan.source_scan_read_only"),
        "complete": _get(scan_row, "complete", bool, "scan.complete"),
        "limits": _get(scan_row, "limits", dict, "scan.limits"),
        "excluded_directories": _get(scan_row, "excluded_directories", list, "scan.excluded_directories", []),
        "explicit_sources": _get(scan_row, "explicit_sources", list, "scan.explicit_sources", []),
    }
    limitations = _get(inventory, "limitations", list, "limitations")
    # Policy class: not a README, not a receipt output, not a harness file.
    policy = []
    for row in _get(inventory, "rule_files", list, "rule_files"):
        row = _row(row, "rule_files[]")
        path = _get(row, "path", str, "rule_files[].path")
        status = _get(row, "read_status", str, "rule_files[].read_status")
        if path.rsplit("/", 1)[-1] != "README.md" and path not in outputs and not is_harness_owned(path):
            policy.append([path, status])
    parts = {"packages": packages, "workspace": {"declarations": declarations, "files": files}, "scan": scan,
             "limitations": limitations, "policy_files": sorted(policy)}
    return {"version": FRAME_VERSION, "parts": {name: _digest(parts[name]) for name in FRAME_PARTS}}
