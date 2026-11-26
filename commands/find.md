# Method: find where something is

Use this when you need the file, symbol, setting, doc section, route or error text behind a name or a topic. Run it from the target root in any agent that has a shell. A map, graph or index result is a lead only; cite the real file and line. This method is usable before a synthesis receipt or feature goal exists.

## Procedure

1. **Name the thing.** Say what it is: a file, symbol, setting, doc topic, route or error text. Write two to four search terms. Include the word a user would say and the word the code would use.
2. **Pick the package.** Take its path from "Package boundaries" in the Markdown map, or from `packages[].path` in `ai_rules/project_inventory.json`. Search only that path. Use `.` for a root package.
3. **Names first, the cheapest search.** `git ls-files --cached --others --exclude-standard -- <package> | grep -i <term> | head -30`
4. **Doc headings.** `git grep --untracked -n -I -E '^#{1,4} ' -- '*.md' | grep -i <term> | head -20`
5. **Text.** `git grep --untracked -n -I -i -w <term> -- <package> | head -30`. Use `rg -n -i -w <term> <package> | head -30` when it is installed. Outside a git repository use `grep -rn -I -i -w <term> <package> | head -30`. More than 30 hits: narrow the term or the path; do not page through.
6. **Open few files.** Open at most five. Read the lines around the hit first, then more only if needed.
7. **Not found.** After three sets of terms with no hit, say "not found". List the terms and paths you tried and ask the owner. Never conclude that the thing does not exist.
8. **Leave a trail.** Write the terms, the paths and the files you opened in the plan or ticket notes, so the next agent does not repeat the search.

Steps 3 to 5 print at most 80 lines in total.
