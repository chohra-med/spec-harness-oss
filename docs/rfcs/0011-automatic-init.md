# RFC 0011: Init does the reading and the first decisions, and asks only plain questions

Status: proposal, written for review. No code change in this RFC.

## Problem

Init, as shipped in 0.7.0, stages files and then stops at many questions that need technical
knowledge. On the Myelino backend (PR 80) the result was: memory files filled from the README,
which is only the NestJS starter text, plus "None recorded yet" everywhere. Skills, role
bindings and conventions were not derived from the code. The person running init had to
answer questions they could not answer, and the reader of the output could not tell where to
start.

## Goal

A person with no technical background runs init once and gets:
- a plain-language summary of what the project is, read from its code and docs;
- the rules, conventions and architecture written from evidence, with each claim cited;
- every decision that init can make on its own already made, and labelled as made;
- only the few questions init cannot answer from evidence, asked in plain words.

## Proposal

1. **Read before asking.** Init reads, in order: the project's own instruction files, the
   README, manifests and lockfiles, the entry points, the module layout, one representative
   feature end to end, and the git history (commit style, branch names). Nothing is asked yet.
2. **Decide what can be decided.** Conventions come from the history and config (for example
   Conventional Commits from `git log`). Architecture comes from the code. Each decision is
   recorded with its evidence and labelled "decided by init, reversible".
3. **Ask the person's level first.** One question at the start: "How comfortable are you with
   code? (a) not at all, (b) I read it, (c) I write it." The answer sets how much init explains
   and how many questions it asks. Level (a) gets yes or no questions and a default for each.
4. **Ask only what cannot be read.** Business facts (what the product does, who uses it, its
   goals) cannot come from code. Init asks those, in plain words, with a suggested answer
   drawn from the README where one exists. It never invents a business rule.
5. **Make the choices easy.** Each question has at most three options, one marked as the
   suggestion, and a "not sure, you decide" option that takes the suggestion.
6. **Show the result in one page.** A page that reads: what the project is, what init decided
   for you, what you still need to answer, and where to start. Every decision is one click from
   its evidence.

## What init must never do

- Invent a business rule, a goal or a user from code.
- Change the project's source code or its CI.
- Treat a rule that contradicts the code as true. It reports the conflict and asks (for
  example, a constitution that forbids `any` while the lint config allows it).

## Acceptance (planned checks, not yet written)

- A fixture repo with a README that is only a starter text: init must say "business purpose
  not stated" and ask, and must not fill it from code.
- A fixture with a Conventional Commits history: init must derive the commit convention with
  a source, and must not ask about it.
- A level (a) answer must produce yes or no questions only.
- Planted fault: a rule that contradicts its config must be reported as a conflict, never
  silently chosen.

## Not decided here

- Whether the questions are asked in the terminal or in an artifact page.
- The exact wording of the level question and the plain-language glossary.
