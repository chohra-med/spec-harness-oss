# RFC 0003: receipt schema 3 and finalize-init

Status: Accepted. Implemented in 0.4.0.

## Problem

`CONTRIBUTING.md` (section "Proposals") says a change that alters a route, a receipt schema or a
status word starts as an RFC. The 0.4.0 hardening adds a receipt schema version, a set of
`finalize-init` journal statuses and a `doctor` report vocabulary. None of them had a written record
outside the code, so an operator or a reviewer could not tell which words were promised and which
were incidental.

This RFC records what the code does. It proposes nothing new. Every fact cites `file:line` in the
`bin/` files at the commit that adds this RFC. If those files change, the line numbers move and this
record must be updated with them.

## Proposal

### 1. Receipt `schema_version`

The receipt is `.claude/agents/.init-synthesis.json`. The readiness check accepts exactly the integers
1, 2 and 3 and fails any other value (`bin/sh-gen-agents.sh:67`).

| `schema_version` | When it is written | What it adds | Source |
|---|---|---|---|
| 1 | a guarded refresh of an existing schema 1 receipt | the three core skills `spec-harness-architecture`, `spec-harness-performance`, `spec-harness-packages` | `bin/sh-gen-agents.sh:354`, `:499` |
| 2 | a first initialisation | schema 1 plus `spec-harness-quality` and `spec-harness-conduct` | `bin/sh-gen-agents.sh:355`, `:499` |
| 3 | the project's policy files are recorded in the receipt | schema 2 plus `policy_sources` and `policy_coverage` | `bin/sh-gen-agents.sh:67`, `:348-350`; `commands/generate-agents.md:47` |

Schema 1 and 2 receipts keep their meaning and are not asked for a policy ledger
(`commands/generate-agents.md:52`).

Schema 3 fields (checked only when `schema_version` is 3, `bin/sh-gen-agents.sh:348-350`):

- **`policy_sources`**: one row per project policy file, with `path`, `sha256` and a non-empty
  `requirement_ids` list with no duplicates. Read in `check_policy_ledger` (`:232-258`).
- **`policy_coverage`**: exactly one row per requirement id, with `id`, `path`, `sha256`,
  `line_start`, `line_end` and `disposition` (`:259-279`). The allowed dispositions are `captured`,
  `not-applicable`, `conflict` and `owner-decision` (`:281`).
  - `captured` must name a `rule_path` that is a registered rule output and a `rule_anchor` that
    appears in that file (`:283-287`).
  - `not-applicable`, `conflict` and `owner-decision` need a `reason` (`:288-289`).
  - `conflict` and `owner-decision` always fail (`:290-291`), so the receipt stays PENDING until they
    are resolved.
  - A requirement id listed in `policy_sources` with no coverage row fails (`:292-295`).
- **Drift check** (`check_policy_drift`, `:298-314`): each inventory `rule_files` row that was read
  and is not receipt-generated is hashed again. A file whose bytes changed since indexing fails with
  "project policy file changed after indexing" (`:310-314`). The check does nothing unless the
  inventory is `ai_rules/project_inventory.json` (`:299-300`).

`rule_modules` is optional in every schema, not only schema 3 (`bin/sh-gen-agents.sh:341-343`). A
package row may list package-local topic files at `<package>/ai_rules/rules/<name>.md` (`ai_rules/rules/<name>.md`
at the root). Each entry has a topic-slug `name`, the exact `path`, `sha256` and `citations`, and the
file must be linked from that package's `RULES.md` (`:190-229`, especially `:225-227`).

### 2. Inventory digest (`bin/sh-index.sh`)

- **Receipt-owned generated outputs leave the inventory hash while they match the receipt.** A package
  `RULES.md` or a `rule_modules` file whose current sha256 equals the value the receipt recorded is
  written as `"ownership": "receipt-generated"` with no `sha256` and no `bytes` (`bin/sh-index.sh:527-530`).
  Ownership is read from the receipt by `receipt_owned_rule_digests` (`:160-220`). The reason is in its
  docstring (`:161-165`): those files carry the inventory digest in their own bytes, so hashing them
  would make the inventory depend on its own output.
- **A registered output that cannot be read safely stops the run.** The index exits 1 with PENDING
  (`:522`), or with PENDING when a registered output is missing, linked or not a regular file
  (`:538-540`).
- **The finalize lock is not an inventory input.** `.claude/agents/.sh-finalize.lock` is in
  `GENERATED_IDENTITY_PATHS` (`:56-57`), so a lock held during a finalize run does not change the
  inventory.
- **Not a change in this release:** the inventory's `project_root_name` is the fixed label `.`
  (`bin/sh-index.sh:645`). It was already `.` at the base commit (`e6f6249`, line 565). The digest does
  not depend on the checkout folder name, and this RFC does not claim that as new.
