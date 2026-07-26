# Optional Typing and User-Defined Type Systems, Shen-Style

**Date:** 2026-07-26
**Status:** exploration. All Stellogen code below was executed against
the current `sgen` binary; outputs are real. Nothing here is in the
repository yet.

---

## 1. What Shen does

Shen (Mark Tarver, successor of Qi) is a Lisp with an unusual bargain:
the language is dynamically typed by default, and the *type system is a
program you write*. Three ingredients matter for us.

### 1.1 Typing is optional and switchable

```shen
(tc +)     \\ turn the type checker on
(tc -)     \\ turn it off
```

Definitions made while checking is on are verified; definitions made
while it is off are not. Typed and untyped code coexist in the same
image and call each other. The type checker is a gate you choose to pass
through, not a wall the language builds around you.

Functions may carry a signature:

```shen
(define double
  {number --> number}
  X -> (* 2 X))
```

The `{...}` is the declared type; Shen checks the body against it.

### 1.2 Types are declared as inference rules

The real content of Shen is `datatype`. You do not pick from a fixed
menu of type formers; you *write the sequent calculus rules* of your
type system:

```shen
(datatype nat

  if (integer? N)
  if (>= N 0)
  ______________
  N : nat;

  N : nat;
  ______________
  [succ N] : nat;)
```

Above the line: premises and side conditions. Below the line: the
conclusion. Premises are themselves typing judgements, so rules compose.

Crucially, premises can be **hypothetical sequents**, which is what makes
binders expressible:

```shen
(datatype lambda

  X : A >> Y : B;
  ___________________________
  [lambda X Y] : (A --> B);

  F : (A --> B); X : A;
  ___________________________
  [F X] : B;)
```

`X : A >> Y : B` reads "assuming `X : A`, we can derive `Y : B`". The
turnstile carries the context. Shen also distinguishes a single line
`_____` (the rule is used in one direction only) from a double line
`=====` (the rule is also usable backwards, i.e. the checker may consult
it to *decompose* a goal).

### 1.3 The checker is a logic program

`datatype` declarations compile to Horn clauses that run on Shen's
built-in Prolog engine, with backtracking, unification, and a cut (`!`)
you can place in rules to prune the search. So Shen's type checker is
literally a logic program over judgements, and the user is writing that
logic program.

The consequences are the selling point: you can build subtyping,
dependent-ish types, units of measure, session types, effect systems,
domain-specific verification — without touching the compiler, and without
the type system being a second language bolted on. Tarver's slogan is
that the type system should be *programmable*.

### 1.4 Why this is the right reference point for Stellogen

Because Stellogen has already arrived at the same destination from the
other side. Shen starts from a Lisp and adds a user-written logic-program
type layer. Stellogen starts from a logic substrate where "a type is a
set of interactive tests" is the *only* notion of type there is. The
Shen-style features are therefore not something to bolt on; they are
mostly a question of *surface syntax and idiom* over machinery that
exists.

The three Shen ingredients map as follows:

| Shen | Stellogen |
|---|---|
| `(tc +)` / `(tc -)` | phase separation: `§` and `sgen check` vs `sgen run` |
| `datatype` inference rules | catalyst stars: positive conclusion, negative premises |
| Prolog engine, unification, backtracking | saturation over the same unification |
| `X : A >> Y : B` hypothetical premise | a context term threaded through the judgement |
| `!` cut / one-way rules (`___` vs `===`) | ground guards `!X` |
| function signature `{A --> B}` | a check-phase `==` assertion on a definition |

The rest of this document works that table out concretely.

---

## 2. Inference rules are already Stellogen's native shape

Stellogen's canonical relational idiom — positive conclusion ray,
negative premise rays, marked catalyst — *is* a natural deduction rule.
The correspondence is exact:

```
    P1    P2
    ---------          becomes        *[(+C ...) (-P1 ...) (-P2 ...)]
        C
```

So a Shen-style rule syntax is not a new mechanism, only a nicer way to
write a star. Parametric definitions can carry literal keywords, which is
enough for a readable sequent notation:

```stellogen
(def (axiom C) [C])
(def (from P1 infer C) [C P1])
(def (from P1 and P2 infer C) [C P1 P2])
```

That is the whole of the "rule DSL". Note that the arguments here are
whole *rays*, not just terms, and it works.

