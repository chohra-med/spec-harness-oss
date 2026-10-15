# Changelog

All notable changes to this project are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## 0.4.0 - Unreleased

### Added

- `spec-harness run-state --check <ticket>` validates a resumable ticket run state
  (`.spec-harness/runs/<ticket>/run-state.json`). The schema is in `docs/RUN-STATE.md`.
- `status`, `update` (plan, then `--apply DIGEST`) and `uninstall` (plan only) for an installed target.
  Each install records what it wrote, so the uninstall plan is exact.
- A three-way merge for `update`: a local edit is kept when the template did not change, merged when
  both changed without overlap, and reported as a conflict with a proposed file when they overlap.
- Policy-coverage receipts (schema version 3). Schema 1 and 2 receipts still validate.
- A rule-coverage matrix over the complete diff in the reviewer agent. Missing evidence is `PENDING`,
  not a blocking finding.
- The `conventions` and `technology-profiles` method owners, with a Grill Me checkpoint and grounded
  conventions step in the plan and SDD commands.
- `examples/react-ts-minimal`, a synthetic project with one unusual convention, and a smoke test of
  init, index and `generate-agents --check`.
- Proposals `docs/rfcs/0001-neutral-install-route.md` and `docs/rfcs/0002-learning-statuses.md`.
- `CONTRIBUTING.md` and a pull request template.

### Changed

- Every Python call in `bin/` runs isolated (`python3 -I -B`), so a file in the working directory cannot
  shadow a standard module. The code targets Python 3.11 and later, and a clear message is printed
  for older versions.
- Every receipt, inventory, journal and state read goes through the bounded safe reader. Symlinks,
  FIFOs, devices, oversized files and non-object JSON are refused.
- The finalizer journals with the receipt hash, limits recovery to the write set, takes a lock, and
  rolls back on SIGINT and SIGTERM. `--dry-run` is the default without `--apply`.
- The inventory digest no longer includes the project's folder name, so renaming the folder keeps the
  hash.
- Tests no longer need `rg`, use `grep`, and run with `TMPDIR` unset in CI.

### Platform support

- macOS and Linux are supported. Native Windows is not. WSL2 works like Linux, and `doctor` says so.

### Security

- Generated rules and third-party skills are data. Init does not fetch mutable skills.

## 0.3.0

- Earlier release. See the git history for its changes.
