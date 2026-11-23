# Token eval answer keys (hand-written)

Each citation line has the form: a path and a line number in backticks, then `contains:` and a short
piece of text that must be on that line. `tests/token-eval-fixtures.sh` checks that the file exists,
that the line exists and that the text is on it. If a source file changes and a line moves, the test
fails and the key is rewritten by hand.

Keep this file out of the copy the agent works in.

## Q1: how `update` decides UPDATE, MERGE or CONFLICT

The decision is the `build_plan` function in `bin/sh-update.py`. A file the harness installed and the
project has not edited is `UPDATE`: its bytes on disk still hash to the value in the install record.
A file edited on disk is merged three ways against the base copy stored under `.spec-harness/base/`.
A clean merge is `MERGE`. A merge with overlapping hunks is `CONFLICT`, and so is a file with no
valid base copy.

- `bin/sh-update.py:177` contains: `def build_plan(root`
- `bin/sh-update.py:209` contains: `elif managed and sha(disk) == entry.get("sha256"):`
- `bin/sh-update.py:210` contains: `row["state"] = "UPDATE"`
- `bin/sh-update.py:216` contains: `merged, conflicts = merge3(disk, base, new)`
- `bin/sh-update.py:218` contains: `state="CONFLICT"`
- `bin/sh-update.py:221` contains: `state="MERGE"`

## Q2: how `status` knows the installed version

The installer writes `.spec-harness/install.json`, an install record with `harness_version`. `status`
in `bin/sh-update.py` loads that record with `load_record` and prints `installed version`. With no
record it prints that the version is unknown and that the install is older than 0.4.0.

- `bin/sh-install.sh:379` contains: `"harness_version": version`
- `bin/sh-update.py:78` contains: `def load_record(root):`
- `bin/sh-update.py:365` contains: `installed version : {record.get('harness_version')}`
- `bin/sh-update.py:368` contains: `unknown (no .spec-harness/install.json; installed before 0.4.0)`

## Q3: scan limits of `index`

`bin/sh-index.sh` stops after 5,000 directories or 25,000 files. When a limit is reached it records a
`scan limit` exclusion for the part it did not scan, marks the scan as not complete, and the Markdown
map says `Scan complete: false`.

- `bin/sh-index.sh:45` contains: `MAX_DIRECTORIES = 5_000`
- `bin/sh-index.sh:46` contains: `MAX_FILES = 25_000`
- `bin/sh-index.sh:730` contains: `add_exclusion(relative_dir, "scan limit"`
- `bin/sh-index.sh:774` contains: `add_exclusion(path_rel, "scan limit"`
- `bin/sh-index.sh:997` contains: `"complete": not truncated,`
- `bin/sh-index.sh:1045` contains: `- Scan complete:`
