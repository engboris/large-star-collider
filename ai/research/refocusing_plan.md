# Stellogen Refocusing Plan: Logic Workbench (v3)

**Updated:** 2026-07-06

This plan identifies what to change, remove, simplify, or defer so that
Stellogen focuses on its strength: a workbench for building, testing, and
exploring logical systems via stellar resolution, structured as a **minimal
pure kernel plus user-space tower** (notation macros, checkers, logics).

See `evaluation_and_directions.md` (same directory) for the full rationale.
That document is self-contained; the former research corpus it once referenced
has been deleted and its durable findings are preserved in its Appendix A.

Completed items are removed from this plan (git history keeps the record).
Numbering of the remaining items is unchanged so cross-references stay valid.

---

## Phase 2: Simplify the Implementation (remaining)

### 2.7 Kernel audit: write `KERNEL.md` — **done 2026-07-07**
Removed from the plan per the convention above; two findings from the
audit differ from what this plan predicted and are recorded here so they
are not re-litigated:

- **`spec` stays a builtin.** The settled demotion was overturned:
  fixed-arity macros cannot faithfully alias the variadic `def` (a call
  beyond the covered arities would fall through silently to a raw term).
  Verified: per-arity macro patterns do reproduce the builtin exactly
  (parametric identifiers, eager galaxy formation, `forall` iteration);
  the rejection is about the arity cap and its silent failure. Demotion
  path recorded 2026-07-07: head-symbol aliasing, a `macro` whose pattern
  is a bare symbol (`(macro spec def)`) rewriting the head at any arity,
  in the Racket rename-transformer style; implement when a second
  intent-marker (`axiom`, `lemma`, ...) is wanted, and `spec` demotes
  with it. Details in the evaluation doc §5.3 update note.
- **The meta-language is not total as implemented.** Cyclic macro
  references still diverge at preprocessing (verified with
  `(macro (loop X) (loop X))`); `KERNEL.md` §2.5 therefore specifies
  totality as conditional on acyclic macro references, an obligation on
  the user. Adding an expansion-depth guard with a proper error would
  discharge it; do this during 2.6-adjacent evaluator cleanup or as a
  standalone small task.

### 2.8 Macro-system hardening — **design note recorded 2026-07-07**
- **Why:** Terms-by-default means notation errors cannot surface as
  unbound identifiers (no such thing exists); notation out of scope
  silently becomes data. The `spec` demotion failure (2.7) exposed the
  general problem.
- **Design:** `ai/research/macro_system.md`. Four pillars: errors on
  meaningless positions rather than unknown names (dead top-level
  expressions; inert action stars entering interaction spaces), arity
  near-miss diagnostics at any depth, a head-symbol alias map
  (`(macro a b)`, also the natural carrier for import prefixing), and
  variable freshening as the entirety of hygiene.
- **Actions (ordered):** dead-spine diagnostic; arity near-miss
  diagnostic; expansion cycle/depth guard (also in the 2.7 note above);
  bare-symbol aliases (implement with the second intent-marker; `spec`
  demotes then); variable freshening (after a deliberate-capture audit
  of existing macros).

### 2.9 Meta-kernel census and reflection — **design note recorded 2026-07-07**
- **Why:** The meta-kernel is a glue language with a fixed menu; macros
  can rearrange it but cannot create new execution disciplines or
  judgments (`::lin` exists only because the `*` linearity modality is
  on the menu). Serious practices will keep hitting this ceiling.
- **Design:** `ai/research/meta_kernel.md`. An admission rule (a form is
  admitted only if inexpressible by lower strata plus macros;
  observation additions cost the most), a census of the fourteen forms
  (`spec` is kernel debt; `~=` earns its seat but its
  any-ray-pair existential semantics looks accidental; `forall` is the
  galaxy eliminator whose content is separation of interaction spaces,
  not a quantifier), and the direction: lift the ceiling by reflection
  (Maude META-LEVEL precedent), not by growing the menu or turning the
  glue into a programming language.
- **Actions (ordered):** decide internal polarities (5.4, gates the
  encoding contract 2.5.2); sharpen KERNEL.md entries for `~=`/`forall`;
  `quote` (reify execution results into the
  %-encoding; demotes `~=`, dissolves negative assertions, inverts the
  trust trend); fuel axis; `eval` only with
  its first strategy/tactic client and a written trust story.

---

## Phase 2.5: Kernel Contract Work

No additions to the object kernel. One canonicalization task, plus one
deferral recorded so it is not re-litigated from scratch. Rationale:
`evaluation_and_directions.md` §5.

### 2.5.1 Ray scoping/namespacing — **deferred (no kernel construct)**
- **Status:** Considered as a kernel addition, rejected for now. Any two
  stars sharing a function symbol with opposite polarities form a
  communication channel; a `scope`/interface construct with symbol
  freshening would close accidental ones. Deferred because: the motivating
  scenario (knowledge-base-style vocabulary merging) is the deprioritized
  Prolog idiom; workbench practice curates each `exec` space by hand and
  composes results, not vocabularies; shape checkers read code as inert
  terms; a flat symbol space is the semantics (symbols are loci/addresses —
  local labels are an assembler feature, not an ISA feature).
