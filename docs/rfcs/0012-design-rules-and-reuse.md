# RFC 0012: Design rules, a reuse search at plan time, and a duplication check at review

Status: proposal, implemented on this branch for review.

Builds on RFC 0011 ("Init does the reading and the first decisions, and asks only plain questions"):
RFC 0011 changes how init reads a project and decides; this RFC adds the design rules that init adopts
and the plan and review checks that enforce them.

## Problem

Initialization and review need evidence for reuse and cohesive responsibilities, without treating a line count or file count as an architectural fact. A search result is a lead: the reviewer must examine behavior and the authority for a finding. Project policy and adoption decide which baseline lines apply.

## Proposal

1. **Design pack.** DESIGN-01 keeps the pre-addition search. DESIGN-02 asks for reuse of the owning implementation of repeated behavior or a concrete reason for independently maintained similar code. DESIGN-03 asks for cohesion and separation when an actual dependency or change scenario shows why. These lines cite this RFC and the owner decision, not an outside authority. Init evaluates each baseline and adopts only applicable lines, byte for byte. CLEAN-02 already discourages speculative generalization; no interface, factory or file-count rule follows from this RFC.
2. **Plan search.** The existing `## Reuse search` table records symbols, search terms and paths, candidates, decisions, reasons and Ponytail rungs. The independent goldfish searches too. An unassessed materially relevant candidate or absent required search evidence is NEEDED; a same-name match alone does not establish equivalent behavior.
3. **Grounded review.** Pass 1 searches and records candidates. Case 8 is NEEDED when actual equivalent behavior or a violated boundary is shown, the exception fails, and an adopted rule, literal goal or concrete defect supplies authority. Otherwise a correct safe structural preference is ADDITION. Distinct domains and justified independently changing behavior can be valid. Case 9 retains pre-existing defects outside the ticket verdict.
4. **Configured measurements.** The tester runs a duplication or complexity command only when the project names one; it never installs a tool. Such output is evidence, not an automatic line threshold or substitute for semantic review.

## Compatibility

- Existing schemas and optional-pack meaning stay unchanged; structural READY does not prove coverage. Init shows each baseline and relevant documentation/design topic, adopted IDs, exclusions or unresolved reasons, provenance, evidence and higher-policy resolution. Material unresolved decisions prevent semantic acceptance. Refresh proposes a policy delta and preserves custom bytes and higher policy.
- The checker accepts only the exact historical CLEAN-04 line as a scoped exception in the clean-code pack; it does not rewrite targets or relax markers, duplicate IDs, ranks, citations or receipt hashes. CLEAN-06 remains optional until adopted. No legacy exception is claimed for the unpublished DESIGN-02/03 proposal.
- A prior plan without a reuse table keeps its existing meaning until replanned; a new checkpoint requires the table. Receipt schemas, run state and rule-line format remain unchanged.

## Tests

The real rule-layer fixture exercises current and historical CLEAN-04, rejected alterations and preserved target bytes. The SDD fixture checks the written search, authority, equivalence, exception and coverage contracts with planted faults; those static checks do not prove semantic judgment. Fresh bounded synthetic init and review controls must inspect actual code, source authorities and search evidence before accepting omissions, reuse or policy claims.

## Later

- Zones in the index: folders that hold one unit of code, with or without a manifest.
- Samples per zone, and one fresh rule writer per zone.
- Per-zone design conventions (for example "controllers only map HTTP to a service"), accepted by the
  owner through `conventions.md`. They need zones first.
- Job recipes from repeated change shapes in git history.
- A coverage line in `generate-agents --check` and `doctor`: zones with rules, out of all zones.
- A refresh that rewrites only the zones whose code moved.
- A details block per rule (why, a cited do and don't, how to check it, scope).
- The learning loop: a `NEEDED` finding no rule covered becomes a rule candidate for its zone.
