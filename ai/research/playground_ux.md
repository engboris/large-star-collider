# Web Playground UX Improvements

**Date:** 2026-07-17
**Source:** review of `web/index.html`, `web/worker.js`,
`web/playground.ml` on the `reactive-execution` branch. Items are
ordered by impact; drop each one from this doc once done.

## Data-loss issues (highest impact, cheap)

- Persist the editor buffer to `localStorage` on input and restore on
  load. Today a refresh, or picking an example from the dropdown,
  silently destroys unsaved work. Add an "unsaved changes" guard before
  an example load overwrites the buffer.
- Native undo is broken: every direct `editor.value` assignment (Tab
  insertion, clear, import, example load) wipes the textarea's undo
  stack, so Ctrl+Z after Tab misbehaves. Route insertions through
  `document.execCommand('insertText', ...)` or `setRangeText` to keep
  the undo history.

## Shareability

- Permalinks: encode the buffer into the URL hash (compressed, e.g. an
  inlined lz-string) so snippets can be shared with no backend. For an
  esoteric language, "look at this program" links are the main
  spreading mechanism.

## Feedback while running

- Run/Check silently ignore clicks while a run is pending
  (`if (pending) return;`). Disable the buttons while busy and add a
  Stop button; the worker-terminate machinery already exists for the
  timeout, so cancel-on-demand is nearly free.
- The hard 5s `TIMEOUT_MS` is tight for the Turing machine example on
  slow devices; a "still running... [Stop]" state is friendlier than a
  hard error.
- Errors are displayed as plain text. The interpreter reports
  line/column positions; parse them to highlight the offending line in
  the editor, or at least make the error clickable to jump there.
  Biggest single boost for learning the language in the browser.

## Editing comfort (paren-heavy language)

- Bracket matching: highlight the matching `()[]{}` delimiter at the
  cursor. Auto-indent on Enter (copy the previous line's leading
  whitespace) is a close second.
- Strategic question: at some point adopting CodeMirror would replace
  the hand-rolled textarea+overlay editor and give bracket matching,
  auto-indent and proper undo for free. The items above are doable
  without it.

## Smaller polish

- Draggable divider between the two panels (fixed 50/50 today).
- Dark mode via `prefers-color-scheme`.
- The examples dropdown doubles as state: "Hello" stays selected after
  the buffer was edited into something else. Use a non-selected
  placeholder label ("Load example...").
- Any non-error run colors the whole output green (`class="success"`);
  reserve color for the status line and leave program output neutral.

## Larger project

- A Trace button: step-by-step fusion visualization in the playground.
  `sgen trace` exists in the CLI and `src/output/tracer.ml` already
  emits events; this is the feature that would make the execution
  model legible. Related: "(trace expr) as a language construct" in
  `issue_backlog.md`.
