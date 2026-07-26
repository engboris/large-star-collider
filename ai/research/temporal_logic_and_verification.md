# Linear Temporal Logic and System Verification in Stellogen

**Date:** 2026-07-25
**Status:** exploration. Every Stellogen snippet below was executed
against the current `sgen` binary and the outputs shown are real. None
of it is in the repository yet; this is a design study.

---

## 1. Why this is worth exploring

Stellogen already encodes automata, Turing machines and boolean circuits
directly (`examples/states/`, `examples/circuits.sg`). Those are exactly
the objects that industrial verification tools reason about. A model
checker is, in essence, three things:

1. a **model** of a system (a state machine),
2. a **property** written in a temporal logic,
3. a **search** that either proves the property or produces a
   counterexample trace.

Stellogen gives (1) for free, expresses (2) as an ordinary constellation,
and gets a large part of (3) from saturation itself, because saturation
*is* exhaustive state-space exploration. What is more, Stellogen already
has a phase separation (`sgen check` vs `sgen run`) whose entire point is
"things that are verified before the program runs". Model checking is the
most natural inhabitant of that phase that I can think of.

So the question of this document is: **how far can we push verification
inside Stellogen without adding anything to the kernel?** The answer
turns out to be: surprisingly far, with one recurring obstacle (residue)
that suggests a small language addition.

---

## 2. What linear temporal logic is (for readers who have never seen it)

### 2.1 The problem it solves

Ordinary logic talks about a *state*: "the door is locked", "x > 0".
Reactive systems (operating systems, protocols, controllers, hardware)
are not about one state, they are about **what happens over time**. The
interesting statements are of the form:

- "the two processes are *never* in the critical section at the same
  time" (safety: nothing bad ever happens);
- "*every* request is *eventually* answered" (liveness: something good
  keeps happening);
- "the alarm stays on *until* it is acknowledged".

None of those is a statement about a state. They are statements about an
infinite sequence of states. Linear Temporal Logic (LTL, Pnueli 1977) is
the standard way to write them down.

### 2.2 Traces

Fix a set of **atomic propositions** (`req`, `grant`, `locked`, ...). A
**trace** is an infinite sequence of states

```
  π = s0 s1 s2 s3 ...
```

where each state says which atoms hold in it. "Linear" in the name means
we look at one such sequence at a time (as opposed to branching-time
logics like CTL, which quantify over the tree of possible futures).

### 2.3 The operators

On top of the boolean connectives (`¬`, `∧`, `∨`, `→`), LTL adds four
temporal operators. Write `π^i` for the suffix `si si+1 si+2 ...`.

| operator | reads as | meaning at position `i` |
|---|---|---|
| `X φ` | ne**x**t `φ` | `φ` holds at `i+1` |
| `F φ` | **f**inally / eventually `φ` | `φ` holds at some `j ≥ i` |
| `G φ` | **g**lobally / always `φ` | `φ` holds at every `j ≥ i` |
| `φ U ψ` | `φ` **u**ntil `ψ` | some `j ≥ i` has `ψ`, and `φ` holds at every position from `i` up to (but excluding) `j` |

`F` and `G` are definable: `F φ = true U φ` and `G φ = ¬F¬φ`. The four
example properties above become:

```
  G ¬(crit1 ∧ crit2)          mutual exclusion (safety)
  G (req → F grant)           every request is eventually granted (liveness)
  alarm U ack                 the alarm stays on until acknowledged
  G (idle → X ¬grant)         a grant never comes directly out of idle
```

The `G (... → F ...)` shape is so common it has a name: **response**.

### 2.4 Model checking

A system `M` (a finite state machine, possibly nondeterministic) has a
set of traces: all the infinite runs starting from its initial state.
`M ⊨ φ` means *every* trace of `M` satisfies `φ`. Model checking is the
algorithmic decision of that question. Two things make it valuable in
practice:

- it is **exhaustive**: unlike testing, it considers every interleaving,
  including the one your test suite will never think of;
