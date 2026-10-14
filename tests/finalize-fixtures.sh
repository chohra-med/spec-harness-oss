#!/usr/bin/env bash
# finalize-init: dry run by default, journaled apply, exact recovery after a hard crash before or
# after every write, SIGINT/SIGTERM rollback, leftover temporaries, a lock against two finalizers,
# and refusal of tampered, linked, FIFO, oversized or unbound journals and of recovery after success.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
# shellcheck source=lib/portable.sh
. "$ROOT/tests/lib/portable.sh"
require_tools bash
require_python311
TMP="$(mktemp -d "${TMPDIR:-/tmp}/sh-finalize.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

python3 -u -I -B - "$ROOT" "$TMP" <<'PY'
import base64, json, os, shutil, signal, subprocess, sys, time
from pathlib import Path

harness, tmp = Path(sys.argv[1]), Path(sys.argv[2])
sys.path.insert(0, str(harness / "tests/lib"))
import ready_fixture as fx

CLI = ["bash", str(harness / "bin/spec-harness")]
FINALIZE = str(harness / "bin/sh-finalize-init.py")
LOCK = ".claude/agents/.sh-finalize.lock"


def run(args, expected, label, cwd=None):
    result = subprocess.run(args, capture_output=True, text=True, cwd=cwd)
    output = result.stdout + result.stderr
    assert result.returncode == expected, f"{label}: expected exit {expected}, got {result.returncode}\n{output}"
    return output


def finalize(target, *extra, expected=0, label="finalize", cwd=None):
    return run(CLI + ["finalize-init", str(target), *extra], expected, label, cwd=cwd)


