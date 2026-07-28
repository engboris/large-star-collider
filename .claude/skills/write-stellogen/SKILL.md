---
name: write-stellogen
description: Write Stellogen (.sg) programs. Triggers when asked to write, generate, or create Stellogen code, constellations, or stellar resolution programs.
allowed-tools: Read, Grep, Glob, Bash, Write, Edit
---

# Write Stellogen Code

You are writing code in **Stellogen**, an experimental language based on **stellar resolution** (term unification with polarities). Before writing any code, read the reference materials:

1. [patterns.md](patterns.md) — Core language patterns and mechanics
2. [examples.md](examples.md) — Index of canonical examples (read the actual `.sg` files it points to)

## Key Principles

1. **Everything is a term.** Variables are uppercase (`X`, `Y`), constants/functions are lowercase (`f`, `add`, `0`).
2. **Polarity drives interaction.** `+` provides, `-` requests. Two rays interact when they have opposite polarities and their terms unify.
3. **Stars are blocks of rays** in `[...]`. Variables are **local** to each star.
4. **Constellations are groups of stars** in `{...}`. They are unordered.
5. **Focus (`@`) is critical.** It marks state stars (data being transformed). Without `@`, nothing executes.
6. **Actions are reusable by default**; prefix a star with `*` to mark it consumable (used at most once). `*{...}` marks every star in a group consumable.
7. **Nested `exec` chains** constellations sequentially: `(exec c2 (exec c1 base))`.
8. **Programs have two phases.** `§` before a top-level expression puts it in the check phase (`sgen check`); unmarked expressions form the run phase (`sgen run`); `(object x ...)` definitions are shared between both. Each phase only sees its own definitions plus objects.

## Writing Process

1. **Understand the domain** the user wants to encode
2. **Choose the right paradigm**: logic programming, state machines, proof structures, functional, etc.
3. **Consult examples.md** for the closest canonical pattern
4. **Write incrementally**: define data/facts first, then rules, then queries
5. **Use `show` and `==`** for testing/verification
6. **Use macros sparingly** — only when repetition is clear

## Common Mistakes to Avoid

- Forgetting `@` on query/state stars (results in empty `{}`)
- Assuming variables are shared between stars (they are LOCAL to each star)
- Wrong polarity direction (need `+` provider and `-` requester)
- Thinking execution is clause-based like Prolog (it is NOT — constellations are unordered, polarity and focus drive execution)
- Referencing a run-phase `def` from a `§` item or vice versa (each phase only sees its own definitions plus objects — share the definition with `object` instead)
- Defining a value with `def` when both a `::` assertion and the run program use it (the `::` expansion is check-phase, so the value must be an `object`)

## Parameterised Definitions

Stellogen supports parameterised definitions which are powerful for readability:

```stellogen
(def (transition Q1 Symbol Q2) [(-a [Symbol|W] Q1) (+a W Q2)])
(def (accept Q) [(-a [] Q) accept])
```

These create reusable templates called with `#(transition q0 a q1)`.

## When Using the Prelude

If the program needs the `::` type assertion macro, start with:
```stellogen
(use "milkyway/prelude.sg")
```

`::` hides a `§` in its expansion, so every type assertion lives in the
check phase: `sgen check` verifies it, `sgen run` skips it. Consequences
when writing code:

- A type (`spec`) only used by assertions gets `§`: `§(spec nat {...})`
- A value that is both type-checked and used by the run program must be
  an `object`; a value only ever type-checked can be `§(def ...)`
- Place each check right after the definition it checks
- Verify with `sgen eval file.sg`, which does both phases (check first,
  then run); `sgen run` / `sgen check` isolate one phase when needed

## Output

Write clean, commented Stellogen code. Use `;` comments to explain the structure. Group related definitions together. Test with `show` and `==` where appropriate.

If $ARGUMENTS is provided, treat it as the description of what to write.
