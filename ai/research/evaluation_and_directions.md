# Stellogen: Evaluation and Directions

**Date:** 2026-07-06
**Status:** Strategic assessment — self-contained.
**Note:** This document is the rationale behind `refocusing_plan.md`. The
former `ai/research/` corpus (~16 AI-generated design documents) has been
deleted as obsolete; the few findings from it worth keeping are distilled in
Appendix A so that nothing in this document depends on them.

---

## Executive Summary

Stellogen has been evaluated against the wrong question. "How does this lead to
real-world applications?" is a bar the project will always fail, because
Prolog, Racket, and miniKanren already exist and are better at being
general-purpose. The right question is: **what can be done in Stellogen that
cannot be done anywhere else?**

There is a real answer, and it is already in the repository:
`examples/proofnets/mll.sg` defines the connectives of Multiplicative Linear
Logic, expresses proof-net correctness criteria as test constellations, and
runs cut-elimination as plain `exec`. No other tool does this. Proof assistants
(Coq/Lean/Isabelle) have fixed foundations; logical frameworks (Twelf, Dedukti,
Metamath) check *derivations*, not *interaction*.

The recommended identity:

> **Stellogen is the workbench where logics and type systems are user-space
> artifacts with certified guarantees, built as a minimal kernel plus
> user-space libraries — a pure substrate with towers of notation and
> checkers over it.**

Four consequences structure everything below:

1. **One syntax, two languages.** An *object language* (constellations,
   whose semantics is stellar resolution — logic/chemistry-flavoured) and a
   small functional *meta-language* that builds, runs, and compares
   constellations (Scheme-flavoured glue), sharing one s-expression syntax.
   The tower is user-space growth of both. No third language, no separate
   compiler (§3.2).
2. **Systems are certified fragments, not DSL sugar.** A "system" is a
   restriction on constellation shape that comes with known metatheory
   (terminates, is linear, satisfies MLL correctness). Locking is an
   assertion, not a compiler mode (§3.3).
3. **Encode + test, never just encode.** Encoding models of computation is
   table stakes for any Turing-complete formalism. The unique twist is typing
   them by tests: the language of an automaton as a behaviour, word acceptance
   as type membership (§3.4).
4. **Purify the substrate.** The implementation has accumulated
   general-purpose-language machinery (incremental parsing with error
   recovery, `watch` mode, variadic macros) that a research kernel does not
   need. Remove it (§4, §7.2).

The most important *language* prerequisite is:

- **A documented, canonical code-as-term encoding** (§5.2) — quoting is
  already structurally free in Stellogen (expressions *are* terms
  internally), but shape-checking — what systems (§3.3) are made of — needs
  that encoding to be a stable, documented contract rather than an
  implementation detail.

(Ray scoping/namespacing was considered as a second kernel addition and
**deferred** — see §5.1 for the analysis and the revisit triggers. The
typing architecture — `::` as user-defined judgment macros over the fixed
base observations `==`/`~=`/`forall` — was audited and found *correct as
is*; its one consequence is a further removal, the `spec` builtin (§5.3).
Internal polarities were investigated and found to be an accidental
semantics: restrict duality to ray heads (§5.4) — a restriction, not an
addition. The object kernel therefore gets *zero* additions.)

---

## 1. Where the Project Stands

### 1.1 What works and is compelling

| Asset | Why it matters |
|---|---|
| `proofnets/mll.sg` (+ `fomll.sg`, `mall.sg`) | The flagship. Cut-elimination is literally star fusion; a type is a galaxy of test constellations checked by interaction. The clearest realization of transcendental syntax as software. |
| `states/nfa.sg`, `npda.sg`, `turing.sg` | NFA, PDA, and Turing machine where each transition is a star and macros provide readable notation (`if read C on Q then Q'`). Legible, working, and already a demonstration of the "tower" model: user-space macros creating domain notation over the raw substrate. |
| Types-as-tests (`naive_nat.sg`, `sumtypes.sg`, the `::` macro) | Types are not annotations but executable test constellations — a genuinely novel, user-definable type discipline. |
| `relational/arithmetic.sg` | Relations run backwards (`2 + ? = 4`) via pure unification; honest header about where the Prolog analogy breaks. |
| Rewritten exercises + `test/exercises.t` | Current-syntax, CI-tested learning materials. |
| Ragot 2025 result | Formal proof that stellar resolution simulates interaction nets/combinators in linear time, with functorial, confluence-preserving translations. The project's only rigorous external validation; it directly supports the workbench story (see Appendix A.4). |

### 1.2 What is broken or unresolved

- **`circuits.sg`** — body entirely commented out; the thesis (Ch. 8)
  acknowledges there is no computationally faithful synchronous circuit
  encoding. This is a boundary of the model, not a bug (§3.4, Appendix A.1).
- **`family.sg` grandparent query** — the rule as written diverges under
  `exec` (its `+parent`/`-parent` rays feed each other across copies);
  rewriting both subgoals negative fixes it (verified). The deeper reading:
  the file judges Stellogen against Prolog's directed clause semantics,
  which the model deliberately does not have — reframe, don't patch (§5.1
  for the related-but-deferred scoping question).
- **Parser over-engineering** — `src/parsing/` implements Menhir's incremental
  API with token-skipping error recovery (~400 lines across `parse_error.ml`
  and `stellogen_parsing.ml`). This is IDE-grade machinery serving no research
  goal; a fail-fast parser with one precise error is the right tool (§7.2).
- **Documentation drift** — e.g. `CLAUDE.md` documents a `<f a b>` stack-sugar
  that no longer appears in the lexer; the actual mechanism is the variadic
  `stack` macro in `milkyway/prelude.sg`. Symptom of feature churn outpacing
  the docs.

### 1.3 The pattern behind past drift

Each abandoned direction (general-purpose scripting, business-rule DSLs, JSON
parsers, error recovery, incremental parsing) shares a signature: it competes
on terrain where mature tools already win and where stellar resolution confers
no advantage. Each retained strength shares the opposite signature: it
exercises interaction-based typing, which nothing else has. The strategy
follows mechanically: build only where the mechanism is the differentiator.

---

## 2. The Core Diagnosis

Stellogen's value is that it is the **assembly language of logic** — which is
exactly what transcendental syntax claims: logic is not computation itself but
a *formatting* of computation. The thesis's own layered architecture (Constat,
Performance, Usine, Usage) already describes strata over a raw substrate.