# A hook runner: loads the finalizer as a module, patches one function, then runs main().
HOOK = r'''
import importlib.util, os, signal, sys, time
spec = importlib.util.spec_from_file_location("finalizer", sys.argv[1])
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
mode, number = sys.argv[4], int(sys.argv[5])
count = [0]
original_replace = module.replace
def counted_replace(*args):
    count[0] += 1
    if mode in ("restore-fails", "restore-conflict", "error-then-sigint-in-restore") and count[0] == number:
        raise OSError("planted write failure")
    if mode == "double-signal" and count[0] == number:
        # Probe: the first SIGINT raises Interrupted; a second SIGINT lands while the first unwinds.
        try:
            os.kill(os.getpid(), signal.SIGINT)
        except module.Interrupted:
            state = "SIG_IGN" if signal.getsignal(signal.SIGINT) == signal.SIG_IGN else "handler"
            print("PROBE first-handler=" + state, file=sys.stderr)
            try:
                os.kill(os.getpid(), signal.SIGINT)
                print("PROBE second-signal=ignored", file=sys.stderr)
            except module.Interrupted:
                print("PROBE second-signal=raised", file=sys.stderr)
            raise
    if mode == "crash-before" and count[0] == number:
        os._exit(23)
    original_replace(*args)
    if mode == "crash-after" and count[0] == number:
        os._exit(23)
    if mode in ("SIGINT", "SIGTERM") and count[0] == number:
        os.kill(os.getpid(), getattr(signal, mode))
        time.sleep(1)
module.replace = counted_replace
if mode == "restore-fails":
    def failing_restore(*args):
        raise OSError("planted restore failure")
    module.restore = failing_restore
if mode == "error-then-sigint-in-restore":
    original_restore_sig = module.restore
    def sigint_restore(root, journal, evidence):
        os.kill(os.getpid(), signal.SIGINT)
        return original_restore_sig(root, journal, evidence)
    module.restore = sigint_restore
if mode == "restore-conflict":
    # A human edit to the written inventory lands before the rollback reads it: a conflict.
    original_restore = module.restore
    def conflicting_restore(root, journal, evidence):
        with open(os.path.join(root, "ai_rules/project_inventory.json"), "ab") as handle:
            handle.write(b"\n")
        return original_restore(root, journal, evidence)
    module.restore = conflicting_restore
if mode == "crash-at-rename":
    real = module.os.replace
    def rename(src, dst, **kwargs):
        if str(src).startswith(module.TEMP_PREFIX):
            count[0] += 1
            if count[0] == number:
                os._exit(23)
        return real(src, dst, **kwargs)
    module.os.replace = rename
if mode == "edit-before-rename":
    # The third read of the inventory is the re-hash just before its rename; a human edits first.
    original_read = module.read_target
    reads = [0]
    def read_with_edit(root, path):
        if path == "ai_rules/project_inventory.json":
            reads[0] += 1
            if reads[0] == number:
                with open(os.path.join(root, path), "ab") as handle:
                    handle.write(b"\n")
        return original_read(root, path)
    module.read_target = read_with_edit
if mode == "sigint-after-lock":
    # The lock window: a SIGINT lands right after the lock file exists (the old code had no handler yet).
    original_acquire = module.acquire_lock
    def acquire_then_sigint(root):
        original_acquire(root)
        os.kill(os.getpid(), signal.SIGINT)
    module.acquire_lock = acquire_then_sigint
if mode in ("lock-sync-fails", "lock-sync-fails-sigint"):
    # The first fsync while the lock file exists is the lock's own: it fails, and with the -sigint mode a
    # SIGINT is sent first, so the signal is held back by take_lock and lands after the error.
    real_full_sync = module.full_sync
    lock_syncs = [0]
    def failing_lock_sync(fd):
        if lock_syncs[0] == 0 and os.path.exists(os.path.join(sys.argv[2], ".claude/agents/.sh-finalize.lock")):
            lock_syncs[0] += 1
            if mode == "lock-sync-fails-sigint":
                os.kill(os.getpid(), signal.SIGINT)
            raise OSError("planted lock sync failure")
        return real_full_sync(fd)
    module.full_sync = failing_lock_sync
if mode == "release-sigint":
    # A SIGINT lands after STRUCTURAL_READY is recorded, at the release call in apply's finally.
    original_release = module.release_lock
    def release_with_sigint(root):
        os.kill(os.getpid(), signal.SIGINT)
        return original_release(root)
    module.release_lock = release_with_sigint
if mode == "slow-tool":
    # A tool step that outlives the timeout: the check sleeps 150 s against a two-second limit.
    module.TOOL_TIMEOUT = 2
    module.check_command = lambda root: [sys.executable, "-c", "import time; time.sleep(150)"]
if mode == "slow":
    original_plan = module.plan
    def slow_plan(*args, **kwargs):
        time.sleep(number)
        return original_plan(*args, **kwargs)
    module.plan = slow_plan
try:
    sys.exit(module.main([sys.argv[2], "--apply", "--evidence-dir", sys.argv[3]]))
except module.Refused as error:
    print("PENDING: " + str(error), file=sys.stderr)
    sys.exit(1)
except module.Interrupted as error:
    # Mirrors the finalizer's __main__: an interrupt that unwinds out of apply() exits 130.
    print("PENDING: interrupted by " + str(error), file=sys.stderr)
    sys.exit(130)
'''


def hooked(target, evidence, mode, number, expected, label):
    return run([sys.executable, "-I", "-B", "-c", HOOK, FINALIZE, str(target), str(evidence), mode, str(number)], expected, label)


start = tmp / "start"
fx.build(start, harness)
initial = fx.snapshot(start)
print("PASS: READY fixture built (inventory first, synthesis outputs after)")

