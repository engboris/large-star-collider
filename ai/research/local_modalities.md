# Reactive Execution: One Rule, Catalysts, Ground Guards

**Date:** 2026-07-15
**Status:** implemented (branch `reactive-execution`). Unmarked stars
are reactive: linear, interacting freely across stars and within one
star (internal cut), and what remains at saturation is the result.
`*` marks catalysts: reusable, passive, mutually inert, dropped from
the result. `!X` on a variable occurrence delays a ray until that
position is ground; the guard survives substitution by inheritance
(`!X` under `X := (s Y)` becomes `(s !Y)`) and is erased before
unification. `@` and the old `*` linearity are removed. One execution
rule, no ordering policy: internal cuts are tried first as a
scheduling choice, guards provide user-side synchronization.
Acceptance met: `examples/circuits.sg` runs its `==` assertions green
(markless nets, `*` truth tables, `!X` gate inputs); the full test
suite, examples, prelude, exercises, web playground and nvim syntax
are migrated.

## Encoding conventions learned during migration

- A cut or linker star that serves several addresses (MLL ⅋/⊗ cuts,
  lambda function/argument linkers) must not be one catalyst: fresh
  copies open duplicate routes to the same rendezvous and speculative
  strands survive as residue. Write it split address-wise, one
  reactive star per address; this is the rewired form the ⅋/⊗ rule
  produces anyway. Atomic (single-address) cuts are plain reactive
  stars, and nets then normalize markless with no kicker star.
- Rule sets where only some alternatives fire (pattern matching,
  automata, truth tables) are catalysts, otherwise the untaken
  alternatives linger in the result (no weakening on reactive stars).

## Open

- Guard strength: only full groundness for now; add a
  head-instantiated (nonvar) variant if an example demands it.
- Staging: `then` works as a built-in; folding it into `exec` via a
  per-ray `stage` tag remains kernel debt. Two independent pipelines
  in one `exec` must not block each other, so the tag is probably
  `(namespace, stage)` with `then` minting a fresh namespace. Decide
  before implementing.
- The wiki still documents the old `@`/`*` model.