This reframes every open dilemma:

- The substrate does not need to be pleasant to write. Assembly isn't.
- Usability belongs to the stratum above, written *in* Stellogen — the
  thesis's "epidictic as macro system" direction, flagged there as "the key
  to making stellar resolution usable" and "concrete enough to implement."
- "Real-world application" for a foundational formalism means: *other
  researchers use it as an instrument and learn something*. That is what
  Twelf, Abella, Dedukti, and Metamath achieved, and it is an honest,
  reachable bar.

---

## 3. The Dilemmas, Answered

### 3.1 General-purpose language vs. logic-first workbench

**Logic-first, definitively.** Not a Prolog-adjacent query tool, but an
instrument for **defining, testing, and comparing logics**, where correctness
criteria are executable and cut-elimination is native dynamics. The
general-purpose experiment (Scheme-like with programmer-side types) should be
formally closed: its good ideas (macros, programmer-side types) survive inside
the tower; its ambitions (scripting ergonomics, stdlib breadth, editor-grade
tooling) do not.

### 3.2 Substrate and tower — one syntax, two languages

The layers question dissolves once a distinction that is already present in
the implementation is made explicit: **Stellogen contains two languages with
different semantics sharing one s-expression syntax**, and confusion comes
from not naming them.

- **The object language: constellations.** Rays, stars, `{...}`, focus,
  inequality constraints. Its semantics is stellar resolution: unordered,
  interactive, non-deterministic, possibly non-terminating. This is the
  logic/constraint-programming flavour — the chemistry.
- **The meta-language: the expression layer.** `def`, `#`-reference,
  parametric definitions, fixed-arity `macro`, `exec`,
  `show`, `==`, `~=`, `forall`, `use`. Its semantics is a small functional
  evaluator: deterministic, ordered, substitution-based. Its *only* data are
  terms and constellations; its *only* job is to build constellations, run
  them, and compare the results. This is the Scheme flavour.

So the feeling of "mixing mechanisms" — a logic-programming kernel wrapped in
a functional-looking s-expression language — is accurate, and it is not a
design flaw. It is the classic architecture of logic frameworks, with the
strongest possible pedigree: **ML was invented as exactly this** — the
functional *Meta-Language* of the LCF prover, whose distinguished datatype
was `theorem` and whose job was to construct and combine object-level proofs.
Stellogen's meta-language is to constellations what ML was to LCF theorems.
Isabelle (ML over object logics) and Coq (Gallina/Ltac over a kernel) share
the shape. Prolog, instructively, does *not* — it collapses meta into object
(`assert`/`retract`, `call/1`) and pays for it in semantic murkiness.

**Why not two fully separate languages, like assembly and C?** Considered and
rejected, for reasons that are structural rather than aesthetic:

1. **The upper language must be user-extensible — that is the project's
   thesis.** Logics and type systems are supposed to be user-space libraries.
   In the asm/C model the high-level language is fixed by the compiler
   author: adding a new logic would mean forking a compiler. In the
   Scheme/Racket model the elaborator (the macro expander) is programmable
   from inside the language: a new logic is a library import.
2. **Racket proves the two-language experience is recoverable as a special
   case.** A `#lang` looks and feels like a different language but is
   implemented as a library over one reader and one expander. The asm/C
   separation can be *simulated* without being *institutionalized*.
3. **Cost.** Two grammars, two ASTs, source mapping, error translation
   across the boundary — double maintenance for a one-researcher project,
   plus a frozen interface exactly where the research needs flexibility.
4. **Shared syntax buys homoiconicity across the strata** (§5.2): meta-level
   checkers manipulate object-level code as plain terms, for free. A
   separate upper language would reopen the quotation problem that §5.2
   just closed.

What the two-language instinct gets right, keep: **the kernel as a
compilation target.** Because the object kernel is small and documented
(`KERNEL.md`), an external front-end — anyone's language, someday — can emit
kernel constellations the way compilers target LLVM. That door stays open
*because* the kernel stays pure. But the project itself ships one language.

**Design rules that fall out:**

1. **`KERNEL.md` has two parts.** The *object kernel*: exactly stellar
   resolution as in the thesis — terms, rays, stars, constellations, focus,
   `||` constraints; nothing else. The *meta kernel*:
   the minimal glue listed above, each construct justified as glue. The
   sorting rule: **anything that computes belongs in the object language;
   the meta-language only assembles, runs, and compares.**
2. **The meta-language stays total and boring.** Once variadic macros are
   removed, macro expansion terminates structurally — keep that property. No
   closures, no higher-order functions, no arithmetic, no general recursion
   at the meta level. The moment the meta-language can compute on its own,
   the general-purpose drift restarts. (This is why v1's macro
   simplification was right for a deeper reason than line count.)
3. **The tower is user-space growth of both strata**: notation macros extend
   the meta-language's surface; constellation libraries (logics, checkers)
   extend the object stock. Both are ordinary `.sg` files; `sgen preprocess`
   is the witness that everything elaborates to kernel forms. A file pragma
   like `#system mll` can come much later as pure sugar for "import this
   library and wrap the file in its checker" — a pragma, not a second
   reader.

So the intuition "a pure, minimalistic, simple substrate, then something over
it" is exactly this model — with the clarification that the "something over
it" is two-natured (functional glue + macros) and shares the substrate's
syntax, which is what makes the whole self-sufficient rather than a
compile-target for an external tool.

### 3.3 Systems: what they are and what "locking" means

**A system is a triple (notation, checker, guarantee):**

- *notation* — macros making the fragment pleasant to write;
- *checker* — a constellation (or galaxy of tests) that decides whether a
  piece of code belongs to the fragment;
- *guarantee* — a theorem, proved on paper, of the form "everything the
  checker accepts has property P" (terminates, is linear, satisfies MLL
  correctness, ...).

Under this reading a type system is not a bundle of conveniences — it is a
**small theorem about a constellation fragment, packaged as a library**. Each
shipped system is potentially paper-worthy, and the long-term version of this
idea is the descriptive-complexity program (§6): shape hierarchies capturing
complexity classes.

**"Locking" is an assertion, not a compiler mode.** The mechanism comes in
three rungs, and only the first two should be built any time soon:

**Rung 0 — behavioural systems (possible today).** A system file exports
macros plus test constellations; membership is checked by *interaction*, as
`::` already does:

```stellogen
; systems/nat.sg — a "system" in embryo
(spec nat {
  [(-nat 0) ok]
  [(-nat (s N)) (+nat N)]})
(macro (:: Tested Test) (forall Test T (== @(exec @#Tested #T) ok)))
```

This tests what code *does*. It cannot test what code *is* — its shape.

**Rung 1 — shape systems (needs only a canonical encoding, §5.2).** Since
expressions already *are* terms internally, a definition's body can be handed
to a checker as a term; the checker is an ordinary constellation that walks
the *code*:

```stellogen
; Sketch: an acyclicity checker receives the constellation reified as a term
; (in the canonical %-encoding) and tests its dependency structure.
(def acyclic-check { ... })   ; ordinary stars walking the code term

; "Locking" a definition into the system — the macro splices Body twice:
; once in code position (the def), once in term position (the check).
(macro (in-acyclic Name Body)
  { (def Name Body)
    (== @(exec @(quote Body) #acyclic-check) ok) })
; `quote` here is thin notation for the existing encoding (§5.2),
; possibly a no-op — not a new evaluator mechanism.
```

`(in-acyclic double {...})` then *is* the lock: the definition is admitted
only if the checker accepts its shape, and the guarantee (acyclic ⇒
terminating, thesis Ch. 9) applies. A block form wrapping many declarations,
or a `#system` file pragma, are trivial sugar over this once it works.

**Rung 2 — vocabulary restriction, nested systems, escape forms.** Deferred
until Rung 1 has at least two real inhabitants (say, the acyclic fragment and
MLL). Do not build machinery ahead of inhabitants.

Two properties keep this aligned with the language's philosophy:

- *Escapable by construction*: enforcement happens only where you write the
  assertion. Not writing it is the escape hatch — no `unlock` keyword needed.
- *Self-hosted*: the checker is a constellation; checking membership is
  itself stellar resolution. Systems are not a second semantics bolted onto
  the language; they are the language applied to its own syntax.

### 3.4 Models of computation as information-passing hypergraphs

**Half a direction — keep the half that is yours.**

"Stellogen can encode a Turing machine" is true of everything Turing-complete
and impresses no one. The differentiator is the typing side:

- The language of an automaton is a *behaviour*; word acceptance is *type
  membership*; the machine is *typed by tests*.
- Every encoding in the repo should ship with its correctness criteria as
  constellations. "Encode + test" is unique to Stellogen; "encode" alone is
  not.

**Boolean circuits: stop fighting them.** Stellar resolution's unification is
eager and asynchronous — a gate encoded as `(+and 1 X X)` will happily unify
with `(-and 1 Y R)` while `Y` is still unbound, producing bindings on
half-arrived inputs; there is no way to make a star *wait* until all inputs
are ground. The thesis (Ch. 8) acknowledges this as a genuine impossibility:
no computationally faithful synchronous circuit encoding exists. Treat it as
a **boundary result** — "stellar resolution relates to synchronous models the
way asynchronous π-calculus relates to synchronous π: encodable with overhead,
not natively" — and, if circuits are ever wanted, implement them in the tower
as a *compilation* (staging the circuit into layers so that each layer's
outputs are ground before the next layer's stars are introduced — e.g. via
`process`), not as a substrate patch. Delete `circuits.sg`; Appendix A.1
preserves the analysis.

**Tile-based computation:** a pleasant native-fit example (stars ≈ tiles,
constellations ≈ assemblies), worth one polished demo. Chasing DNA-computing
realism (probabilistic assembly, million-tile scale, visualization) would be
a detour into someone else's field. Example, not direction.

### 3.5 The open proof assistant

**The Coq analogy, calibrated.** Architecturally, Stellogen relates to its
kernel the way Coq relates to CIC: small trusted core, elaboration and
notation above it, libraries above that (macros ≈ notations, the meta-glue ≈
the vernacular, `logics/` ≈ the standard library). But the kernels play
opposite roles, and the difference is the project. **Coq's kernel is a
judge**: CIC is a fixed logic, proof objects are checked against its typing
judgments, and "correct" means "the kernel accepts." **Stellogen's kernel is
a physics engine**: stellar resolution executes interactions and judges
nothing; there are no typing judgments in the kernel at all. Correctness is
manufactured above, in user space, by checkers — so where Coq has one global
trusted base (the kernel), Stellogen has a per-system trust story: the
executor (OCaml, small), plus each system's checker (a readable
constellation, itself inspectable and testable), plus the paper theorem
linking checker to guarantee (§3.3). In thesis terms: Coq is Church-style
(typing derivations built into the object), Stellogen is Curry-style (types
as tests applied after the fact). One line: *Stellogen is Coq with the logic
evicted from the kernel into user space.* The kernel is not the analogue of
CIC — it is the analogue of the untyped calculus CIC was built to discipline.

**This is the destination, approached incrementally.** The thesis notes call a
toy prototype "extremely compelling and publishable." The path is not to
build a Coq competitor; it is:

1. Flagship MLL artifact (§8, step 3) — "here is a logic, defined and tested."
2. `logics/` library — MLL, classical propositional via resolution, linear
   types — each one a *system* in the §3.3 sense: notation + checker +
   guarantee, with worked proofs and *rejected* non-proofs.
3. The demonstration no one else can give: **"what if we change the logic?"**
   Drop a test, add a connective, watch which proofs survive. Logic as a
   library import, not a foundation.
4. Only then: proof-construction UX (REPL, tactics-as-constellations, trust
   story across logical modules).

---

## 4. Syntax and Program Shape: A Review

The surface syntax (reference: `examples/syntax.sg`) is in decent shape, but
it carries noise that contradicts the "pure substrate" goal.

### 4.1 What is right and should not change

- **S-expressions.** Zero grammar ambiguity, trivially macro-able, and — see
  §5.2 — the precondition for cheap quotation. Do not pursue "natural"
  surface syntax at the kernel level; that was the single biggest wrong turn
  in the deleted research corpus.
- **The three sigils**: polarity (`+`/`-`), focus (`@`), reference (`#`).
  Compact, meaningful, and they mark exactly the three concepts newcomers
  must learn. Keep.
- **`[...]` for stars, `{...}` for constellations.** The visual distinction
  between a block of rays and a set of stars carries real information.
- **Term syntax** (uppercase variables, lowercase functions, optional parens
  on constants) — standard and fine.

### 4.2 Noise and friction to resolve

