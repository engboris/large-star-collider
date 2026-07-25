# Tour of Stellogen: Interactive Lessons Design

**Date:** 2026-07-17
**Companion to:** `playground_ux.md` (general playground polish).
Two separate experiences: the playground is "try", the tour is
"learn". Delete sections from this doc as they are built.

## Key insight: lesson checks are Stellogen specs

No JavaScript validation framework. A lesson's success criterion is a
hidden `check.sg` appended to the user's buffer and run through the
existing `check` mode in the worker. The author writes ordinary specs
against names the lesson asked the user to define:

```stellogen
; check.sg for "define 'two' as a nat"
(spec nat {[(-nat 0) ok] [(-nat (s N)) (+nat N)]})
§(== (exec #two *#nat) ok)
```

Exit-ok means passed; failure messages come from the existing error
reporting for free. Types-as-tests is the language's thesis, so the
lesson checker being a Stellogen type is the honest pedagogy.

Open authoring question: should checks also constrain the approach
(e.g. reject a hardcoded answer)? `~=` and inequality bans allow it;
early lessons should not bother.

## Content model

One directory per lesson, bundled at build time (static site, no
backend, progress in `localStorage`):

```
tour/
  01_terms/
    lesson.md      ; explanation shown in the lesson panel
    starter.sg     ; pre-filled editor content with a hole
    check.sg       ; hidden, appended on "Check my answer"
    solution.sg    ; shown on "reveal solution"
```

Seed content exists: `exercises/` with `solutions/`, and the wiki
Basics pages for lesson text. The real cost is authoring 20-40 small
lessons, not the mechanics.

## Code organization: two thin pages over shared modules

Avoid duplication by extracting the current 651-line `web/index.html`
into plain ES modules (no framework, no bundler; modules need HTTP,
which the worker already requires):

```
web/
  shared/
    theme.css       ; styling both pages use
    editor.js       ; createEditor(container) -> {getValue, setValue,
                    ;   onInput}; overlay highlighting, line numbers,
                    ;   Tab handling, shortcuts
    runner.js       ; createRunner({onResult, onStatus}) -> {run,
                    ;   check, stop}; worker lifecycle, timeout
  worker.js         ; unchanged, already shared
  index.html        ; playground ("Try"), ~100 lines of page wiring
  tour.html         ; tour ("Learn"): lesson panel, prev/next,
                    ;   progress marks, "Check my answer",
                    ;   "reveal solution", per-lesson URL hashes
                    ;   (#tour/03-polarity)
  build-examples.js ; generalize to bundle examples/ -> examples.js
                    ;   and tour/ -> lessons.js
```

Sequencing: do the extraction first as its own commit, verify the
playground behaves identically, then build the tour on top. The
extraction also makes `playground_ux.md` items (persistence, undo
fix, Stop button) land once in shared modules for both pages.

## Bridge between the two pages

The URL-hash permalink feature from `playground_ux.md` doubles as the
tour-to-playground bridge: "open in playground" is a permalink into
`index.html` carrying the learner's current attempt; the playground
header links back with "Learn Stellogen". No other coupling.

## UI notes

- Keep "Run" available next to "Check my answer" so learners can
  experiment freely inside a lesson.
- The trace feature (see `playground_ux.md`, larger project) matters
  most here: "watch the fusion happen" is the best explanation for
  the first lessons.