# 1. Dry run is the default and writes nothing.
target = tmp / "dry"
shutil.copytree(start, target)
out = finalize(target, label="dry run")
assert "DRY-RUN" in out and "WRITE ai_rules/project_inventory.json" in out and "planned writes    : 13" in out, out
assert fx.snapshot(target) == initial and not (target / LOCK).exists()
out = finalize(target, "--dry-run", label="explicit dry run")
assert "nothing was written" in out and fx.snapshot(target) == initial
finalize(target, "--apply", expected=1, label="apply without evidence dir")
inside = finalize(target, "--apply", "--evidence-dir", str(target / "evidence"), expected=1, label="evidence inside target")
assert "outside the target" in inside and fx.snapshot(target) == initial
print("PASS: dry run (default and --dry-run) prints 13 planned writes and changes no byte")

# 2. Apply, check, repeat: the second run writes nothing (a fixed point across runs).
target = tmp / "apply"
shutil.copytree(start, target)
out = finalize(target, "--apply", "--evidence-dir", str(tmp / "apply-ev"), label="apply")
assert "STRUCTURAL_READY" in out and "wrote 13 file(s)" in out, out
assert "READY:" in run(CLI + ["generate-agents", "--check", str(target)], 0, "check after apply")
after = fx.snapshot(target)
for path in (".claude/agents/sdd-reviewer.md",):
    before_text, after_text = initial[path].decode(), after[path].decode()
    outside = lambda text: text[:text.index("<!-- GEN:rules START -->")] + text[text.index("<!-- GEN:rules END -->"):]
    assert outside(before_text) == outside(after_text), "role bytes outside GEN changed"
assert after["RULES.md"] == initial["RULES.md"] and after["src/App.tsx"] == initial["src/App.tsx"]
out = finalize(target, "--apply", "--evidence-dir", str(tmp / "apply-ev2"), label="repeat apply")
assert "wrote 0 file(s)" in out and fx.snapshot(target) == after, out
journal = json.loads((tmp / "apply-ev/journal.json").read_text())
assert journal["status"] == "STRUCTURAL_READY" and journal["semantic_review"] == "PENDING"
writes = sum(bool(row["expected_after"]) for row in journal["files"].values())
assert writes == 13, writes
print("PASS: apply writes 13 files, keeps role text outside GEN and human rules, and a repeat writes 0")

# 3. Recover after success is refused and keeps the result.
out = finalize(target, "--recover", "--evidence-dir", str(tmp / "apply-ev"), expected=1, label="recover after success")
assert "nothing to recover" in out and fx.snapshot(target) == after
print("RED control observed: --recover after STRUCTURAL_READY is refused and the result is kept")

# 4. Hard crash before and after every write, then --recover restores the exact prior bytes.
for mode in ("crash-before", "crash-after"):
    for number in range(1, writes + 1):
        target = tmp / f"{mode}-{number}"
        shutil.copytree(start, target)
        evidence = tmp / f"{mode}-{number}-ev"
        hooked(target, evidence, mode, number, 23, f"{mode} {number}")
        assert (target / LOCK).exists(), "a crashed run leaves its lock"
        blocked = finalize(target, "--apply", "--evidence-dir", str(tmp / f"{mode}-{number}-other"), expected=1, label="apply over a stale lock")
        assert "another finalize-init holds" in blocked
        out = finalize(target, "--recover", "--evidence-dir", str(evidence), label=f"recover {mode} {number}")
        assert "RECOVERED" in out, out
        assert fx.snapshot(target) == initial, (mode, number)
        shutil.rmtree(target)
print(f"PASS: exact recovery after a hard crash before and after each of the {writes} writes; the stale lock blocks a new apply until --recover")

# 5. A crash between writing the temporary file and renaming it leaves a .sh-finalize-* file.
target = tmp / "temp-crash"
shutil.copytree(start, target)
evidence = tmp / "temp-crash-ev"
hooked(target, evidence, "crash-at-rename", 2, 23, "crash at rename")
leftovers = [path for path in target.rglob(".sh-finalize-*")]
assert leftovers, "the crash left no temporary file"
out = finalize(target, "--recover", "--evidence-dir", str(evidence), label="recover temporaries")
assert "RECOVERED" in out and "1 leftover temporary file(s) removed" in out, out
assert not list(target.rglob(".sh-finalize-*")) and fx.snapshot(target) == initial
print("PASS: --recover removes the leftover .sh-finalize-* temporary and restores the prior bytes")