1. **Two import forms.** `use` vs `use-macros` is a distinction without a
   user-visible difference. Merge (already planned).
2. **Two stacking notations.** `CLAUDE.md` documents `<f a b>` reader sugar;
   the code actually uses the variadic `stack` macro. One mechanism must win.
   Since variadic macros are slated for removal, the honest options are: a
   kernel-level reader sugar, or nothing (writing `(s (s 0))` is bearable).
   Recommendation: nothing, until real tower code demands it.
3. **Variadic macros** power `stack`/`chain`/`process` in the prelude but
   constitute a general-purpose metaprogramming language inside the macro
   system. Removing them (planned) requires `process` to become a kernel
   built-in first — the right order of operations.
4. **Overloaded brackets.** `[0 1]` inside a ray is a cons-list; `[...]` in
   constellation position is a star. Context-dependent meaning of the same
   delimiter is a real reader hazard. At minimum document it prominently;
   consider a distinct list syntax if it keeps confusing people.
5. **`spec` as a built-in.** If `spec` is semantically `def` for galaxies, it
   should either be macro-definable in user space or be justified in
   `KERNEL.md` as a primitive. Audit it during the kernel write-up.
6. **Fields/records** (`(+field k) v` + a `get` macro) are a *pattern*, and a
   good one — they already live in user space. Keep them out of the kernel;
   resist any richer record machinery.
7. **Comment syntax** (`'` and `'''`) is unusual (quote-like) but harmless. *(Update 2026-07-07: switched to Lisp-style `;` line comments, freeing `'` for a possible future quote marker.)*
   Not worth churn.

### 4.3 The shape of a good Stellogen file

Programs in the repo have converged on a natural shape worth codifying as the
house style — it is also the shape of a "logic file" in the §3.5 sense:

```stellogen
(use "...")          ; 1. notation/system imports
(def ...)            ; 2. the objects (constellations)
(spec ...)           ; 3. the tests (types/correctness criteria)
(:: ... ...)         ; 4. assertions: objects pass tests
(show (exec ...))    ; 5. demonstrations
```

Definitions, then tests, then assertions, then demonstrations. Every example
and every future `logics/` file should read this way; it is the file-level
expression of "encode + test."

---

## 5. Four Kernel-Level Design Questions

All four answered without adding to the object kernel: scoping is
*deferred* (the analysis below records why and when to revisit), quotation
is a canonicalization task (the machinery already exists), the
typing/judgment architecture is *already correct* — its resolution is one
more removal (§5.3) — and internal polarities turn out to be an
*accidental semantics* to restrict, not a feature to keep (§5.4).
Everything else is removal or user space.

### 5.1 Scoping/namespacing for rays — considered, deferred

**The mechanism that motivated it** (verified against the current
implementation, 2026-07). Two libraries that each use a symbol as *private
wiring* cross-talk the moment they are merged into one interaction space:

```stellogen
(def libA {
  [(+fooA X) (-tmp X)]    ; `tmp` is libA's private wiring
  [(+tmp a)]})
(def libB {
  [(+fooB X) (-tmp X)]    ; libB coincidentally also wires with `tmp`
  [(+tmp b)]})

(show (exec { #libA #libB } @[(-fooA X) X]))
; today: { [a] [b] } — libB's private [+tmp b] answered a query
; it was never meant to see. Expected: a.
```

Compatibility is decided purely by symbol + polarity + unifiability,
globally: any two stars that use the same function symbol with opposite
polarities form a communication channel, whether or not the authors meant
one. The considered fix was a `scope`/interface construct — declared
exported symbols, everything else freshened at composition time.

**Why it is deferred.** Re-examined without the Prolog lens, the case for a
kernel construct collapses:

1. **The flagship customer left.** The scenario that motivated scoping was
   knowledge-base-style merging — many independently authored vocabularies
   saturating in one space (`{ #family #grandparent }`). That is precisely
   the Prolog-emulation idiom this document deprioritizes. No example in
   the repo actually hits the collision; the demo above had to be
   constructed.
2. **The meta-language already provides the isolation.** In workbench
   practice every `exec` is a small, hand-assembled interaction space; you
   compose *results* (via `process`, `#`-reference, fields), not
   vocabularies. Putting two constellations in one space is explicit and
   opt-in — the curation point already exists in the language.
3. **The workbench's own idioms are collision-resistant.** Shape checkers
   (§3.3) consume reified code as *inert terms* — no live rays, nothing to
   capture. Behavioural tests (`::`) interact through a deliberately narrow
   test vocabulary — under bi-orthogonality the test vocabulary *is* the
   interface, which is the model working as designed, not a hazard
   survived.
4. **A flat symbol space is the semantics, not a defect.** Symbols are the
   loci at which interaction happens (locativity); the kernel already gives
   hygiene to variables because they are per-star placeholders, and the
   asymmetry is principled — symbols are *addresses*. The assembly analogy
   lands exactly: local labels are an assembler feature, not an ISA
   feature. Address management belongs to whoever *generates* the code.

**If collisions ever bite**, the proportionate responses stay out of the
object kernel, in escalating order: a naming convention (prefix private
symbols by library — the defense every assembly programmer knows); then
import-time renaming at the meta level, e.g. `(use "lib.sg" (prefix lib))`
— standard module practice, one option on an existing meta form, object
kernel untouched.

**Revisit triggers** (record kept precisely so this can be reopened without
re-deriving it): co-saturation of multiple independent libraries becomes a
real idiom; users report actual capture bugs; a `logics/` library
legitimately needs to share one interaction space with arbitrary user code.
If a kernel construct is ever built, the design notes stand: freshening is
symbol-renaming at constellation build time (`tmp` → `libA::tmp#42`), no
evaluator changes; the theory guide is bi-orthogonality (an interface is
"the symbols through which this constellation is willing to be tested");
acceptance test is the cross-talk example above answering only `a`.

### 5.2 Quotation, `eval`, and the homoiconicity question

**Is homoiconicity noise? No — and it is already there.** Stellogen does not
need a quotation primitive, because quoting already exists in two forms:

- *Structurally*: the implementation parses every expression into a
  first-order term — `ray_of_expr` in `src/core/expression.ml` maps all
  surface syntax onto `%`-constructors (`%cons`/`%nil`, `%group`, `%params`,
  `%string`). An expression *is* a term; the `Raw` AST node wraps exactly
  that. Stellogen is in this sense more homoiconic than Lisp: programs and
  runtime data are not merely the same *kind* of structure, they are the
  same material — first-order terms manipulated by unification.
