#!/usr/bin/env bash
# Contract: the workflow tester role states, in its Hard rules, that it never runs an attack against a shared,
# staging or production environment. v008 Security: the role had no environment guard. Planted-fault control:
# deleting the rule line turns this red.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
ROLE="$ROOT/agents/sdd-workflow-tester.md"
FAILURES=0

hard=$(sed -n '/^## Hard rules/,/^## /p' "$ROLE")
if printf '%s\n' "$hard" | grep -q -i 'shared, staging or production'; then
  echo "PASS: workflow tester hard rules forbid shared, staging or production targets"
else
  echo "FAIL: agents/sdd-workflow-tester.md Hard rules have no environment guard (shared, staging or production)"
  FAILURES=$((FAILURES + 1))
fi

if printf '%s\n' "$hard" | grep -q -i 'disposable'; then
  echo "PASS: the guard names a disposable target as the only exception"
else
  echo "FAIL: the environment guard does not name the disposable-target exception"
  FAILURES=$((FAILURES + 1))
fi

if [ "$FAILURES" -ne 0 ]; then echo "workflow-tester-env-contract: $FAILURES check(s) failed"; exit 1; fi
echo "workflow-tester-env-contract: all checks passed"