# 6. SIGINT and SIGTERM during the writes roll back through the journal.
for sig in ("SIGINT", "SIGTERM"):
    target = tmp / f"{sig}-target"
    shutil.copytree(start, target)
    evidence = tmp / f"{sig}-ev"
    out = hooked(target, evidence, sig, 3, 130, sig)
    assert "rolled back" in out, out
    assert fx.snapshot(target) == initial and not (target / LOCK).exists()
    assert json.loads((evidence / "journal.json").read_text())["status"] == "ROLLED_BACK"
print("PASS: SIGINT and SIGTERM during writes roll every write back, release the lock and exit 130")

# 6b. A human edit that lands after the plan but before the rename is preserved, not overwritten.
target = tmp / "late-edit"
shutil.copytree(start, target)
out = hooked(target, tmp / "late-edit-ev", "edit-before-rename", 3, 1, "edit before rename")
assert "concurrent edit preserved: ai_rules/project_inventory.json" in out, out
assert (target / "ai_rules/project_inventory.json").read_bytes() == initial["ai_rules/project_inventory.json"] + b"\n"
print("RED control observed: the re-hash right before the rename keeps a late human edit")

# 6c. H5: a failed rollback keeps the lock, so a second finalizer is refused and --recover adopts it.
for mode, expected_status, label in (("restore-fails", "RECOVERY_FAILED", "rollback fails"),
                                     ("restore-conflict", "RECOVERY_CONFLICT", "rollback conflicts")):
    target = tmp / f"lock-{mode}"
    shutil.copytree(start, target)
    evidence = tmp / f"lock-{mode}-ev"
    out = hooked(target, evidence, mode, 2, 1, label)
    assert json.loads((evidence / "journal.json").read_text())["status"] == expected_status
    assert (target / LOCK).exists(), f"{expected_status} must keep the lock; output: {out}"
    if mode == "restore-fails":
        assert "lock kept; run --recover" in out, out
    else:
        # A conflict is not fixed by --recover alone: the message must name the manual step.
        assert "then run --recover" in out and "journal.json" in out and '"before"' in out, out
    blocked = finalize(target, "--apply", "--evidence-dir", str(tmp / f"lock-{mode}-other"), expected=1, label=f"apply after {label}")
    assert "another finalize-init holds" in blocked, blocked
    if mode == "restore-conflict":
        stuck = finalize(target, "--recover", "--evidence-dir", str(evidence), expected=1, label="recover while the conflict stands")
        assert "then run --recover" in stuck and (target / LOCK).exists(), stuck
        # The documented manual step: put the file back to the bytes its journal entry records, then --recover.
        row = json.loads((evidence / "journal.json").read_text())["files"]["ai_rules/project_inventory.json"]
        (target / "ai_rules/project_inventory.json").write_bytes(base64.b64decode(row["before"]))
        out = finalize(target, "--recover", "--evidence-dir", str(evidence), label="recover after the manual step")
        assert "RECOVERED" in out and fx.snapshot(target) == initial and not (target / LOCK).exists(), out
    if mode == "restore-fails":
        out = finalize(target, "--recover", "--evidence-dir", str(evidence), label="recover after failed rollback")
        assert "RECOVERED" in out and fx.snapshot(target) == initial and not (target / LOCK).exists(), out
print("RED control observed: a failed rollback keeps the lock; --recover adopts it and restores the prior bytes")