- when it fails it gives a **counterexample trace**, which is a concrete
  execution you can read, replay and debug.

The classical algorithm (Vardi–Wolper) is automata-theoretic and worth
keeping in mind because it maps onto Stellogen almost verbatim:

1. Build an automaton `A¬φ` that accepts exactly the traces *violating*
   `φ`. (Not a finite-word automaton: a **Büchi** automaton, which reads
   infinite words and accepts when some accepting state is visited
   infinitely often.)
2. Take the **synchronous product** `M × A¬φ`: run both at once.
3. Ask whether that product accepts anything. Since the product is
   finite, an accepted infinite run can always be folded into a
   **lasso**: a finite prefix followed by a cycle. So the question is a
   graph search for a reachable accepting cycle.
4. Empty language ⇒ the property holds. Non-empty ⇒ the lasso is a
   counterexample.

Bounded model checking (BMC, Biere et al.) is the cheaper cousin: only
look for counterexamples of length ≤ k. Incomplete, but it finds shallow
bugs fast and it is what most industrial flows actually run first.

Everything below is one of those two algorithms, written in Stellogen.

---

## 3. A system as a constellation

The running example is a tiny request/grant arbiter with three states.

```stellogen
(def sys *{
  [(+t idle idle)] [(+t idle req)] [(+t req req)]
  [(+t req grant)] [(+t grant idle)]})
```

That is a Kripke structure minus its labelling. The labelling says which
atoms hold in each state. Rather than a set of atoms per state, it is
convenient to store a *total* boolean valuation, because that makes
negation computable rather than a failure test (more on this in §4.2):

```stellogen
(def labels *{
  [(+val idle id 1)]  [(+val idle req 0)]  [(+val idle grant 0)]
  [(+val req id 0)]   [(+val req req 1)]   [(+val req grant 0)]
  [(+val grant id 0)] [(+val grant req 0)] [(+val grant grant 1)]})
```

Both are catalysts: they are consulted, never consumed, exactly like the
transition tables in `examples/states/nfa.sg`.

### 3.1 Traces come out of saturation for free

A finite trace of the system is a path. Bounded unrolling is four lines:

```stellogen
(def run *{
  [(+run 0 S [S])]
  [(+run (s N) S [S|T]) (-t S S2) (-run N S2 T)]})

(show (exec *#sys *#run [(-run (s (s 0)) idle T) (trace T)]))
```

```
{ [(trace [idle idle idle])] [(trace [idle idle req])]
  [(trace [idle req req])]   [(trace [idle req grant])] }
```

This is the first pleasant surprise. In a conventional language,
enumerating all paths of a nondeterministic machine is a worklist
algorithm you write by hand. Here it is *the ambient execution rule*:
when a negative ray can fuse with several catalyst copies, execution
branches into all of them at once. The state space search is not
programmed, it is inherited. Nondeterminism in the model is
nondeterminism in the engine.

Note also that the trace is built by unification, not by an accumulator:
`[S|T]` in the head is filled in by the recursive call underneath it. The
list is a shared variable that both ends of the recursion write into.

---

## 4. An LTL evaluator as a constellation

### 4.1 Formulas are terms

Nothing special is needed to represent a formula; it is a term. Temporal
operators must start lowercase (uppercase is a variable), which is fine
and arguably more readable than `X`/`F`/`G`/`U`:

```
  (p req)            atom
  (not F) (and F G) (or F G)
  (next F)           X F
  (ev F)             F F   ("eventually")
  (alw F)            G F   ("always")
  (until F G)        F U G
```

So `G (req → F grant)` is written

```
  (alw (or (not (p req)) (ev (p grant))))
```

### 4.2 Why the evaluator returns a value instead of proving satisfaction

The obvious encoding would be a relation `(sat φ T)` that resolves when
`T` satisfies `φ`. It does not work well, for a reason that is
instructive: **negation**. Resolution has no negation-as-failure, and
Stellogen has no notion of a star "failing" — a star that cannot react
simply survives in the result as residue. So `(sat (not φ) T)` has
nothing to hook onto.

