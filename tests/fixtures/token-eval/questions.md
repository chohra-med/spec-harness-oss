# Token eval questions (public set)

Target: a copy of the public Spec Harness repository itself. Three questions a new agent would ask
about it. The answers are in `keys.md`. Never put `keys.md` in the copy the agent works in.

Ask each question on its own, in a fresh session, once with the index and once without.

## Q1

How does `spec-harness update` decide that an installed file is `UPDATE`, `MERGE` or `CONFLICT`?
Name the file and the lines where that decision is made.

## Q2

How does `spec-harness status` know which version of Spec Harness is installed in a project, and what
does it print when it cannot tell? Name the file that writes that record, the file that reads it, and the lines.

## Q3

What limits does `spec-harness index` put on a scan, and what does the inventory say when one of them
is reached? Name the file and the lines.

## The two arms

Both arms use a copy of this repository outside any workspace. Both copies drop the answer key and the
root agent files, so neither arm starts with a map. These commands are text only. They are model calls
(the `claude -p` lines), so a person runs them, not a test. `SRC` is the checkout, `Q` is one question's text.

Prepare both copies once. No model is called here.

```text
EVAL=$(mktemp -d)
for arm in without with; do
  rsync -a --exclude .git --exclude .worktrees --exclude node_modules \
    --exclude tests/fixtures/token-eval --exclude /AGENTS.md --exclude /CLAUDE.md "$SRC/" "$EVAL/$arm/"
done
bash "$SRC/bin/spec-harness" index "$EVAL/with"        # writes ai_rules/context_map.md; no model
```

Arm "without index":

```text
cd "$EVAL/without" && claude -p --max-budget-usd 1.50 --output-format json "$Q" > "$EVAL/without-Q.json"
```

Arm "with index":

```text
cd "$EVAL/with" && claude -p --max-budget-usd 1.50 --output-format json "Read ai_rules/context_map.md first. $Q" > "$EVAL/with-Q.json"
```

Notes for whoever runs them:

- The flags are the ones `claude --help` lists. Use `--bare` (add it right after `-p`) only where an API
  key is set: it signs in only with an API key, so on a machine that signs in through the app it fails.
  Otherwise run without it. Then both arms get the same fixed start context (the client's own prompt and
  any personal instruction or memory file); say so beside the results. On the first run, check what was
  loaded before the other five runs.
- Do not add `--no-session-persistence`. The token checker reads the saved transcript for the per-step view.
- Grade each answer against `keys.md`: the file, the lines and the mechanism must all match.