---

## 3. A worked example: simply typed lambda calculus

### 3.1 The context

Shen's `>>` needs a context. In Stellogen the context is just a term
carried through the judgement — a list of `(: var type)` pairs — and
context extension is consing, exactly as in a pen-and-paper presentation:

```stellogen
(def lookup *{
  [(+lk [(: X A)|_] X A)]
  [(+lk [(: Y _)|G] X A) (-lk G X A) || (!= X Y)]})
```

The `||` inequality constraint implements shadowing: an inner binding
hides an outer one of the same name. Shen would need an explicit
side-condition here too.

### 3.2 The rules

```stellogen
(def stlc *{
  #(axiom (+tc _ (num _) int))
  #(axiom (+tc _ tt bool))

  #(from (-lk G X A)
   infer (+tc G (var X) A))

  #(from (-tc [(: X A)|G] B T)
   infer (+tc G (lam X B) (arrow A T)))

  #(from (-tc G M (arrow A T)) and (-tc G N A)
   infer (+tc G (app M N) T))})
```

Compare with the Shen `datatype lambda` above, and with the textbook:

```
    Γ, x:A ⊢ b : T                    Γ ⊢ m : A→T    Γ ⊢ n : A
  ───────────────────────           ─────────────────────────────
   Γ ⊢ λx.b : A → T                        Γ ⊢ m n : T
```

The abstraction rule's premise is `(-tc [(: X A)|G] B T)`: the
hypothetical sequent `X : A >> B : T`, written by consing onto the
context. Nothing in the language had to know about binders.

### 3.3 It infers, not just checks

```stellogen
(def ts *#lookup *#stlc)
(def (typeof E) [(-tc [] E T) (has_type T)])

(show (exec #ts #(typeof (num 3))))
(show (exec #ts #(typeof (lam x (var x)))))
(show (exec #ts #(typeof (lam x (lam y (var x))))))
(show (exec #ts #(typeof (app (lam x (var x)) (num 3)))))
(show (exec #ts #(typeof (app (lam f (app (var f) tt)) (lam x (var x))))))
```

```
(has_type int)
(has_type (arrow A13 A13))
(has_type (arrow A30 (arrow _129 A30)))
(has_type int)
(has_type bool)
```

The identity function gets `(arrow A A)` and `K` gets
`(arrow A (arrow _ A))`. Nobody implemented unification-based inference:
the type variables are Stellogen variables and the engine is already a
unifier. Writing the *declarative* rules gets you the *algorithm* for
free, which is precisely Shen's pitch, delivered with less machinery
because the host language is already resolution.

### 3.4 Type errors are the residue

Ill-typed terms are where Stellogen behaves unlike anything else:

```stellogen
(show (exec #ts #(typeof (app (num 3) (num 4)))))
```
```
[(has_type T7) (-tc %nil (num 3) (arrow int T7))]
```

There is no failure, no exception, no `false`. What comes back is the
partial derivation with the obligation that could not be discharged left
in place: *"I needed `3 : int → T` and could not get it."* That is a type
error message, and it was not written by anyone — it is the shape of the
stuck proof.

This is worth dwelling on. In `ai/research/temporal_logic_and_verification.md`
residue is the main nuisance (failed search branches clutter the result).
Here the same phenomenon is the single most valuable output. The
difference is that a type check runs one deterministic derivation, so
there is exactly one residue and it is the explanation. **Stellogen gets
"errors as unfinished proofs" for free, which is a feature real type
checkers spend serious effort to approximate.**

The practical consequence: a Stellogen type system should be written so
that the judgement is *directed* (one derivation, not a search), because
that is what makes the residue an error message rather than noise. Ground
guards are the tool for that, which brings us to Shen's line notation.

---

## 4. Shen's `___` vs `===` is Stellogen's `!X`

Shen distinguishes rules usable only downwards from rules usable in both
directions, and offers `!` to cut the search. Stellogen's default is the
*more* liberal of the two: a star is a relation, so every rule is
reversible, as §3.3 shows (giving `#(typeof ...)` a free `T` produced
inference rather than checking).

Directionality is recovered by ground guards. `(-tc G !M T)` refuses to
fire until the term is fully known, which turns "any rule that could
conclude this" into "the rule matching this term". Concretely:

- **no guards** → the rules run as a relation: type inference, and also
  *term synthesis* (give the type, get inhabitants — proof search);
- **guard the term** → a type checker: one derivation, one residue,
  readable errors;
- **guard the type** → a bidirectional checking mode.

So the annotation Shen expresses with a choice of horizontal line,
Stellogen expresses with a mark on a variable occurrence, and it is
finer-grained (per position, not per rule). This is the same dial noted
for circuits in the verification document: `!X` is what separates
"execute this description" from "solve this description".

---

## 5. Optionality: `(tc +)` is `§`

Shen's `(tc +)` / `(tc -)` is a mode switch controlling whether
definitions get checked. Stellogen already has the corresponding thing,
and arguably a better version of it, because the split is per-item and
static rather than a stateful toggle.

Wrap the judgement in a macro whose expansion carries `§`, exactly as the
prelude's `::` does:

```stellogen
(macro (has Term Type)
  §(== (exec #ts #(typeof Term)) (has_type Type)))
```

Then:

```stellogen
(has (num 3) int)
(has (app (lam x (var x)) (num 3)) int)
(has (app (num 3) (num 4)) int)
```

`sgen check`:

```
error: assertion failed
  --> shen3.sg:30:1
   |
30 | (has (app (num 3) (num 4)) int)
   | ^
  Expected: (has_type int)
       Got: [(has_type T7) (-tc %nil (num 3) (arrow int T7))]
```

`sgen run`: silent, and the type system is not even evaluated.

That is Shen's bargain, with three improvements that come from the split
being phase-based rather than mode-based:

- **granularity**: `(tc +)`/`(tc -)` is a global toggle with an ordering
  discipline; `§` is per top-level item, so typed and untyped code
  interleave freely without a mode to keep track of;
- **cost**: Shen carries its checker into the image; `sgen run` skips
  check-phase items entirely, so an elaborate type system costs literally
  nothing at run time;
- **error reporting**: the failure is located at the *assertion* site
  with the stuck derivation inline, which is what Shen's checker also
  aims for but has to construct.

Shen also checks definitions *implicitly*: `(define f {A --> B} ...)` is
verified because it was made in typed mode. That closes with a macro,
since a macro expansion may contain several top-level items:

```stellogen
(macro (define Name Type Body)
  (object Name Body)
  §(== (exec #ts #(typeof Body)) (has_type Type)))

(define three int (num 3))
(define applied int (app (lam x (var x)) (num 3)))
(define bad int (app (num 3) (num 4)))
```

`sgen check`:

```
error: assertion failed
  --> shen4.sg:32:1
   |
32 | (define bad int (app (num 3) (num 4)))
   | ^
  Expected: (has_type int)
       Got: [(has_type T7) (-tc %nil (num 3) (arrow int T7))]
```

That is Shen's `define`-with-a-signature, in four lines of prelude, with
the definition available to both phases and the check erased from
`sgen run`.

One caveat: `==` is syntactic, so a *polymorphic* signature does not
work — the inferred `(arrow A13 A13)` will not equal a written
`(arrow A A)` because the variable names differ. Declaring polymorphic
types needs `~=` (unifiability) rather than `==`, or an
alpha-equivalence observation. Worth deciding deliberately: `~=` is
weaker than intended (it also ignores polarity), so a dedicated
"equal up to renaming" base observation may be the honest answer.

---

## 6. Where this could go: type systems as libraries

The point of Shen is not the lambda calculus example; it is that a user
can *ship a type system*. A few that look within reach in Stellogen, in
rough order of effort:

- **Subtyping.** Add a `(-sub A B)` judgement and one subsumption rule.
  Since judgements are just relations, adding a second one and letting it
  interact costs a star.
- **Units of measure / dimensional analysis.** `(m 1)`, `(s -2)` as type
  terms, with an addition rule requiring equal dimension terms. This is a
  showcase for `||` constraints and for the fact that types can carry
  arithmetic.
- **Linear and session types.** Stellogen is already unusually well
  placed here: `examples/lambda/linear_lambda.sg` and
  `examples/proofnets/mll.sg` do linear logic natively, and linearity is
  the *default* behaviour of reactive stars. A `datatype`-style linear
  type system where the context is consumed rather than copied is a
  natural next example, and the "context splitting" that makes linear
  type checking awkward in ordinary languages is just two negative rays
  sharing a list.