- **Discipline meanwhile:** prefix private wiring symbols by library name
  (e.g. `acyclic-walk`), as house convention in `logics/`.
- **Escalation path if collisions bite:** import-time renaming at the meta
  level — `(use "lib.sg" (prefix lib))` — before any object-kernel change.
- **Revisit triggers:** real capture bugs; multi-library co-saturation
  becoming an idiom; a `logics/` library needing to share one interaction
  space with arbitrary user code.

### 2.5.2 Canonical code-as-term encoding — **blocking for shape-systems**
- **Why:** `::` tests behaviour (what code does). Systems — certified
  fragments like "acyclic ⇒ terminating" or MLL correctness — must test
  *shape* (what code is). Checkers need code reified as a term to unify
  against. **No new primitive is needed:** expressions already are terms
  internally (`ray_of_expr` in `expression.ml` maps all surface syntax onto
  `%`-constructors), examples already store code as data (fields pattern),
  and a term→code `eval` existed until it was removed on 2025-11-16 (commit
  `3025e62`) — correctly, for kernel purity.
- **Action:** (1) done 2026-07-07: the encoding is documented in
  `KERNEL.md` part III. (2) partially done: `@`, `#` and `{}` verified to
  embed in term position (noted in `KERNEL.md` 3.1); the working
  `in-acyclic` splice test below remains. (3) Keep `eval`
  removed until a concrete need (tactics, staged proof construction)
  justifies deliberate reintroduction with a written staging/trust story.
- **Acceptance test:** a working `(in-acyclic Name Body)` macro that defines
  `Name` and asserts the acyclicity checker accepts `Body`'s term encoding.

---

## Phase 3: Reframe and Rebuild Content

### 3.1 Extend exercises — **pending**
- Base set exists (00–03, solutions, cram test). Extend with: types-as-tests,
  automata word-acceptance, and (post-Phase 4) a small MLL proof exercise.

### 3.2 Codify the standard file shape — **pending**
- **Action:** Document the house style (imports → definitions → tests →
  assertions → demonstrations) in `BASICS.md`; align all examples with it.
  It is the file-level expression of "encode + test."

---

## Phase 4: Build the Logic Library

### 4.1 Create `logics/` directory — **pending; benefits from 2.5.2**
```
logics/
  mll.sg            -- Multiplicative Linear Logic (expand from proofnets/)
  classical.sg      -- Classical propositional logic via resolution
  linear_types.sg   -- Linear type system (complete linear_lambda.sg TODO)
  automata.sg       -- Automata-as-logic (acceptance as type membership)
```

### 4.2 Each logic file is a *system*: notation + checker + guarantee
1. Connective definitions as constellations
2. Correctness criteria as test constellations (the checker)
3. Fixed-arity macros for readable notation
4. Worked proofs with commentary **and failing examples showing what the
   checker rejects**
5. A stated guarantee ("everything this checker accepts satisfies P"), with
   the paper proof referenced or sketched

### 4.3 The flagship demonstration — **the project's centerpiece**
- One polished MLL tutorial: connectives → correctness tests → valid proof
  accepted → cut-elimination via `exec` → invalid proof-structure rejected →
  **change the logic and watch behaviour change**. Five-minute answer to
  "what is Stellogen for"; seed of the tool paper.
- Supporting demos: "inventing a connective"; "automata as logical systems."

---

## Phase 5: Improve the Experience

### 5.1 Empty-result diagnostics — **highest UX priority**
- When `exec` produces `{}`, report why: no focused stars? no
  opposite-polarity pair? unification failure (on which rays)?
- **Files:** `executor.ml`, `evaluator.ml`

### 5.2 `(trace expr)` as a language construct
- Let users trace specific executions instead of all-or-nothing CLI tracing.

### 5.3 REPL
- Essential for workbench-style exploration: define connectives, try proofs,
  watch reductions.

---

## Summary: What Remains

| Category | Items |
|----------|-------|
| **Harden** | macro-system diagnostics, expansion guard, aliases, freshening (2.8) |
| **Decide** | internal polarities (gates encoding contract and `quote`, 2.9) |
| **Reflect** | `quote` for execution results, fuel axis, `eval` gated on first client (2.9) |
| **Document** | file-shape house style in `BASICS.md` (`KERNEL.md` written 2026-07-07; keep it in sync) |
| **New content** | `logics/` library + flagship MLL tutorial, exercise extensions |

**Net effect:** a kernel small enough to read in an afternoon, an encoding
contract that unblocks the logic library, and a flagship artifact that
states the project's identity — with zero additions to the object kernel.

---

## Execution Order

```
Phase 2 (short term)     → constellation_eval fold (2.5); trace config (2.6)
Phase 2.5 (design work)  → Encoding contract (blocks Phase 4); scoping deferred
Phase 3 (ongoing)        → Reframe examples and docs
Phase 4 (the point)      → logics/ library + flagship MLL demonstration
Phase 5 (longer term)    → Diagnostics, trace, REPL
```

Phase 2 is mechanical and can be done in a session. Phase 2.5 is the real
design work and gates Phase 4. Phase 4 is where Stellogen becomes genuinely
compelling; Phase 5 is what makes it pleasant to show others.
