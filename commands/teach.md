# Command: `teach` — explain a system to a human

> Build one self-contained interactive page that a person can read in a browser and come away
> understanding a system: what it is, why it is built this way, and how to use it. The agent
> explains; the human learns. `learning_human.html` at the root of an installed project is a worked
> example of this method applied to Spec Harness itself.

## When to run it

- A person asks to understand a codebase, a feature, an architecture or a decision.
- After a ticket or a setup step whose result a person must review and own.
- Onboarding: a new teammate needs the map before the details.

It is for teaching. It is not documentation generation, and it never edits application source.

## The contract

1. **One file.** A single `.html` with inline CSS, inline SVG and a small inline script. No CDN, no
   web fonts, no fetch, no images loaded from elsewhere. It must open from `file://` with no network.
2. **Readable without interaction.** Every fact is on the page as text. Interaction reveals detail
   and lets the reader play with a model; it never hides the only copy of something.
3. **Light and dark**, through `prefers-color-scheme`. **Phone and desktop.** Keyboard reachable:
   every clickable diagram part has `tabindex`, a `role` and a label.
4. **Accessible diagrams.** Each `<svg>` has `role="img"` and a `<title>` and `<desc>` that say what
   the diagram shows, not what shapes it contains.
5. **Honest.** State limits and unknowns next to the claims. A page that only praises is an advert.

## The learning ladder

Teach every concept in this order. Skipping a rung is the usual reason an explanation fails.

| Rung | What to write |
|---|---|
| **1. The principle** | One sentence: the law, stated plainly. |
| **2. The theory** | What it is and why it matters, in two to four concrete sentences. Name the real pieces. |
| **3. The anchor** | Tie it to something this reader already knows. Ask who the reader is, or read it from the project, before choosing anchors. |
| **4. An example** | A small real-world illustration that is not this codebase. |
| **5. How it is used here** | Where it lives in this project: files and what each contains. |
| **6. The real code** | A short excerpt with `path:line`. Comments carry the teaching. |

Use bullets where a detail has three or more facts. Keep paragraphs short and give them air.

## Structure of the page

1. **The idea in one screen**: what this is and who it is for, before any detail.
2. **The problem it solves**, in the reader's terms.
3. **The flow**: one diagram of how work moves through the system, with a panel that explains the
   selected step.
4. **The structure**: what exists and where, as a layer or tree diagram.
5. **How to use it**: numbered steps with commands that can be copied.
6. **Evidence and limits**: what was measured, and where it is weak.
7. **Words**: every term the page used, defined in a sentence.

Number the sections and say the reading order at the top.

## Diagrams

A diagram earns its place only when the reader learns more from it than from a paragraph.

- When the `diagram-design` skill is installed, load it and follow it: pick the type, load that
  type's reference, run its checklist.
- Without it, keep to these rules: at most nine nodes; one or two accent elements, never more; every
  connector a straight or right-angled line, never a diagonal between off-axis boxes; labels never
  sit on their own line; no shadows; arrows drawn before boxes; a legend, if any, below the diagram.
- Choose by what you are showing: steps in order (process), stacked levels (layers), a cycle that
  feeds itself (loop), parts and connections (architecture), choices (flowchart).

## Evidence rules

- Never invent a code excerpt, a file name, a line number or a measurement. Read the real file.
- An excerpt that is a paraphrase is labelled `illustrative`. A quote is never spliced.
- Every number on the page came from a command you ran or a source you can name.
- Nothing private in a page that will be shared: no secrets, no client or employer names.

## Procedure

1. **Gather.** Read the project's instruction files and the source the topic touches. For a codebase,
   read the inventory first, then the files it names.
2. **Decide the reader.** One sentence: who reads this and what they should be able to do after.
3. **Structure.** Lay out the sections above. Decide which concepts get a diagram.
4. **Build.** Write the one file. Keep data separate from drawing code so the page can be updated.
5. **Verify, all of it:**
   - syntax-check the inline script (for example `node --check` on the extracted script);
   - open it in a real browser at desktop and phone widths and look at the result;
   - click every control and confirm the page changes as described;
   - confirm it makes no network request;
   - have a fresh context check every excerpt, path and number against the source.
6. **Deliver.** Save it where the user asked, tell them the path, and open it for them when you can.

## Output

Report the file path, the reader it was written for, what was verified and how, and anything on the
page that is unverified. Do not report the page as correct because it renders.
