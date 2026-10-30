#!/usr/bin/env bash
# Contract: every install or run line that fetches this package from GitHub names the release tag, and the
# design-check detector names an exact version. An unpinned `npx -y` line runs whatever the default branch
# holds at that moment (v008 Security: unpinned fetch). Planted-fault control: a copy of the bare line turns it red.
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
cd "$ROOT" || exit 1
FAILURES=0
TAG="v0.7.0"

bare=$(grep -rn -E 'npx -y github:chohra-med/spec-harness-oss( |$|`|\\)' --exclude-dir=.git --exclude-dir=node_modules --exclude='pinned-refs-contract.sh' . || true)
if [ -n "$bare" ]; then
  echo "FAIL: unpinned npx github line(s); name the tag, e.g. github:chohra-med/spec-harness-oss#$TAG"
  printf '%s\n' "$bare" | head -20
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: every npx github: line names a tag"
fi

loose=$(grep -rn -E 'npx -y impeccable( |$)' --exclude-dir=.git --exclude-dir=node_modules . || true)
if [ -n "$loose" ]; then
  echo "FAIL: design-check detector is not pinned to a version"
  printf '%s\n' "$loose"
  FAILURES=$((FAILURES + 1))
else
  echo "PASS: design-check detector names an exact version"
fi

if [ "$FAILURES" -ne 0 ]; then echo "pinned-refs-contract: $FAILURES check(s) failed"; exit 1; fi
echo "pinned-refs-contract: all checks passed"
