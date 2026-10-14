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
  written as `"ownership": "receipt-generated"` with no `sha256` and no `bytes` (`bin/sh-index.sh:526-531`).
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
  (`bin/sh-index.sh:646`). It was already `.` at the base commit (`e6f6249`, line 565). The digest does
  not depend on the checkout folder name, and this RFC does not claim that as new.
- **`--preview`** (`:115-118`, `:797-801`) writes the exact bytes the index would write to stdout and
  exits 0 without writing anything.

### 3. `finalize-init` journal statuses

`bin/sh-finalize-init.py` records a `status` in its journal (`journal.json` in `--evidence-dir`).

Enumerated with `grep -n '"status"\]\s*=\|status": "' bin/sh-finalize-init.py`. COMPLETE: the grep
returns six write sites, lines 441, 460, 471, 487, 490 and 568. Lines 487 and 566 each set one of two
values by a conditional, so the set below has seven words.

| Status | Written at | Meaning | Process exit |
|---|---|---|---|
| `PENDING` | `:441` | journal created before any target write | stays on disk only when the process dies before its next status write |
| `APPLYING` | `:460` | set before each target file is replaced | stays on disk only after an abrupt stop mid-write |
| `STRUCTURAL_READY` | `:471` | every write applied; a second index reached the same inventory; the success line prints at `:476` | 0 (`:478`) |
| `ROLLED_BACK` | `:487` | a refusal or an interrupt; restore put back every prior byte and found no concurrent edit | 1 (`:503`), or 130 when the cause was a signal (`:501-502`) |
| `RECOVERY_CONFLICT` | `:487` (apply) or `:568` (recover) | restore found a file whose bytes are neither the prior bytes nor a postimage this run wrote; those files are kept | 1 (`:497`, `:571`) |
| `RECOVERY_FAILED` | `:490` | restore itself raised an error | 1 (`:495`) |
| `RECOVERED` | `:568` (status written) | `--recover` restored the prior bytes; the success line prints at `:575` | 0 (`:577`) |

Recover refuses a journal whose status is `STRUCTURAL_READY`, `RECOVERED` or `ROLLED_BACK`
(`:531`, `:533`). It does not refuse `RECOVERY_CONFLICT` or `RECOVERY_FAILED`, so the code path
for retrying them exists. That path is read from code (`bin/sh-finalize-init.py:523-581`). The conflict path is run by
`tests/finalize-fixtures.sh` section 6c, which applies the manual step below and then `--recover`.

**Manual step for a conflict.** `--recover` restores a file only when its bytes are the journal's prior
bytes or a postimage this run wrote. Any other content stays a conflict, so a hand edit clears it only when
the result is the prior bytes. For each file the message names, write the bytes its journal entry records
(`files[<path>].before`, base64-decoded) back to the file, then run
`spec-harness finalize-init <target> --recover --evidence-dir <dir>`. This overwrites a concurrent edit, so save
that edit first if it matters. The steps are in `docs/GETTING-STARTED.md`.

The conflict message has one of two forms, depending on the path that kept the files. Both end with `; lock kept.`

- From `--apply` (`:497`, after the journal failure text): `concurrent edits kept, manual recovery needed: <path>`
- From `--recover` (`:571`): `concurrent edits kept; manual recovery needed: <path>`

**Lock rule** (after the H5 change at `c0daa34`):

- `--apply` takes the lock before it writes its journal (`:440`). A busy lock refuses at `:233` and
  leaves the lock file alone. The refusal does not create a journal, but it does leave an empty
  `--evidence-dir` behind (`:439` creates the directory before the lock is taken). A retry needs a new
  directory. This was run: the refusal exits 1, the lock file was unchanged and the empty directory
  remained.
- At the end of an apply the lock is released when the status is `PENDING`, `ROLLED_BACK` or
  `STRUCTURAL_READY` (`:507-511`).
- The lock is kept when the status is `RECOVERY_CONFLICT` or `RECOVERY_FAILED` (`:495`, `:497`). A target
  may then hold a half-written file, so `--recover` must adopt the lock.
- The first SIGINT or SIGTERM installs an ignore for both signals (`:425-432`, `:482-483`), so a second
  signal cannot interrupt the rollback.
- `--recover` adopts a lock only when the PID recorded in it is not alive (`:584-606`). A live PID
  refuses (`:605`). It releases the lock only when the recovery succeeded or the lock was its own
  (`:580-581`).

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

- `finalize-init` does not refresh a Markdown context map. It refuses (`bin/sh-finalize-init.py:294`).
  Only the JSON inventory is supported.
- `doctor` does not check the semantic or the client field. Both stay `NOT_ASSESSED` by design
  (`:150`, `:152`).
- `--recover` installs no signal handler. `install_signal_handlers` is called only from `--apply`
  (`:443`), so an interrupt during `--recover` is not covered by the 130 path. This is a known gap,
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
| `finalize-init` | 0 | dry run; `--apply` reached `STRUCTURAL_READY`; `--recover` reached `RECOVERED` | `:621`, `:478`, `:577` |
| `finalize-init` | 1 | a refusal (precondition, busy lock, concurrent edit, failed or conflicted rollback) | `:655` |
| `finalize-init` | 2 | argument error (`argparse`), or Python older than 3.11 | `bin/spec-harness:35-41` |
| `finalize-init` | 130 | `--apply` interrupted by SIGINT or SIGTERM and rolled back cleanly (both signals return 130) | `:501-502`, `:658` |
| `index --preview` | 0 | bytes printed, nothing written | `bin/sh-index.sh:801` |
| `index` | 1 | a refusal raised as a message (`SystemExit` with a string) | e.g. `:117`, `:170`, `:540` |
| `index` | 2 | no target argument, or Python older than 3.11 | `bin/sh-index.sh:7-8`, `:14`, `:21` |

An uncaught Python exception in `finalize-init` or `doctor` also exits 1 with a traceback. Neither
`main` catches it, so it is not a documented status. Line `:658` is the last-resort handler for an
interrupt that escapes `--apply`; no path in the code reads as reaching it.

## Test to add when accepted

Not required by this RFC: the record adds no behaviour. The enumerations above are checked by reading the
cited lines. Any later change to a status word or a schema version must come with an RFC update and a
fixture that fails without the change.