- **`--preview`** (`:115-118`, `:796-800`) writes the exact bytes the index would write to stdout and
  exits 0 without writing anything.

### 3. `finalize-init` journal statuses

`bin/sh-finalize-init.py` records a `status` in its journal (`journal.json` in `--evidence-dir`).

Enumerated with `grep -n '"status"\]\s*=\|status": "' bin/sh-finalize-init.py`. COMPLETE: the grep
returns six write sites, lines 545, 548, 584, 608, 619 and 695. Lines 545 and 695 each set one of two
values by a conditional, so the set below has seven words.

| Status | Written at | Meaning | Process exit |
|---|---|---|---|
| `PENDING` | `:584` | journal created before any target write | stays on disk only when the process dies before its next status write |
| `APPLYING` | `:608` | set before each target file is replaced | stays on disk only after an abrupt stop mid-write |
| `STRUCTURAL_READY` | `:619` | every write applied; a second index reached the same inventory; the success line prints at `:627` | 0 (`:629`). It stays on disk with the completed run kept only when the top-level rollback is refused because another run holds the lock (exit 1, `:572`), or when an interrupt lands in the interpreter's own exit (exit 0 with a traceback; see the lock rule) |
| `ROLLED_BACK` | `:545` | set by `roll_back` (`:527`) after a complete restore: a refusal (raised at `:636`), a tool step past `TOOL_TIMEOUT` (600 s, `:46`; the refusal is at `:306`), an unnamed failure (re-raised at `:640`), or an interrupt (`interrupted_exit`, `:559`); restore put back every prior byte and found no concurrent edit | 1 for a refusal (`:636`, printed at `:782`), 1 with a traceback for an unnamed failure (`:640`), 130 for an interrupt (`:577`) |
| `RECOVERY_CONFLICT` | `:545` (from `roll_back`, called by `apply` at `:633` or by `interrupted_exit` at `:569`) or `:695` (recover) | restore found a file whose bytes are neither the prior bytes nor a postimage this run wrote; those files are kept | 1 (raised at `:635` from apply; returned at `:575` from an interrupt; raised at `:698` from recover) |
| `RECOVERY_FAILED` | `:574` | restore raised partway. The journal's `restored` list (`:475`) names the files it put back; the other written files still hold this run's bytes, so this is not a complete rollback | 1 (raised as `RollbackFailed` at `:576`; an interrupt prints the restored and the unrestored files at `:606`) |
| `RECOVERED` | `:695` (status written) | `--recover` restored the prior bytes; the success line prints at `:702` | 0 (`:704`) |

Recover refuses a journal whose status is `STRUCTURAL_READY`, `RECOVERED` or `ROLLED_BACK`
(`:657-660`). It does not refuse `RECOVERY_CONFLICT` or `RECOVERY_FAILED`, so the code path
for retrying them exists. That path is read from code (`bin/sh-finalize-init.py:650-708`). The conflict path is run by
`tests/finalize-fixtures.sh` section 6c, which applies the manual step below and then `--recover`.

**Files this run never wrote.** `restore` skips a journaled file whose `expected_after` is empty (`:477-478`). Such a
file is neither put back nor a conflict, so a human edit to it is kept and the rollback completes (fixture 6r). Only
files this run wrote are restored or can conflict.

**Manual step for a conflict.** `--recover` restores a file only when its bytes are the journal's prior
bytes or a postimage this run wrote. Any other content stays a conflict, so a hand edit clears it only when
the result is the prior bytes. For each file the message names, write the bytes its journal entry records
(`files[<path>].before`, base64-decoded) back to the file, then run
`spec-harness finalize-init <target> --recover --evidence-dir <dir>`. This overwrites a concurrent edit, so save
that edit first if it matters. The steps are in `docs/GETTING-STARTED.md`.

The conflict message has one of two forms, depending on the path that kept the files. Both end with `; lock kept.`

- From `--apply`, or from an interrupt (`conflict_message`, `:521`, after the failure text): `concurrent edits kept, manual recovery needed: <path>`
- From `--recover` (`:698`): `concurrent edits kept; manual recovery needed: <path>`

**Lock rule** (after the H5 change at `c0daa34`; revised by correction 19, 2026-10-15):

- `--apply` installs its signal handler (`install_signal_handlers`, `:475`, called at `:589`) and fills the run
  record `RUN` (`:58`, set at `:590`) before it takes the lock (`:591`; `take_lock` is defined at `:274`). The
  handler and the record therefore exist before the first lock call.