- **Effect systems / capability checking.** The judgement carries an
  effect set; the check phase becomes "this program performs no I/O".
  This is the bridge to the verification document: at that point the
  distinction between "type checking" and "model checking" is only how
  much of the program's future the judgement talks about.
- **Refinement types.** The residue-as-error property makes these
  attractive to try, but they need a decision procedure for the
  refinements; saturation is a weak one. Probably the honest ceiling
  without external solvers.

Two things make this list plausible rather than aspirational. First, each
of them is *additive*: a new type system is a new constellation, not a
compiler change. Second, they all get inference, error messages and
optionality from the same three mechanisms, so the marginal cost of the
fourth type system is much lower than the first.

---

## 7. Gaps found while prototyping

These are concrete, small, and all surfaced by trying to write §3–§5.

1. **Macro patterns cannot contain literal symbols.**
   `(macro (rule P1 yields C) ...)` fails with `MacroError`; only the
   head may be a literal, every other pattern position must be a
   variable. Parametric definitions *do* allow literals
   (`(def (from P1 infer C) ...)` works, and `examples/states/nfa.sg`
   relies on it). The asymmetry is surprising and it is exactly what
   blocks a Shen-like `datatype` surface syntax at the macro level.
   Aligning macro patterns with `def` patterns looks like a small change
   with a good payoff.

2. **No "equal up to renaming" observation.** `==` is syntactic, so a
   polymorphic signature cannot be asserted (§5). `~=` is too weak
   (polarity- and guard-blind). A base observation for alpha-equivalence,
   or for one-way matching (is the inferred type an instance of the
   declared one?), is what a real signature check needs. The latter is
   arguably the more useful of the two, since "the inferred type is more
   general than declared" is the standard rule.

3. **No variadic patterns.** `datatype` in Shen takes an arbitrary number
   of rules. Fixed arity means a Stellogen version has to be
   "a constellation of `#(from ... infer ...)` calls", which is honestly
   fine and maybe better. Worth deciding deliberately rather than by
   default.

4. **`#name` does not work in term position.** Fuel bounds, type
   constants and similar have to be written literally inside rays. This
   bit repeatedly in the verification study too. A term-level splice
   would help both.

5. **Residue discipline needs a convention, not a mechanism.** §3.4 shows
   residue as an asset. But that only holds while the judgement is
   deterministic. A documented idiom — "guard your judgement so that
   exactly one derivation runs, and read the residue as the error" —
   should go in the prelude's documentation, because the alternative
   (nondeterministic rules) silently degrades error messages into noise.

---

## 8. Summary

Stellogen does not need to *acquire* Shen's optional typing; it needs to
*notice* that it has the pieces and give them a surface syntax:

- inference rules ≡ catalyst stars with a positive conclusion — no new
  machinery, only `(def (from _ infer _) ...)`-style sugar;
- hypothetical premises ≡ a context list threaded through the judgement;
- the Prolog engine ≡ saturation, and it delivers unification-based
  *inference* rather than mere checking;
- `!` / one-way rules ≡ ground guards, per position rather than per rule;
- `(tc +)`/`(tc -)` ≡ `§` and `sgen check`, per item and with zero run
  time cost;
- and one genuine bonus Shen does not have: **the failed derivation is
  the error message**, because a stuck star is a partial proof rather
  than an exception.

The philosophical fit is close enough to be worth stating plainly. Shen's
position is that a type system is a library. Stellogen's stronger
position is that a type is *nothing but* a set of interactive tests, so
there is no privileged type system to be a library relative to. Shen is
the best available demonstration that the weaker version of this idea is
practical, which makes it a good source of concrete syntax and worked
examples for Stellogen to steal.

### Suggested next steps

1. `examples/types/stlc.sg` — §3 verbatim, with `§(has ...)` assertions.
   It runs today and is a much more convincing type-system demo than
   `examples/sumtypes.sg`.
2. Fix macro literal patterns (gap 1); then move the rule DSL from
   parametric `def`s into the prelude.
3. `examples/types/linear.sg` — linear STLC, playing to Stellogen's
   actual strength and connecting to the existing proof-net examples.
4. Write down the residue-as-error-message idiom in `BASICS.md`; it is
   currently folklore and it is one of the language's better properties.