# PROBE-6e: a SIGINT that lands during the rollback of a non-signal failure must not abort the rollback.
target = tmp / "sig-in-restore"
shutil.copytree(start, target)
evidence = tmp / "sig-in-restore-ev"
out = hooked(target, evidence, "error-then-sigint-in-restore", 2, 1, "signal during rollback")
journal_status = json.loads((evidence / "journal.json").read_text())["status"]
print("PROBE-6e status=" + journal_status + " lock_exists=" + str((target / LOCK).exists()) + " out=" + out.replace(chr(10), " | "), file=sys.stderr)
assert journal_status == "ROLLED_BACK" and not (target / LOCK).exists() and fx.snapshot(target) == initial, out

# 6d. H5: after the first SIGINT, a second signal that lands while the first unwinds is ignored.
# The probe is deterministic (the signal is sent inside the unwind), so twenty runs must agree.
red = []
for attempt in range(20):
    target = tmp / f"double-{attempt}"
    shutil.copytree(start, target)
    evidence = tmp / f"double-{attempt}-ev"
    out = hooked(target, evidence, "double-signal", 3, 130, f"double SIGINT {attempt}")
    if "PROBE first-handler=SIG_IGN" not in out or "PROBE second-signal=ignored" not in out:
        red.append(attempt)
    assert fx.snapshot(target) == initial and not (target / LOCK).exists(), f"run {attempt}: rollback incomplete"
    assert json.loads((evidence / "journal.json").read_text())["status"] == "ROLLED_BACK", f"run {attempt}"
    shutil.rmtree(target)
assert not red, f"{len(red)} of 20 runs let a second SIGINT escape the rollback handler; last output:\n{out}"
print("PASS: twenty double-SIGINT runs ignore the second signal, roll back every write and release the lock")

# 6f. A SIGINT that lands right after this run creates the lock must not leave that lock behind,
# and must roll back and exit 130 like any other interrupt (the handler is installed before the lock).
target = tmp / "lock-window"
shutil.copytree(start, target)
evidence = tmp / "lock-window-ev"
proc = subprocess.run([sys.executable, "-I", "-B", "-c", HOOK, FINALIZE, str(target), str(evidence), "sigint-after-lock", "0"],
                      capture_output=True, text=True)
out = proc.stdout + proc.stderr
assert not (target / LOCK).exists(), f"a SIGINT in the lock window left {LOCK} behind:\n{out}"
assert proc.returncode == 130 and "interrupted by SIGINT" in out, f"expected exit 130 via the handler, got {proc.returncode}:\n{out}"
assert fx.snapshot(target) == initial, "a SIGINT in the lock window changed the target"
print("PASS: a SIGINT right after the lock is created leaves no lock, changes no byte and exits 130")

# 6g. A tool step that outlives TOOL_TIMEOUT fails the run with the step and the command named, rolls back,
# and releases the lock. The finalizer must not hang: the test bounds its own run at 60 seconds.
target = tmp / "tool-timeout"
shutil.copytree(start, target)
evidence = tmp / "tool-timeout-ev"
log_path = tmp / "tool-timeout.log"
with open(log_path, "w") as log:
    try:
        timed_exit = subprocess.run([sys.executable, "-I", "-B", "-c", HOOK, FINALIZE, str(target), str(evidence), "slow-tool", "0"],
                                    stdout=log, stderr=subprocess.STDOUT, timeout=60).returncode
    except subprocess.TimeoutExpired:
        timed_exit = "hung (no result within 60 s)"
out = log_path.read_text()
assert timed_exit == 1 and "step 'generate-agents --check' timed out after 2 s: its direct child was stopped, but a child process it started may keep running" in out and "every write was rolled back" in out, \
    f"expected a named timeout refusal, got {timed_exit}:\n{out}"
assert fx.snapshot(target) == initial and not (target / LOCK).exists(), "a timed-out run changed the target or kept its lock"
assert json.loads((evidence / "journal.json").read_text())["status"] == "ROLLED_BACK"
print("PASS: a tool step past its timeout fails the run with the step and command named, and rolls back")

