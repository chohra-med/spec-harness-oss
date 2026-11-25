# Rule packs

Curated rules that `init` copies into a target's `ai_rules/rules/` as rule modules. They are
written once here, reviewed with the harness and versioned with it, so every project gets the same
wording instead of rules regenerated in different words each time.

- `baseline-*.md`: engineering rules evaluated for each project and adopted where applicable (clean code, design, security, error
  handling, performance, testing, accessibility). Layer `baseline`.
- `standard-*.md`: rules for a named standard or law (for example the European Accessibility Act with
  EN 301 549, OWASP MASVS). Adopted only when the owner records a commitment in
  `.memory/10-product.md`; layer `standard`.
- `tool-*.md`: rules for one package, used only when that package is in the project's
  `ai_rules/stack.md` and its version is inside the pack's `applies` range. Layer `tool`.

Rule line format, the same in every layer:

```text
- **SEC-01** One plain sentence that a reviewer can check. (source: <document>, <URL>)
```

A rule the harness decided itself, with no outside document behind it, cites the RFC that decided it
instead of a URL: `(source: Spec Harness RFC <number>, owner decision <date>)`. The design pack does
this (RFC 0012 in the Spec Harness repository, `docs/rfcs/`).

A target module made from a pack keeps the pack's `rule-layer`, `pack` and `applies` markers and
copies each rule line it adopts byte for byte. It may leave out a rule that does not apply; it may
not reword one. A project that needs a different rule writes its own rule in a higher layer with
`overrides <ID>` in its source tag and records the decision in `.memory/60-decisions.md`.

Sources were checked on 2026-10-21. The performance rules RN-06 to RN-11 and EXPO-04 to EXPO-07 were added on 2026-11-06 from the official Expo documentation and blog, the React documentation and Callstack's React Native best practices skill, checked that day. The design rules DESIGN-01 to DESIGN-03 were added on 2026-11-07 from RFC 0012. A pack whose source moves or changes is updated here, never in
a target.

The checker also accepts the exact historical CLEAN-04 line for existing targets; it does not rewrite them. A guarded refresh proposes the current line and CLEAN-06 for ordinary owner review. Until adopted, the new documentation rule is not enforced there. The current comment and caller-documentation distinction cites the Google review guide checked 2026-11-13.