- While the lock is taken, SIGINT and SIGTERM are held back (`take_lock`, `:274-297`). If a signal lands after
  this run created the lock, the lock is removed before the interrupt propagates. A busy lock refuses at `:242`
  and leaves the lock file alone (a refusal this run did not create is never removed). The refusal does not
  create a journal, but it does leave an empty `--evidence-dir` behind (`:583` creates the directory before the
  lock is taken). A retry needs a new directory. This was run before correction 19; that path is unchanged.
  The refusal exits 1, the lock file was unchanged and the empty directory remained.
- **The commit point.** The lock is released at `:625`, after the STRUCTURAL_READY write (`:619`) and before the
  success print (`:627`) and `return 0` (`:629`). From there the run is committed and the lock no longer guards it.
- **Rollback from the top level.** After the handler is installed, a SIGINT or SIGTERM raises `Interrupted`
  (`:481-483`) on whatever line it lands, which covers the release call, the STRUCTURAL_READY write, the
  `return 0` and everything before them. `apply` does not catch it. It reaches `__main__` (`:777-785`), which
  calls `interrupted_exit` (`:559`). That calls `roll_back` (`:527`), the same path `apply` uses on a refusal
  (`:633`). `roll_back`:
  1. ignores both signals (`:534`), so a second signal cannot interrupt the rollback;
  2. holds the lock before it writes (`hold_lock_for_rollback`, `:530`). If the commit released the lock and
     nothing took it, it takes it again with `take_lock` (`:538`), with the same mask and `O_EXCL`. It keeps a
     lock only when this run created it (`LOCK_CREATED`, `:65`, set at `:299`, cleared by `release_lock` at `:280`)
     and the file still records this process. A lock this run did not create is never removed, even when it records
     this process's PID (fixture 6m). If another run holds it, the attempt is refused with the `acquire_lock` message
     (`:249`) and nothing is written. If the lock step raises an OSError, the attempt is refused as
     `cannot take the finalize lock for the rollback` (`:544`), again with nothing written (fixture 6n);
  3. restores every journaled file (`:544`) and records the outcome in the journal;
  4. releases the lock only when the status is `ROLLED_BACK` (`:553`). It keeps the lock for `RECOVERY_CONFLICT`
     and `RECOVERY_FAILED`.
  `interrupted_exit` returns 130 when every write is rolled back (`:577`).
- **Race refused.** When another run holds the lock at the moment the top-level rollback starts (a second
  finalizer took it after the commit), the rollback refuses (`:564`, re-raised at `:568`) and writes nothing.
  It leaves the other run's lock alone. `interrupted_exit` prints the refusal and returns 1 (`:609-610`). The
  status stays `STRUCTURAL_READY`, and the journal's `failure` field records `rollback refused`, so the
  completed run is kept. Fixture 6l measures this case.
- **Four cases where an interrupt after the first target write does not roll back.** (1) The race refusal above:
  the completed run is kept, exit 1. (2) A conflict: the rollback finds a file whose bytes are neither the prior
  bytes nor this run's postimage, keeps that file and the lock, and exits 1 (`interrupted_exit`, `:611-613`). (3) A
  restore that raises partway (`RECOVERY_FAILED`): some files hold the prior bytes and others still hold this run's
  bytes, the lock is kept, and the print names both sets and exits 1 (`:597-607`). (4) The interpreter's own exit,
  below, which exits 0.
- **The window that remains: the interpreter's own exit.** After `sys.exit` raises `SystemExit` out of the `try`
  in `__main__` (`:827`, and the exits at `:830` and `:833`), no code in this file is protected. The handler is
  never restored: `install_signal_handlers` (`:497`) runs once and nothing resets the default disposition. So an
  interrupt there raises `Interrupted` in code that does not catch it, on every exit path of `__main__`, not only
  after a completed run. Measured with a SIGINT sent from an `atexit` hook after a completed run: exit code 0, a
  traceback ending `Interrupted: SIGINT`, status `STRUCTURAL_READY`, no lock, and every byte equal to the completed
  run. The rollback does not cover this window. The exact boundary inside the exit path was not measured. After a
  refusal (exit 1) or a 130 exit, the same window exists; the exit code and output of those paths were not measured
  (UNVERIFIED).
- **Injection measurement.** A SIGINT injected at each of the 158 line events of `apply` from the first target
  write (event 67, line 610) to the last (event 224, line 629) ended with exit 130, `ROLLED_BACK`, no lock and
  every byte equal. The table is in the correction 19 receipt. The same driver on a copy of `6136460` flagged
  10 of 166 points.
- The first SIGINT or SIGTERM ignores both signals (`:482`), and `roll_back` sets them again (`:534`), so a
  second signal cannot interrupt the rollback.
- `--recover` adopts a lock only when the PID recorded in it is not alive (`acquire_or_adopt_lock`, `:711-733`).
  A live PID refuses (`:732`). It releases the lock only when the recovery succeeded or the lock was its own
  (`:707-708`).

### 4. `doctor` report (`bin/sh-doctor.py`)