# 6h. NEEDED-1: a failure right after the lock file is created (its fsync raises) leaves no lock behind.
target = tmp / "lock-sync-fails"
shutil.copytree(start, target)
out = hooked(target, tmp / "lock-sync-fails-ev", "lock-sync-fails", 0, 1, "lock fsync fails")
assert not (target / LOCK).exists(), f"a failed lock fsync left {LOCK} behind:\n{out}"
assert fx.snapshot(target) == initial, "a failed lock fsync changed the target"
print("PASS: a failed fsync right after the lock is created leaves no lock and changes no byte")

# 6i. NEEDED-1 with a signal: a SIGINT that lands together with that failure leaves no lock and exits 130.
target = tmp / "lock-sync-fails-sigint"
shutil.copytree(start, target)
out = hooked(target, tmp / "lock-sync-fails-sigint-ev", "lock-sync-fails-sigint", 0, 130, "lock fsync fails with SIGINT")
assert not (target / LOCK).exists(), f"a SIGINT with a failed lock fsync left {LOCK} behind:\n{out}"
assert "interrupted by SIGINT" in out and fx.snapshot(target) == initial, out
print("PASS: a SIGINT with a failed lock fsync leaves no lock, changes no byte and exits 130")

# 6j. NEEDED-2: a SIGINT after STRUCTURAL_READY is recorded, at the release call, must not skip the release.
target = tmp / "release-sigint"
shutil.copytree(start, target)
evidence = tmp / "release-sigint-ev"
out = hooked(target, evidence, "release-sigint", 0, 0, "SIGINT at the release call")
assert not (target / LOCK).exists(), f"a SIGINT at the release call left {LOCK} behind:\n{out}"
assert json.loads((evidence / "journal.json").read_text())["status"] == "STRUCTURAL_READY" and "STRUCTURAL_READY" in out, out
print("PASS: a SIGINT after STRUCTURAL_READY releases the lock and the run still exits 0")

