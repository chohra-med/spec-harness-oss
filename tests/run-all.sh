#!/usr/bin/env bash
# Runs every contract test in tests/*.sh (not tests/tools/) and exits 1 if any of them fails.
# Each test's output goes to a log in ${TMPDIR:-/tmp}, as the README describes. `npm test` calls this.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
LOG_DIR="${TMPDIR:-/tmp}"
failed=0
ran=0

cd "$ROOT" || exit 1
for test in tests/*.sh; do
  [ "$test" = tests/run-all.sh ] && continue
  ran=$((ran + 1))
  bash "$test" > "$LOG_DIR/sh-$(basename "$test").log" 2>&1
  code=$?
  echo "exit $code $test"
  [ "$code" -eq 0 ] || failed=$((failed + 1))
done

if [ "$ran" -eq 0 ]; then
  echo "run-all: no tests found under tests/*.sh" >&2
  exit 1
fi
if [ "$failed" -gt 0 ]; then
  echo "run-all: $failed of $ran tests failed; logs in $LOG_DIR" >&2
  exit 1
fi
echo "run-all: $ran of $ran tests passed"