The fix is to make the evaluator **total**: compute a truth value `0`/`1`
instead of proving a fact. Negation is then a lookup in a two-line truth
table, and every query returns exactly one answer with no residue. The
boolean tables are literally the ones from `examples/circuits.sg`:

```stellogen
(def bool *{
  [(+bnot 1 0)] [(+bnot 0 1)]
  [(+band 1 V V)] [(+band 0 V 0)]
  [(+bor 0 V V)] [(+bor 1 V 1)]})
```

### 4.3 The semantics, verbatim

```stellogen
(def ltl *{
  ; atoms: read the valuation of the current (head) state
  [(+ev (p P) [S|_] V) (-val S P V)]

  ; booleans: evaluate the arguments, then consult the truth table
  [(+ev (not F) T V) (-ev F T A) (-bnot !A V)]
  [(+ev (and F G) T V) (-ev F T A) (-ev G T B) (-band !A !B V)]
  [(+ev (or F G) T V) (-ev F T A) (-ev G T B) (-bor !A !B V)]

  ; next: strong at the end of a finite trace (see §4.5)
  [(+ev (next F) [_] 0)]
  [(+ev (next F) [_ S|T] V) (-ev F [S|T] V)]

  ; eventually: F φ = φ now, or F φ from the next position
  [(+ev (ev F) [S] V) (-ev F [S] V)]
  [(+ev (ev F) [S1 S2|T] V)
    (-ev F [S1 S2|T] A) (-ev (ev F) [S2|T] B) (-bor !A !B V)]

  ; always: G φ = φ now, and G φ from the next position
  [(+ev (alw F) [S] V) (-ev F [S] V)]
  [(+ev (alw F) [S1 S2|T] V)
    (-ev F [S1 S2|T] A) (-ev (alw F) [S2|T] B) (-band !A !B V)]

  ; until: φ U ψ = ψ now, or (φ now and φ U ψ from the next position)
  [(+ev (until F G) [S] V) (-ev G [S] V)]
  [(+ev (until F G) [S1 S2|T] V)
    (-ev G [S1 S2|T] A) (-ev F [S1 S2|T] B) (-ev (until F G) [S2|T] C)
    (-band !B !C D) (-bor !A !D V)]})
```

That is the whole of LTL in twelve stars, and the correspondence with the
textbook recursive semantics is one-to-one. Three Stellogen-specific
remarks:

- **Ground guards do the sequencing.** `(-band !A !B V)` cannot fire
  until `A` and `B` are actual values. Without the guards the truth table
  would be consulted relationally, matching `(+band 1 V V)` with `A`
  still free and spraying speculative branches everywhere. The guard is
  what turns a relation into a function call, and it is the exact same
  idiom `examples/circuits.sg` uses to make a gate wait for its inputs.
  Here it is doing the job of an evaluation order.
- **Recursion on the suffix is the "position" argument.** The textbook
  writes `π,i ⊨ φ`; a cons list suffix is the same thing with the index
  built into the data.
- **No `[]` case anywhere.** Suffixes of a nonempty trace are nonempty,
  hence the `[S]` / `[S1 S2|T]` pattern pairs. This is why the parser's
  nested-tail patterns matter.

Checked against hand-computed values:

```stellogen
(show (exec *#bool *#ltl *#labels
  [(-ev (alw (or (not (p req)) (ev (p grant)))) [idle req grant] V) (result V)]))
; (result 1)
(show (exec *#bool *#ltl *#labels
  [(-ev (alw (or (not (p req)) (ev (p grant)))) [idle req req] V) (result V)]))
; (result 0)
```

### 4.4 Bounded model checking: two rays in one star

Now the punchline. Generating traces is a relation. Evaluating a formula
is a relation. Bounded model checking is **putting both in the same
star** and letting unification connect them:

```stellogen
(def report *{
  [(+report 0 T) (counterexample T)]     ; verdict 0: keep the trace
  [(+report 1 T)]})                      ; verdict 1: vanish

(def machinery *#sys *#run *#bool *#ltl *#labels *#report)

(def (bmc PHI N) [(-run N idle T) (-ev PHI !T V) (-report !V T)])
```

The whole algorithm is that one star. `(-run N idle T)` constrains `T` to
be a legal trace; `(-ev PHI !T V)` evaluates the property on it (the
guard `!T` makes the evaluator wait for a complete trace);
`(-report !V T)` keeps the trace only if the verdict was `0`. The star
that discharges everything with verdict `1` reduces to the empty star and
disappears, so **the result constellation contains exactly the
counterexamples**.

```stellogen
; SAFETY, holds: a grant never comes directly after idle
(show (exec #machinery #(bmc (alw (not (and (p id) (next (p grant))))) (s (s (s 0))))))
```
```
{}
```
```stellogen
; SAFETY, fails: grant never occurs at all
(show (exec #machinery #(bmc (alw (not (p grant))) (s (s (s 0))))))
```
```
{ [(counterexample [idle idle req grant])] [(counterexample [idle req req grant])]
  ... [(counterexample [idle req grant idle])] }
```

An empty constellation means "verified up to depth 3"; a non-empty one is
a set of counterexample traces you can read off directly. There is no
separate counterexample-extraction machinery: the trace was already a
term in the star that witnessed the violation.

The idiom worth naming here is **totalize, then filter**: make the
verdict a value rather than a success/failure, then use a two-clause
catalyst where the good case has no neutral ray left. Empty result =
property holds. It is how you get a boolean answer out of an engine that
has no notion of failure.

### 4.5 Where finite traces stop being enough

Ask the liveness property at the same depth:

```stellogen
(show (exec #machinery #(bmc (alw (or (not (p req)) (ev (p grant)))) (s (s (s 0))))))
```
```
{ [(counterexample [idle idle idle req])] [(counterexample [idle idle req req])]
  ... [(counterexample [idle req req req])] }
```

These are **not** counterexamples. `[idle req req req]` merely ends
before the grant arrives; extend it by one step and it satisfies the
property. This is the fundamental limitation of finite-trace evaluation,
and it is not a bug in the encoding: no finite prefix can ever refute
`F grant`, because liveness violations are inherently infinite objects.

The same tension shows up in the choice made for `next` at the end of a
trace. `[(+ev (next F) [_] 0)]` (strong next: false at the end) is right
for safety properties of the shape `G ¬(a ∧ X b)` — the last position
does not spuriously report a violation. The opposite choice (weak next,
true at the end) is right for obligations. Finite-trace LTL, sometimes
called LTLf, genuinely has both variants, and a real implementation would
carry both operators. It is worth being explicit about this in any
Stellogen library: the choice is a modelling decision, not a detail.

The fix for liveness is to stop looking at finite traces and start
looking at lassos.

---

## 5. Infinite behaviour: monitors, products and lassos

### 5.1 The property becomes an automaton

Instead of interpreting the formula, compile its **negation** into a
monitor automaton, in exactly the style of `examples/states/nfa.sg`. For
`G (req → F grant)`, the negation is "eventually a request after which
grant never occurs", which is a two-state Büchi automaton:

```stellogen
(def mon *{
  [(+mon m0 S m0)]                            ; stay in m0, waiting
  [(+mon m0 req m1)]                          ; guess: this req is never granted
  [(+mon m1 S m1) || (!= S grant)]})          ; from now on, no grant allowed

(def acc *{                                   ; m1 is the accepting state
  [(+accf (cfg S m1) 1)]
  [(+accf (cfg S M) 0) || (!= M m1)]})
```

Two things to notice. The `||` inequality constraint is doing the work of
a complemented transition guard, which is exactly what it is for. And the
`m0 --req--> m1` transition is a *guess*: the automaton nondeterministically
picks the request it claims will never be answered. In Stellogen a guess
costs nothing to write, because branching is the execution rule.

