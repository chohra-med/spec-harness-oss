#!/usr/bin/env bash
# The public token-eval question set (tests/fixtures/token-eval/). No model is called.
# - questions.md holds exactly three questions and both arm commands; keys.md holds one key per question.
# - Every citation in keys.md names a file that exists, a line number that exists, and text that is on
#   that line. A planted wrong line, a planted missing file and a planted missing text must fail.
# - Neither file holds a local path.
set -u

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS_DIR="${SPEC_HARNESS_DIR:-$(cd "$TEST_DIR/.." && pwd -P)}"
# shellcheck source=lib/portable.sh
. "$TEST_DIR/lib/portable.sh"
require_python311

python3 -I -B - "$HARNESS_DIR" <<'PY'
import re, sys
from pathlib import Path

root = Path(sys.argv[1])
fixtures = root / "tests/fixtures/token-eval"
questions = (fixtures / "questions.md").read_text(encoding="utf-8")
keys = (fixtures / "keys.md").read_text(encoding="utf-8")
failures = []


def require(condition, message):
    print(("PASS: " if condition else "FAIL: ") + message)
    if not condition:
        failures.append(message)


CITATION = re.compile(r"^- `([^`:]+):(\d+)` contains: `(.+)`$", re.M)


def bad_citations(text):
    """One defect per citation whose file, line or text does not hold; also none at all is a defect."""
    found = CITATION.findall(text)
    defects = [] if found else ["no citations"]
    for path, line, needle in found:
        file = root / path
        if not file.is_file():
            defects.append(f"{path}: no such file")
            continue
        lines = file.read_text(encoding="utf-8").splitlines()
        number = int(line)
        if not 1 <= number <= len(lines):
            defects.append(f"{path}:{line}: the file has {len(lines)} lines")
        elif needle not in lines[number - 1]:
            defects.append(f"{path}:{line}: text not on that line")
    return defects


def sections(text, prefix):
    return re.findall(rf"^## ({prefix}\d)\b", text, re.M)


require(sections(questions, "Q") == ["Q1", "Q2", "Q3"], "questions.md has exactly Q1, Q2 and Q3")
require(sections(keys, "Q") == ["Q1", "Q2", "Q3"], "keys.md has exactly Q1, Q2 and Q3")
parts = re.split(r"^## ", keys, flags=re.M)[1:]
require(len(parts) == 3 and all(len(CITATION.findall(part)) >= 2 for part in parts), "each key cites at least two lines")
require("claude -p" in questions and questions.count("--output-format json") == 2 and "ai_rules/context_map.md" in questions,
        "questions.md holds the with-index and the without-index command, as text")
require("```text" in questions and "```sh" not in questions, "the commands sit in text blocks, not runnable sh blocks")
defects = bad_citations(keys)
require(not defects, "every citation names an existing file, an existing line and text that is on it" + ("" if not defects else ": " + "; ".join(defects)))
require(bad_citations(keys.replace("bin/sh-update.py:210", "bin/sh-update.py:211", 1)) != [], "RED control: a citation with the wrong line")
require(bad_citations(keys.replace("bin/sh-index.sh:45", "bin/sh-index.sh:99999", 1)) != [], "RED control: a line past the end of the file")
require(bad_citations(keys.replace("`bin/sh-install.sh:379`", "`bin/no-such-file.sh:379`", 1)) != [], "RED control: a file that does not exist")
require(bad_citations("no citations here") != [], "RED control: a key with no citation")
require(not re.search(r"/Users/|/home/", questions + keys), "no local path in the question set")
sys.exit(1 if failures else 0)
PY
