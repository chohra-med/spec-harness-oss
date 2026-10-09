#!/usr/bin/env bash
# Rule-ownership contract: each first-initialization and guarded-refresh phrase must have one owner.
# The owner is commands/init.md. The work order (bin/sh-gen-agents.sh) and the generator
# (bin/sh-make-skills.sh) may point to it but must not restate it.
# Usage: rule-ownership-contract.sh [root]   (root defaults to this repository; a temp copy is a valid root)
set -euo pipefail

ROOT="${1:-$(cd "$(dirname "$0")/.." && pwd -P)}"
FILES=(bin/sh-gen-agents.sh bin/sh-make-skills.sh commands/init.md)
PHRASES=(
  "create a skill only when its name is absent"
  "reuse or refresh an existing skill"
  "no custom edit intervened"
  "captured preimage"
)

for file in "${FILES[@]}"; do
  [ -f "$ROOT/$file" ] || { echo "FAIL: missing $file under $ROOT"; exit 1; }
done

status=0
for phrase in "${PHRASES[@]}"; do
  owners=()
  for file in "${FILES[@]}"; do
    if grep -Fq -- "$phrase" "$ROOT/$file"; then owners+=("$file"); fi
  done
  if [ "${#owners[@]}" -gt 1 ]; then
    echo "FAIL: phrase \"$phrase\" appears in ${#owners[@]} files: ${owners[*]}"
    status=1
  fi
done

if [ "$status" -eq 0 ]; then
  echo "PASS: each first-initialization and refresh phrase has at most one owner among the work order, the generator and init.md"
fi
exit "$status"