# 7. Two finalizers at once: exactly one gets the lock.
target = tmp / "concurrent"
shutil.copytree(start, target)
slow = subprocess.Popen([sys.executable, "-I", "-B", "-c", HOOK, FINALIZE, str(target), str(tmp / "slow-ev"), "slow", "3"],
                        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
deadline = time.time() + 20
while not (target / LOCK).exists() and time.time() < deadline:
    time.sleep(0.05)
assert (target / LOCK).exists(), "first finalizer never took the lock"
second = finalize(target, "--apply", "--evidence-dir", str(tmp / "fast-ev"), expected=1, label="second concurrent finalizer")
assert "another finalize-init holds" in second, second
first_out, _ = slow.communicate(timeout=120)
assert slow.returncode == 0 and "STRUCTURAL_READY" in first_out, first_out
assert not (tmp / "fast-ev/journal.json").exists() or json.loads((tmp / "fast-ev/journal.json").read_text())["files"] == {}
print("RED control observed: a second concurrent finalizer is refused while the first holds the lock; the first completes")

# 8. Tampered, linked, FIFO, oversized and unbound journals are refused without touching the target.
def interrupted_copy(label):
    target = tmp / f"tamper-{label}"
    shutil.copytree(start, target)
    evidence = tmp / f"tamper-{label}-ev"
    hooked(target, evidence, "crash-after", 2, 23, f"tamper base {label}")
    return target, evidence, fx.snapshot(target)

target, evidence, crashed = interrupted_copy("outside")
journal = json.loads((evidence / "journal.json").read_text())
journal["files"]["package.json"] = {"before": base64.b64encode(b"{}\n").decode(), "before_sha256": fx.sha(b"{}\n"), "expected_after": [fx.sha((target / "package.json").read_bytes())]}
(evidence / "journal.json").write_text(json.dumps(journal))
out = finalize(target, "--recover", "--evidence-dir", str(evidence), expected=1, label="journal outside write set")
assert "outside the finalize write set" in out and fx.snapshot(target) == crashed, out
print("RED control observed: a journal that lists package.json is refused; package.json is unchanged")

target, evidence, crashed = interrupted_copy("inconsistent")
journal = json.loads((evidence / "journal.json").read_text())
journal["files"]["RULES.md"]["before"] = base64.b64encode(b"# planted rules\n").decode()
(evidence / "journal.json").write_text(json.dumps(journal))
out = finalize(target, "--recover", "--evidence-dir", str(evidence), expected=1, label="inconsistent journal entry")
assert "inconsistent" in out and fx.snapshot(target) == crashed, out
print("RED control observed: a journal entry whose bytes do not match its recorded hash is refused")

target, evidence, crashed = interrupted_copy("unbound")
receipt = target / ".claude/agents/.init-synthesis.json"
receipt.write_text(json.dumps(json.loads(receipt.read_text())) + "\n")
crashed = fx.snapshot(target)
out = finalize(target, "--recover", "--evidence-dir", str(evidence), expected=1, label="journal not bound to receipt")
assert "not the one this journal started from" in out and fx.snapshot(target) == crashed, out
print("RED control observed: a journal not bound to the receipt on disk is refused")

target, evidence, crashed = interrupted_copy("link")
(evidence / "journal.json").rename(evidence / "real.json")
(evidence / "journal.json").symlink_to(evidence / "real.json")
out = finalize(target, "--recover", "--evidence-dir", str(evidence), expected=1, label="symlinked journal")
assert "journal refused" in out and fx.snapshot(target) == crashed, out
(evidence / "journal.json").unlink()
os.mkfifo(evidence / "journal.json")
out = finalize(target, "--recover", "--evidence-dir", str(evidence), expected=1, label="FIFO journal")
assert "journal refused" in out and fx.snapshot(target) == crashed, out
(evidence / "journal.json").unlink()
with open(evidence / "journal.json", "wb") as handle:
    handle.truncate(64 * 1024 * 1024 + 1)
out = finalize(target, "--recover", "--evidence-dir", str(evidence), expected=1, label="oversized journal")
assert "read limit" in out and fx.snapshot(target) == crashed, out
(evidence / "journal.json").unlink()
(evidence / "real.json").rename(evidence / "journal.json")
assert "RECOVERED" in finalize(target, "--recover", "--evidence-dir", str(evidence), label="genuine journal still recovers")
assert fx.snapshot(target) == initial
print("RED control observed: symlinked, FIFO and oversized journals are refused; the genuine journal then recovers")

# 9. A changed semantic input stops the refresh before any write.
target = tmp / "semantic"
shutil.copytree(start, target)
(target / "src/Other.tsx").write_text("export const other = 1;\n")
(target / "package.json").write_text('{"name":"ready-fixture","dependencies":{"react":"18.3.1","zod":"3.0.0"}}\n')
changed = fx.snapshot(target)
out = finalize(target, "--apply", "--evidence-dir", str(tmp / "semantic-ev"), expected=1, label="semantic change")
assert "PENDING" in out and fx.snapshot(target) == changed, out
print("RED control observed: a semantic source change stops finalize with every byte preserved")

# 10. Planted hashlib.py/json.py in the target and the current directory change nothing.
# (Planted in the working directory: inside the target a .py file would be new source evidence.)
target = tmp / "planted"
shutil.copytree(start, target)
cwd = tmp / "planted-cwd"
cwd.mkdir()
for name in ("hashlib", "json"):
    (cwd / f"{name}.py").write_text("import sys\nsys.exit(0)\n")
out = finalize(target, label="dry run with planted modules", cwd=cwd)
assert "DRY-RUN" in out and "planned writes" in out, out
out = finalize(target, "--apply", "--evidence-dir", str(tmp / "planted-ev"), label="apply with planted modules", cwd=cwd)
assert "STRUCTURAL_READY" in out, out
print("PASS: planted hashlib.py and json.py do not hijack finalize-init")
print("All finalize-init fixtures passed.")
PY