### 5.2 The product is just a star

The synchronous product of the system and the monitor — the construction
that textbooks spend a page on — is one star:

```stellogen
(def prod *[(+step (cfg S M) (cfg S2 M2)) (-t S S2) (-mon M S2 M2)])
```

Both automata step, and the shared variable `S2` forces them to agree on
the letter read. This is the clearest single win in this whole document.
The product automaton is not a data structure that has to be built,
stored and garbage-collected; it is the observation that two constellations
placed in the same interaction space and sharing a vocabulary already
compose. Composition of models is *union of constellations*.

### 5.3 Lasso search, and the guess as a shared variable

An accepted infinite run of a finite product can be folded into a prefix
plus a cycle through an accepting state. Reachability and cycles, bounded
by a fuel argument so saturation terminates:

```stellogen
(def paths *{
  [(+path C C _ [C])]
  [(+path C D (s N) [C|P]) (-step !C E) (-path !E D N P)]})

(def cycles *{                                ; F = 1 if an accepting cfg was seen
  [(+cyc C C _ 0 [])]
  [(+cyc C D (s N) F [C|P])
    (-step !C E) (-accf !E A) (-cyc !E D N B P) (-bor !A !B F)]})

(show (exec #all
  [(-path (cfg idle m0) C (s 0) Pre)              ; reach some configuration C
   (-step !C E) (-accf !E A)                      ; take at least one step
   (-cyc !E !C (s 0) B Loop) (-bor !A !B F)       ; ... and come back to C
   (-report !F Pre [C|Loop])]))
```

```
[(lasso [(cfg idle m0) (cfg req m1)] [(cfg req m1)])]
```

Read: reach `(req, m1)` from the initial configuration, then loop on it
forever. Since `m1` is accepting and the loop stays there, the monitor
accepts, so the system has an infinite run violating `G (req → F grant)`
— the arbiter can leave a request pending forever. That is a genuine
liveness counterexample, and the printed lasso is the debug artifact a
model checker is supposed to hand you.

The elegant part is `C`. In a hand-written nested-DFS you have to
*choose* a loop head and then search for a cycle through it. Here `C` is
one variable occurring in two rays: `(-path ... C ...)` says "C is
reachable", `(-cyc ... C ...)` says "C is on a cycle", and unification
does the choosing. The nondeterministic guess of the classical algorithm
is literally a shared variable.

### 5.4 The honest part: residue drowns the answer

The output above is the *interesting* star. The actual result also
contains several hundred stuck stars — every branch that took a wrong
turn survives, because reactive stars are never weakened. Two distinct
causes:

- **Dead-end branches.** A `(-cyc ...)` that cannot close leaves its rays
  in place. The `nfa.sg` trick applies: a second `exec` stage against
  catch-all positive killers (`*(+cyc _ _ _ _ _)`, ...) erases those rays,
  and since dead-end stars contain no neutral ray they collapse to the
  empty star and vanish. This works, and it removes most of the noise.
- **Guard-blocked rays.** A ray like `(-accf !(cfg grant M) A)` whose
  guarded position never became ground can never fuse — not even with a
  killer. Those stars are unerasable by any in-language means. This is
  the one place where the current kernel leaves no way out.

So the lasso search *works* but does not currently *present* well. This is
not a small ergonomic wrinkle; it is the difference between a
demonstration and a usable tool. See §8.

---

## 6. Beyond LTL: verification of other computational structures

The reason to care about Stellogen here is not that it can host a model
checker (many languages can) but that the models being checked are the
same kind of object as the checker. Two directions.

### 6.1 Circuits already run backwards

Verification of combinational hardware is: given a circuit and a property
of its outputs, find an input violating it. That is a satisfiability
question, and it is normally handed to a SAT solver. In Stellogen the
circuit is already a relation, so the "solver" is just running it in the
other direction:

```stellogen
(def semantics *{
  [(+not 1 0)] [(+not 0 1)]
  [(+and 1 V V)] [(+and 0 V 0)]
  [(+or 0 V V)] [(+or 1 V 1)]})

(show (exec #semantics [(-and 1 0 R) (out R)]))   ; forwards: (out 0)
(show (exec #semantics [(-and A B 1) (sat A B)])) ; backwards: (sat 1 1)
```

Combined with the totalize-then-filter idiom, a property check over a
whole net is again "empty means verified":

```stellogen
(def bad *{[(+bad 0 A) (violation A)] [(+bad 1 A)]})

; is (or A (not A)) ever 0?
(show (exec *#semantics *#bad [(-not A NA) (-or A NA V) (-bad !V A)]))
; {}
; is (or A (and A A)) ever 0?
(show (exec *#semantics *#bad [(-and A A X) (-or A !X V) (-bad !V A)]))
; (violation 0)
```

The interesting observation is about ground guards. `examples/circuits.sg`
puts `!X` on every gate input, which makes the net a *simulator*: data
flows one way, each gate waits for its inputs. Drop the guards and the
same constellation becomes a *solver*: outputs propagate back to inputs
and unification enumerates the satisfying assignments. **The guard
annotation is the dial between execution and verification, on one
unchanged description of the circuit.** I do not know another language
where simulation and SAT-solving of a netlist are the same text with a
different annotation, and this seems like the single most
Stellogen-specific thing in this document.

The obvious next step is sequential circuits: a latch is a state, a
clocked netlist is a transition relation, and §4.4's `run` unrolls it.
That is textbook BMC (unroll `k` cycles, assert the negated property,
solve) with the SAT call replaced by saturation. Saturation is a much
worse solver than a CDCL engine, so this is a semantic demonstration and
not a performance proposal — but the *encoding* is the same, and it
reuses the existing `circuits.sg` vocabulary unchanged.

### 6.2 Verification as a type, in the check phase

Stellogen's type discipline is "a type is a set of interactive tests, and
checking is interaction judged by `==`". A temporal property is exactly
that: a test that the system either passes or fails, evaluated by
interaction. So model checking does not need a new mechanism, it needs to
be dropped into the existing one, with `{}` as the success observation:

```stellogen
§(== (exec #machinery #(bmc (alw (not (and (p id) (next (p grant))))) (s (s (s 0))))) {})
§(== (exec #machinery #(bmc (alw (not (p grant))) (s (s (s 0))))) {})
```

`sgen check` on that file prints:

```
error: assertion failed
  --> bmc.sg:51:2
   |
51 | §(== (exec #machinery #(bmc (alw (not (p grant))) (s (s (s 0))))) {})
   |  ^
  Expected: {}
       Got: { [(counterexample [idle idle req grant])]
              [(counterexample [idle req req grant])] ... }
```

This is, I think, the most convincing artifact in this document. A
temporal property has become a compile-time check, the counterexample
trace appears in the *error message* at the source location of the
property, and `sgen run` skips the whole thing at zero runtime cost. The
phase separation was designed for type assertions, but "the property was
verified before the program was allowed to run" is what verification
tooling has always wanted from a compiler, and here it falls out of a
mechanism that already exists.

With the prelude's macro style this becomes readable:

```stellogen
(macro (models Sys Phi Depth)
  §(== (exec #Sys #(bmc Phi Depth)) {}))

(models machinery (alw (not (and (p id) (next (p grant))))) (s (s (s 0))))
```

`models` is `⊨`. The macro is three lines because all the mechanism it
needs — phase marking, interaction, base observation — already exists.

---

## 7. What this says about Stellogen

Collecting the wins:

- **Nondeterministic search is free.** Branching on multiple fusion
  partners is state-space exploration. No worklist, no visited set, no
  explicit backtracking.
- **Product/composition is union.** The synchronous product of a system
  and a monitor is one star sharing a variable. Modular composition of
  models costs nothing.