- *Idiomatically*: examples already store code as data — the fields pattern
  keeps constellations inside stars, and encoding s-expressions as rays is
  an established usage.

The reverse bridge existed too: an **`eval` expression (term → running code)
was implemented and then removed on 2025-11-16 (commit `3025e62`)** during
simplification — it took a single-ray result, converted the ray back into an
expression, and evaluated it (`expr_of_ray`, since deleted).

What remains is therefore not adding machinery but **promoting the encoding
from implementation detail to contract**:

1. **Document the canonical encoding in `KERNEL.md`** — the exact term shape
   of reified rays, stars, and constellations (the `%`-constructors).
   Shape-checkers (§3.3) will be written against this encoding; it must be
   stable, unique, and documented, not incidental.
2. **Verify macro splicing covers the locking pattern** — `(in-acyclic Name
   Body)` must be able to splice `Body` both in code position (the `def`)
   and in term position (the checker's input). Homoiconicity should make
   this nearly automatic; if some surface forms (`@`, `#`, `{}`) fail to
   embed in term position, fix that, and a thin `quote` notation can paper
   over the seam — sugar over the existing encoding, not a new evaluator
   mechanism.
3. **Leave `eval` out for now — its removal was the right call for kernel
   purity.** Reintroduction is cheap (it was ~18 lines) and should wait for
   a concrete need: a tactic engine, staged proof construction, executing
   code retrieved from fields. When that need arrives, reintroduce it
   deliberately, with the staging and trust story written down, rather than
   as a convenience. Full computational reflection (self-modifying
   constellations, fexpr-style tricks) stays out regardless.

*(Update 2026-07-07: extended by `meta_kernel.md`, which covers what
this section does not: reification of execution __results__, not just
code. A `quote` form over results makes observations user-definable
(demoting `~=`, dissolving negative assertions) and names eval's likely
first client, a strategy/tactic practice, per the staging story required
above. Point 3's conclusion is unchanged.)*

**Why this matters here specifically:** types-as-tests (`::`) observes
*behaviour* — what code does under interaction. Systems (§3.3) check *shape*
— what code is — and shape-checking constellations receive code as a term to
unify against. The technical fit is exact: inspecting reified code means
pattern-matching against code terms, and Stellogen's one mechanism —
unification — is exactly a code-pattern-matcher. Checking reified code by
interaction is typing syntax by tests — the language applied to itself, with
no new mechanism at all. It also fits the theory: reifying dynamics into a
static, inspectable object is precisely the thesis's Constat move.

### 5.3 Typing as user-defined judgment — settled, correct

**The question.** `spec` and `::` were once primitives; today `::` is a
prelude macro and each practice can define its own. The recurring doubt:
typing is the *central* mechanism of the language — should something so
central really be left to user-defined macros, given that every practice
has a different way to say "this test passed"?

**Verdict: the macro architecture is correct, and the diversity of success
criteria is the content, not the problem.** The evidence is already
in-repo. The judgment has at least three independent degrees of freedom,
and existing practices vary along each:

- *How to run*: `prelude.sg`'s `::` uses `exec`; `mll.sg` had to define
  `::lin` with `*`-marked stars (linear proofs must not duplicate
  actions), plus
  adapter pre-composition before checking.
- *Against what*: each test in the spec galaxy, separately (`forall`).
- *What counts as passing*: the `ok` residue today; annihilation (empty
  residue — the GoI/nilpotency convention), witness shapes, or phased
  checks (Appendix A.5) for future practices.

Even a permanently standardized `ok` token would not have saved a
primitive `::` — the linearity axis alone breaks it (`::lin` would
have required a kernel patch). In ludics terms this is exactly right: the
orthogonality relation ⊥ is a *parameter* of the model — daimon-
convergence, nilpotency, normalization are different choices yielding
different types and different logics. A practice's `::` macro is that
practice **declaring its orthogonality relation**. Making the user write
it is the "meaning belongs to the user" thesis executed literally, not a
workaround. Moving `spec`/`::` out of the primitives was the single most
thesis-aligned decision in the language's history.

**Where trust bottoms out — the regress argument.** Testing cannot be
tests all the way down: "does the residue equal `ok`?" cannot itself be
answered by an interaction without a judge for the judge. Every
test-based discipline needs *base observations* that are not tests.
Stellogen's are `==` (syntactic equality of results) and `~=`
(compatibility), plus `forall` to quantify over a galaxy — the right
minimal set, because equality and connectability are the two things one
can decide about terms without imposing any meaning on them.

This yields an LCF-shaped factoring, worth stating as the design:

| LCF | Stellogen | Status |
|---|---|---|
| abstract `thm` type | assertions (`==`, `~=`) | fixed, trusted, meta-kernel |
| tactics | judgment macros (`::`, `::lin`, …) | user-defined, diverse, untrusted |
| goals/terms | specs (galaxies of test constellations) | data |

The uniformity that a primitive `::` seemed to offer is not lost — it
lives one level lower. **The contract: a checking macro must expand to a
sequence of assertions.** Assertions are the only way anything is
reported as pass/fail, so generic tooling (test runner, CI, a `--check`
mode) counts assertion failures identically across all practices,
whatever their success conventions. This contract is already true de
facto; it should be documented as normative (KERNEL.md, §3.2).

**`forall` is load-bearing, keep it primitive.** A type is a *set* of
tests and the tested must pass each in a **separate interaction space** —
merging the tests into one constellation would let tests interact with
each other and corrupt the judgment. `forall` is the ∀ in "t ⊥ e for all
e ∈ E". It also cannot be a macro: it iterates over galaxy structure
unknown at expansion time.

**Rejected alternatives** (for the record):

- *Re-primitivize `::`/`spec`*: bakes one orthogonality relation into the
  kernel; contradicts the thesis; `::lin` already proves the kernel would
  need patching per practice.
- *Types carry their own success criterion as object-level data* (e.g. a
  `judge` field next to the tests): hits the regress — the judgment needs
  `==`, which is meta-level; the criterion belongs in the practice's
  macro, not in the type's data.

**One action falls out:**

1. **Demote `spec` (a removal).** It is still a kernel builtin — and it is
   *literally* `def`: `src/core/expression.ml:622` matches `def_op` and
   `spec_op` in the same arm, identical code path (the `syntax.sg` comment
   "spec is a built-in for galaxies" is misleading; `def` handles the
   multi-expression galaxy case identically). Intent-marking is a
   notation-layer job: `(macro (spec X Y ...) (def X Y ...))` in the
   prelude. One less name in the trusted kernel — goes on the §7.2 list.
   [Update 2026-07-07: **overturned**. The sketch above is variadic, and
   variadic macros no longer exist; `def` is variadic (that is how
   galaxies are formed), so a faithful `spec` macro is impossible. A
   per-arity pattern set works for today's repo but a call exceeding the
   covered arities falls through silently to a raw term instead of
   erroring, which is unacceptable for a typing construct. `spec` stays
   a builtin, justified in `KERNEL.md` (part II) as intent-marking on a
   variadic form. The demotion path, when wanted, is identifier-level
   aliasing in the Racket rename-transformer style, not a call-pattern
   macro: a `macro` whose pattern is a bare symbol, `(macro spec def)`,
   rewrites the head symbol at any arity. It is trivially terminating (a
   finite symbol-to-symbol map; cycles detectable at definition time) and
   makes intent vocabulary (`axiom`, `lemma`, practice variants of `spec`)
   cheap user-space notation; the same symbol-map mechanism is the natural
   carrier for import-time prefixing (§5.1's escalation path). Implement
   it when a second intent-marker is wanted, and `spec` demotes with it.
   Caveat: aliasing does not remove the silent-fallthrough hazard; under
   terms-by-default a `spec` call without the alias in scope still
   becomes an inert term.]

Optional refinement, zero-cost and user-space: a prelude vocabulary of
named base judgments — `(macro (passes-ok R) (== @R ok))`,
`(macro (annihilates R) (== @R {}))` — so each practice's `::` reads as a
composition of named observations and its orthogonality relation is
legible at a glance, instead of raw `==` against magic tokens.

### 5.4 Internal polarities — accidental semantics, restrict to head duality

**The question.** Rays carry polarity on the head symbol; but nothing
stops a `+`/`-` symbol from occurring *inside* a term, e.g.
`(+f (+g a))`. The author never uses internal polarities in practice, the
thesis notes they threaten confluence, and they add complexity to the
engine. Keep, restrict, or remove?

**Measured behavior** (verified against the implementation, 2026-07). The
implementation has *no head/subterm distinction at all*: polarity is baked
into the function-symbol type (`constellation.ml:12`,
`idfunc = polarity * string`), `ray = term`, and the same
polarity-*inversion* compatibility rule applies at **every** depth of
unification (`constellation.ml:22-27`, applied recursively via
`unification.ml:66-77`). Three consequences, all confirmed by experiment:

1. **A term containing a polarized subterm never matches its structural
   twin.** `(+f (+g a))` does *not* unify with `(-f (+g a))` — the inner
   `+g`/`+g` pair fails; only `(-f (-g a))` matches, because inner
   polarities must *also* invert.
2. **Neutral-headed rays can fuse.** `@[(f (+g a)) ok]` and
   `[(f (-g a)) yes]` fuse to `[ok yes]`: `is_polarised` is
   depth-sensitive (`constellation.ml:105-107`), so an internal polarity
   makes a neutral-headed ray eligible, and `Null/Null` heads are
   compatible. This directly contradicts the documented model ("neutral
   rays do not interact") and changes which star fires first — the
   concrete mechanism behind the confluence worry.
3. **Nothing uses them.** Exactly one executed program in the entire repo
   touches an internal polarity: `x7` in `exercises/00-unification.sg`,
   where `(+g a)` rides through a variable binding and later surfaces as
   a head ("deferred activation"). Git history (`git log -S`) shows the
   depth behavior was never deliberately introduced; no doc mentions it.
   It is an accident of reusing one `compatible` function for all depths.

**The interesting mechanism, isolated.** What made internal polarities
feel computationally interesting is the `x7` idiom: *first-class
suspended actions* — a polarized term stored as inert data inside a term,
transmitted through a variable binding, and activated when it surfaces in
ray position (π-calculus mobile-channel flavour). Crucially, **that idiom
does not need depth-inversion matching**. It only needs polarized symbols
to be *storable* at depth. The two anomalies above contribute nothing to
it.

**Options:**

- **(A) Ban them** — `+`/`-` in argument position becomes a parse error;
  introduce a real ray/term type split (polarity only at ray level, as in
  the ideal grammar). Cleanest types; kills the deferred-activation idiom;
  and reified code (§5.2) could no longer carry ray polarities as plain
  subterms — the encoding would need wrapper symbols like `(%pos …)`.
- **(B) Make them inert** — polarity inversion applies *only at ray
  heads*; at depth, a polarized symbol is simply part of the symbol's
  identity (`+g` matches `+g`, not `-g`); `is_polarised` inspects the head
  only. Small change (compare heads for duality, unify arguments with the
  equality signature that already exists for `~=`).
- **(C) Status quo** — an undocumented trap that contradicts the docs.

**Recommendation: (B).** It removes both anomalies and the confluence
hazard, keeps the genuinely distinctive mechanism (suspended actions),
and — decisive synergy — it is what the **shape-system agenda needs**:
reified code containing polarized rays is stored with its polarities as
inert subterms, shape checkers pattern-match them by *equality* (under
the current depth-inversion semantics a checker would have to write
*inverted* polarities in its patterns to match code — absurd), and
"unquoting" is just surfacing. `x7` still works under (B): the inner
`(+g a)` binds through the variable without any depth comparison and
activates on surfacing. Under (A) it becomes unwritable.

**One thing to reconcile:** whether the thesis's formal definition of
stellar resolution puts duality at all depths or at heads only. If the
thesis allows depth duality, (B) is the workbench officially adopting the
restricted, confluent fragment as its semantics — a restriction, not an
addition, and KERNEL.md should say so explicitly.

---

## 6. The Research Program

The language and the research agenda should feed each other:

1. **Descriptive complexity via shape constraints** (thesis notes: top
   priority). Systems (§3.3) are the *implementation vehicle*: a hierarchy of
   certified fragments capturing complexity classes would be a stellar
   resolution analogue of Immerman–Vardi, with the workbench as the
   experimental instrument.
2. **Termination fragments.** Termination of constellations is undecidable in
   general, but the thesis (Ch. 9) gives a decidable sufficient condition:
   acyclic finite constellations terminate. That is the first shape-system to
   certify (§3.3, Rung 1); size-change-style extensions can be explored
   empirically inside the workbench.
3. **Asynchrony as a boundary theorem.** Formalize the circuit impossibility
   (§3.4, Appendix A.1) as a statement about synchronous vs. asynchronous
   interaction models.
4. **Petri nets / string diagrams / game semantics** (thesis notes): outward
   connections; pursue opportunistically, ideally by *encoding them in the
   workbench* so each connection doubles as a tower library.
5. **The inward question** (thesis notes): the intrinsic structure of the
   space of constellations — topology, metrics, order structure. The workbench
   again serves as instrument.

Publication targets: a tool/system paper (FSCD, IJCAR, ITP, or CPP style) on
"a workbench for transcendental syntax" anchored by the MLL demonstration;
separate theory papers per certified fragment.

---

## 7. Technical Priorities

### 7.1 Language work (kernel additions)

1. **Canonical code-as-term encoding** (§5.2) — documentation and
   stabilization of what `ray_of_expr` already does, not new machinery;
   blocking for shape-systems; acceptance test is a working `in-acyclic`
   (§3.3 Rung 1).

That is the whole list. Ray scoping was considered and deferred (§5.1);
the object kernel gets zero additions.

### 7.2 Substrate purification (kernel removals)

The implementation is ~3,000 lines of OCaml; a meaningful fraction serves
abandoned general-purpose ambitions. Remove:

1. **Incremental parsing + error recovery** (`src/parsing/parse_error.ml`,
   the recovery driver in `stellogen_parsing.ml`). **Audited 2026-07:
   removal is safe and loses nothing observable.** Key findings: the
   diagnostic *quality* (precise `file:line:col`, caret rendering,
   contextual messages + hints) lives in `lexer.ml` (delimiter stack,
   `last_token`), `terminal.ml`, and `contextualize_error` — none of it
   depends on the incremental API; 7 of 8 error-test fixtures are *lexer*
   errors that abort before recovery ever runs; the multi-error test
   itself is titled "reports first error only"; and the recovery driver
   restarts from a fresh checkpoint mid-stream, so its second errors are
   rarely coherent. Replacement: a ~15-line monolithic parse via
   `MenhirLib.Convert.Simplified.traditional2revised` +
   `Sedlexing.with_tokenizer`, reusing the existing (currently dead)
   fail-fast handlers; drop `--table` from the menhir flags; error output
   is byte-identical minus the `found N error(s)` banner. Net ≈ −180 to
   −210 lines and the codebase's only incremental-API surface disappears.
   `parse_error.ml` contains dead code besides (`is_delimiter`,
   `is_top_level_start`, `format_position`); keep only
   `string_of_token` + `contextualize_error`, folded into
   `stellogen_parsing.ml`. Callers (`bin/sgen.ml`, evaluator `use`, web
   playground) depend only on the entry-point signature — no hidden
   couplings.
2. **`watch` command** (`bin/sgen.ml`, ~70 lines of Unix process management).
   `entr`/`watchexec` exist.
3. **Variadic macros** (~120 lines in `expression.ml`) — after `process`
   becomes a built-in.
4. **`use-macros`/`use` duplication**, **`MatchableRays` duplication**,
   **`constellation_eval.ml` indirection**, **`__trace__` magic binding** —
   as per the refocusing plan.
5. **`spec` builtin** (§5.3) — identical code path to `def`
   (`expression.ml:622`); demote to a prelude macro
   `(macro (spec X Y ...) (def X Y ...))`. Intent-marking is
   notation-layer work, not kernel work.
   [Overturned 2026-07-07: fixed-arity macros cannot alias the variadic
   `def`; `spec` stays a builtin. See the §5.3 update note.]
6. **Depth-inversion polarity matching** (§5.4) — restrict polarity
   duality to ray heads; at depth, polarized symbols become part of
   symbol identity (inert). A semantics *restriction*, not an addition:
   removes the neutral-head-fusion anomaly, the twin-mismatch anomaly,
   and the confluence hazard, while keeping suspended-action terms
   storable (and making reified-code pattern-matching sane for §5.2).
7. **Kernel audit**: write `KERNEL.md` (§3.2), structured in two parts —
   object kernel (stellar resolution proper) and meta kernel (the glue).
   Every surviving construct is either listed there with a justification or
   demoted to a tower macro; meta constructs must justify themselves as
   glue (assemble/run/compare), never as computation.

The goal state: the OCaml core is small enough to read in an afternoon, and
its contents map one-to-one onto the formal definition of stellar resolution
plus the short kernel list. That *is* the "very simple and pure substrate."

### 7.3 Workbench experience

The highest-leverage UX work, in order:

1. **Empty-result diagnostics.** When `exec` yields `{}`, say why: no focused
   star? no opposite-polarity pair? unification failure (and on which rays)?
   These are the three universal beginner walls.
2. **`(trace expr)`** as a language form (currently tracing is all-or-nothing
   via the CLI).
3. **REPL** — essential for the workbench feel; define a connective, try a
   proof, watch it reduce.

---

## 8. Roadmap

**Step 1 — Purify (mechanical, immediate).** §7.2 removals: parser recovery
machinery, `watch`, then `process` built-in → variadic macros out, import
merge, dedups. Write `KERNEL.md`. Delete `circuits.sg`.

**Step 2 — Reposition the logic-programming examples.** Reframe
`examples/prolog/` as *saturation-style* logic programming (Datalog-like
least-fixpoint semantics, not SLD) or fold the keepers into `relational/`;
Prolog emulation is either a future certified system or explicitly out of
scope, not a debt the kernel owes. (Ray scoping was dropped from this step —
deferred per §5.1.)

**Step 3 — Flagship artifact.** One polished, documented MLL tutorial:
connectives (~50 lines) → correctness criteria as tests → a valid proof
accepted → cut-elimination run → an invalid proof-structure *rejected* → then
change the logic and watch behaviour change. The five-minute answer to "what
is Stellogen for," the centerpiece of the README, the seed of the tool paper.

**Step 4 — Encoding contract + first shape-system.** Document the canonical
code-as-term encoding (§5.2); implement the acyclicity checker and
`in-acyclic` (§3.3 Rung 1) as the first certified fragment; package MLL from
Step 3 as the second system (notation + checker + guarantee).

**Step 5 — `logics/` library.** Classical propositional via resolution,
linear types (complete the `linear_lambda.sg` TODO), automata-as-logic
(acceptance as type membership). Each in the file shape of §4.3, with worked
proofs *and* rejected non-proofs.

**Step 6 — Workbench UX.** Diagnostics, `(trace expr)`, REPL (§7.3).

**Step 7 — Paper + outreach.** Tool paper; position against
Dedukti/Metamath/Twelf (§9); success metric: the first external researcher
formalizes a logic in Stellogen and learns something.

---

## 9. Competitive Landscape

The open-proof-assistant space is not empty. Positioning must be explicit —
reviewers and users will ask.

| Tool | Model | Stellogen's differentiator |
|---|---|---|
| **Dedukti** | Logics as rewrite theories over λΠ-modulo | Dedukti checks derivations against a fixed judgment structure; Stellogen has no fixed judgment structure at all — types are tests, correctness is orthogonality, dynamics (cut-elimination) is native rather than encoded. |
| **Metamath** | Minimal substrate, logics as libraries | Closest in spirit ("logic as library"). Metamath verifies proof *texts* by substitution; Stellogen verifies by *interaction* and has computation as a first-class citizen. |
| **Twelf / LF** | Judgments as types, higher-order abstract syntax | LF fixes the meta-logic; Stellogen's meta-level is user-space and escapable. |
| **miniKanren / Prolog** | Relational programming | Shares unification, but has fixed operational semantics (SLD resolution, cut, clause order). Stellogen deliberately lacks these, and no formal correspondence with SLD semantics has been established (thesis Ch. 9) — so *stop framing anything as Prolog emulation*; the honest framing is "relational reasoning by interaction." |
| **Racket** | Language-oriented programming | The architectural role model for kernel-plus-user-space, not a competitor: Racket's towers are DSLs, Stellogen's are logics. |

The strongest external card is **Ragot 2025** (Appendix A.4): it certifies
the substrate is at least as expressive as the interaction-net world, with
the *added* capability of typing-by-tests.

---

## 10. What to Explicitly Abandon

- General-purpose language ambitions: scripting ergonomics, stdlib breadth,
  **error recovery and incremental parsing (implemented — remove them)**,
  editor-grade tooling in the core.
- Business-rule / configuration DSL use cases; "natural syntax" via custom
  readers or per-system grammars.
- Prolog emulation as a framing (no SLD correspondence exists).
- Faithful synchronous circuits at the substrate level (boundary result;
  tower-level compilation only, if ever).
- DNA/tile computing realism beyond one demo example.
- Full `defsystem` machinery (vocabulary locks, law engines, nested system
  composition) ahead of inhabitants; reintroducing `eval` (term → running
  code, removed 2025-11-16) ahead of a concrete need.

Each of these fights on terrain where the mechanism confers no advantage.
Their good ideas are absorbed by the tower; their ambitions are not.

---

## 11. Audience and Success Criteria

**Primary audience:** logic/PL researchers who want an experimental
instrument for non-standard logics — the community around Dedukti, FSCD,
IJCAR, structural proof theory, implicit computational complexity.

**Secondary audience (onramp):** teaching computation theory. The automata
suite plus the CI-tested exercises are already close to a genuinely good
course artifact; unification + interaction is a vivid pedagogical vehicle for
DFAs, PDAs, and Turing machines.

**Success is not adoption metrics.** It is, in order:

1. The MLL flagship exists and a newcomer understands the project in five
   minutes.
2. A tool paper is accepted.
3. Someone outside the project formalizes a logic in Stellogen and reports a
   result.

**One-sentence identity, for the README and for every future "what is this
for?" moment:**

> Stellogen is not a language that has a type system or lacks one — it is the
> workbench where type systems and logics are user-space artifacts with
> certified guarantees, built over a minimal, pure stellar-resolution kernel.

---

## Appendix A — Findings preserved from the deleted research corpus

The former `ai/research/` corpus (16 documents, largely AI-generated and
explicitly disclaimed as speculative) was deleted on 2026-07-06. Most of its
content was design-space brainstorming pushing toward general-purpose DSL
territory, now abandoned. The durable findings:

### A.1 Circuits and synchronization

Boolean gates need all inputs ground before firing; stellar resolution's
unification is eager and asynchronous, so a gate star unifies as soon as *one*
compatible ray appears, binding outputs to unresolved variables and enabling
spurious interaction chains. The thesis (Ch. 8) treats this as a genuine
impossibility: there is no computationally faithful synchronous circuit
encoding. Workarounds surveyed (CPS-style staging, wrapping values to defer
unification, strictness annotations, multi-phase evaluation) all amount to
*compiling* synchrony into the asynchronous substrate — i.e., tower-level
transformations, the strongest being staged execution via `process` where each
circuit layer is fully resolved before the next is introduced. Conclusion
adopted in §3.4: boundary result, not a bug to fix.

### A.2 Termination

Undecidable in general. Decidable sufficient condition (thesis Ch. 9):
acyclic finite constellations always terminate. Even terminating
constellations can have severe concrete-execution complexity, since
substitution can grow terms unpredictably and interaction order is
nondeterministic. Practical stance: bounded-execution monitoring in the
interpreter; scientific stance: the acyclic fragment as the first certified
shape-system (§3.3, §6.2).

### A.3 Prolog's cut and SLD semantics

Constellations are unordered; there are no clause order, no choice points, no
backtracking — hence no analogue of Prolog's cut, committed choice, or
negation-as-failure. No formal link between stellar resolution and SLD
resolution / Clark completion has been established (thesis Ch. 9). Adopted
consequence: drop the Prolog framing entirely (§9).

### A.4 Interaction nets (the one formal external result)

Ragot [2025] proves stellar resolution simulates interaction nets and
interaction combinators in linear time, with functorial translations
preserving confluence. Constellations are strictly lower-level than nets
(port structure is explicit in terms), which is what enables typing-by-tests
on top. This is the project's strongest citation and belongs in the README
and any paper.

### A.5 Phasing

All checking in Stellogen currently happens at runtime: `::` is an `exec`
plus an equality assertion. There is no compile-time phase. This is
acceptable for a workbench (assertions run when the file runs) and no
multi-phase machinery should be built; if a static flavour is ever wanted,
it falls out of shape-systems (§3.3) run by the interpreter before
evaluation, not from a new phasing architecture.