`doctor <target>` prints one JSON object (`:160`). Its fields, in order of the report dictionary
(`:146-159`):

- `target`, `structural` (`READY` or `PENDING`, `:138`), `structural_reasons`;
- `semantic` (always `NOT_ASSESSED`, `:150`), `semantic_note`;
- `client` (always `NOT_ASSESSED`, `:152`), `client_note`;
- `startup_route_in` (which of `AGENTS.md` and `CLAUDE.md` names `.claude/commands/sdd.md`, `:73`);
- `paths`: a row per file with `status`;
- `synthesis_check`: `exit` and `output` of `generate-agents --check` (`:135-136`);
- `prerequisites` (`:86-100`) and `platform` (`:103-117`).

Status words, each produced by the code cited:

- path rows: `PRESENT`, `SCAFFOLD`, `MISSING`, `UNSAFE`, `UNREADABLE` (`classify`, `:42-57`);
- prerequisites: `OK`, `MISSING`, `TOO_OLD` (`:88-97`);
- platform: `SUPPORTED`, `UNSUPPORTED`, `UNTESTED` (`:103-117`).

`semantic` and `client` are never judged by doctor. A fresh reviewer decides the first, and a fresh
client session decides the second (`:5-8`).

## Not in 0.4.0

- `finalize-init` does not refresh a Markdown context map. It refuses (`bin/sh-finalize-init.py:340`).
  Only the JSON inventory is supported.
- `doctor` does not check the semantic or the client field. Both stay `NOT_ASSESSED` by design
  (`:150`, `:152`).
- `--recover` installs no signal handler. `install_signal_handlers` is called only from `--apply`
  (`:589`), so an interrupt during `--recover` is not covered by the 130 path. This is a known gap,
  not a designed behaviour.

## Exit codes

Every exit code the four new surfaces can produce. COMPLETE: found by `grep -n 'sys.exit\|SystemExit\|return [0-9]'`
over `bin/sh-doctor.py`, `bin/sh-finalize-init.py` and `bin/sh-index.sh`, plus the argument parsers and
the dispatcher check in `bin/spec-harness:35-41`.

| Surface | Code | Cause | Source |
|---|---|---|---|
| `doctor` | 0 | structural READY | `bin/sh-doctor.py:161` |
| `doctor` | 1 | structural PENDING | `:161` |
| `doctor` | 2 | target is missing or a symbolic link | `:127` |
| `finalize-init` | 0 | dry run; `--apply` reached `STRUCTURAL_READY`; `--recover` reached `RECOVERED`. An interrupt in the interpreter's own exit also exits 0 (measured; see the lock rule in section 3) | `:748`, `:629`, `:704` |
| `finalize-init` | 1 | a refusal (precondition, busy lock, concurrent edit, failed or conflicted rollback, a rollback refused after an interrupt because another run holds the lock, or a tool step past `TOOL_TIMEOUT`, where only its direct child is stopped and a child process it started may keep running); an unnamed failure, after its rollback, with a traceback | `:782` (refusals from `main`), `:572` and `:575` (interrupt paths), `:636` (raised by apply), `:640` (re-raised) |
| `finalize-init` | 2 | argument error (`argparse`), or Python older than 3.11 | `bin/spec-harness:35-41` |
| `finalize-init` | 130 | `--apply` interrupted by SIGINT or SIGTERM and rolled back from the top level: every write restored, the lock released (both signals). Not covered: an interrupt in the interpreter's own exit (exit 0, section 3); an interrupt whose rollback is refused because another run holds the lock, or whose lock step fails (exit 1); an interrupt whose rollback finds a conflict (exit 1, conflicting files and lock kept); an interrupt whose restore raises partway (exit 1, `RECOVERY_FAILED`, section 3) | `:615`, `:825-833` |
| `index --preview` | 0 | bytes printed, nothing written | `bin/sh-index.sh:800` |
| `index` | 1 | a refusal raised as a message (`SystemExit` with a string) | e.g. `:117`, `:170`, `:540` |
| `index` | 2 | no target argument, or Python older than 3.11 | `bin/sh-index.sh:7-8`, `:14`, `:21` |

An uncaught Python exception in `finalize-init` or `doctor` also exits 1 with a traceback. Neither `main` nor
`__main__` catches it, so it is not a documented status. An unnamed failure inside `apply` (`:637-640`) rolls
back first and then re-raises, so the traceback is the only difference from a named refusal. An interrupt that
reaches `__main__` (`:783-785`) is always handled by `interrupted_exit`. The one interrupt it cannot handle is one
that lands in the interpreter's own exit (section 3).

## Test to add when accepted

Not required by this RFC: the record adds no behaviour. The enumerations above are checked by reading the
cited lines. Any later change to a status word or a schema version must come with an RFC update and a
fixture that fails without the change.