- **Guessing is a shared variable.** The loop head of a lasso, the
  "offending request" chosen by a Büchi monitor, the input assignment
  violating a circuit property — all of them are unification variables
  rather than search procedures.
- **Counterexamples are already terms.** No instrumentation is needed to
  extract a witness; the witness is the data the violating star is
  carrying.
- **Direction is an annotation.** Ground guards decide whether a
  description is executed or solved.
- **Verification has a home in the language.** The check phase turns a
  temporal property into a compile-time obligation with source-located
  errors, using only `==`.

And the honest limits:

- **Residue.** Every failed branch survives. This is the dominant
  practical problem and it is discussed in §8.
- **No negation-as-failure.** Workable — totalize the verdict — but it
  means every property must be given a complete valuation, so partial
  models and three-valued abstraction (the basis of most abstraction
  refinement) do not fit naturally yet.
- **Performance is not competitive and will not be.** Saturation
  enumerates; real model checkers use BDDs, SAT/SMT, partial-order
  reduction, symmetry reduction. Stellogen's contribution here is
  conceptual economy, not throughput. That is fine: the interesting claim
  is "these algorithms are *small* in Stellogen", not "these algorithms
  are *fast* in Stellogen".
- **Fuel everywhere.** Termination requires an explicit decreasing
  argument on every recursive relation, so every bound is manual. A
  saturation engine with built-in memoization (the Datalog move) would
  remove most of those fuel arguments and would also collapse the
  duplicate lassos.

---

## 8. The one thing the language seems to need

Every experiment above hit the same wall: **there is no way to observe
only the stars that finished.** Success and failure are both "a star in
the result"; they are distinguished only by whether polarized rays remain.

The `nfa.sg` staged-kill idiom is the current workaround and it is not
good enough:

- it requires writing a catch-all killer for every relation symbol used,
  which does not scale and silently breaks when a symbol is added;
- it is unsound in general — killing rays out of a stuck star can leave a
  neutral ray that then reads as a success;
- it cannot touch guard-blocked rays at all.

What is missing is a **projection observation**. Something in the family
of:

```
(saturated expr)     ; keep only stars with no polarized ray left
(only expr Pattern)  ; keep only stars unifiable with Pattern
```

`saturated` is the more principled of the two: "the answers are the
stars that discharged all their obligations" is a meaningful notion in a
resolution setting, it needs no new syntax in stars, and it does not
require the user to enumerate symbols. With it, §5.3 would print one
lasso, §4.4 would not need the `report` trick, and the totalize-then-filter
idiom would become the ordinary way to write a decision procedure rather
than a workaround. Two smaller items that would follow naturally:

- **memoized saturation**, to drop fuel arguments and duplicate answers;
- a **weaker guard** (`nonvar` rather than fully ground), which would let
  the evaluator start on a partially-built trace instead of waiting for
  the whole thing.

None of these is specific to verification, which is a good sign: model
checking is a demanding enough application to surface general gaps, and
the gaps it surfaces are all about *observing* a saturated constellation
rather than about *computing* one. Stellogen's execution engine appears to
be adequate for this domain already; its observation vocabulary is what
is thin.

---

## 9. Possible next steps

1. Add `examples/verification/ltl.sg`: the evaluator of §4.3 plus the
   BMC driver, with `§(models ...)` assertions. It is self-contained and
   runs today.
2. Add `examples/verification/mutex.sg`: two processes, `G ¬(c1 ∧ c2)`
   verified and a deliberately broken variant producing a counterexample.
   This is the canonical demo and it exercises composition-as-union.
3. Prototype `saturated` in the evaluator and rewrite the lasso search
   against it; measure how much of §5.4 disappears.
4. Sequential circuits: extend `examples/circuits.sg` with a latch and a
   two-cycle unrolling, checking a property with the guards removed.
   This is the clearest demonstration of the simulate/solve dial.
5. Only then consider an LTL-to-Büchi translation in Stellogen itself
   (the tableau construction is not large), which would let a user write
   the formula and get the monitor automaton, closing the gap between §4
   and §5.
