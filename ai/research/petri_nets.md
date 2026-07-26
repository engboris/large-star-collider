# Petri Nets in Stellogen

**Date:** 2026-07-26
**Status:** exploration. Every Stellogen snippet below was executed
against the current `sgen` binary and the quoted outputs are real.
Nothing is in the repository yet.

Companion to `temporal_logic_and_verification.md` (the model-checking
machinery reused in §5) and `inspirations_from_other_languages.md` §1
(the chemical-programming reading, which §6 puts to the test).

---

## 1. What a Petri net is

### 1.1 The picture

A Petri net (Carl Adam Petri, 1962) is a bipartite directed graph with
two kinds of node:

- **places** (drawn as circles), which hold **tokens** — think of a place
  as a counter, a buffer, or a condition that can hold several times
  over;
- **transitions** (drawn as bars), which are events that consume tokens
  from some places and produce tokens in others.

Arcs go place→transition (an **input** arc) or transition→place (an
**output** arc), never place→place or transition→transition. An arc may
carry a **weight** `k`, meaning "consumes/produces `k` tokens".

```
        p1 ●●                  p1: two tokens
            \
             ▮ t               t consumes one from p1, one from p2,
            / \                  and produces one in p3
        p2 ●   ● p3
```

### 1.2 Marking, enabling, firing

A **marking** `M` assigns a token count to every place; it is the state
of the net. Everything else is one rule:

- transition `t` is **enabled** at `M` if every input place `p` holds at
  least `W(p,t)` tokens;
- **firing** `t` removes `W(p,t)` tokens from each input place and adds
  `W(t,p')` to each output place, giving a new marking `M'`, written
  `M →t M'`.

That is the whole formalism. There is no control flow, no global clock,
and no scheduler.

### 1.3 Why anyone cares: concurrency, conflict, and the state space

Two properties make Petri nets the reference model of concurrency:

- **Locality.** A transition only looks at, and only touches, its
  neighbouring places. Two transitions with disjoint input places are
  **concurrent**: they may fire in either order, or "at the same time",
  and the result is the same. The net expresses that without saying
  anything about interleaving.
- **Conflict.** Two transitions sharing an input place with only one
  token are in **conflict**: either may fire, and firing one disables
  the other. This is a genuine nondeterministic *choice*, and it is
  where most of the interesting analysis lives.

The classical questions are:

| question | meaning |
|---|---|
| reachability | is `M'` reachable from `M0`? |
| deadlock-freedom | is there a reachable marking where nothing is enabled? |
| boundedness | is the token count bounded, or can a place grow forever? |
| liveness | can every transition always eventually fire again? |
| coverability | is some marking `≥ M` reachable? |
| invariants | linear relations on token counts preserved by every firing |

Petri nets model manufacturing lines, workflow, communication protocols,
mutual exclusion, and (with places as chemical species) reaction
networks. Adding **inhibitor arcs** — "fire only if this place is
empty" — makes them Turing complete; without them, reachability is
decidable but Ackermann-hard.

### 1.4 The example used throughout

Mutual exclusion between two processes. Places `idle_i`, `wait_i`,
`crit_i` for each process, plus one shared place `mutex` holding a single
token:

```
  req_i   : idle_i         →  wait_i
  enter_i : wait_i + mutex →  crit_i
  exit_i  : crit_i         →  idle_i + mutex
```

Initial marking: one token in `idle_1`, one in `idle_2`, one in `mutex`.
The property to verify is that `crit_1` and `crit_2` are never both
marked. It holds because `enter_i` needs the single mutex token.

---

## 2. Two ways to encode a net, and why the choice matters

Stellogen offers two obviously different encodings, and they are not
equally good. It is worth naming both up front:

- **(A) marking-as-a-term.** The whole marking is one term; a transition
  is a rule rewriting that term. This is the state-machine view, exactly
  the shape of `examples/states/nfa.sg`.
- **(B) tokens-as-stars.** Each token is its own star in the
  constellation; a transition is a star that consumes token-rays and
  produces others. This is the chemical view — a token really is a
  molecule floating in the soup.

(B) is the seductive one. It promises *true concurrency*: no global
state object, no interleaving, tokens genuinely distributed. It is also
the one that matches Stellogen's own self-description as a multiset
reaction system.

**(A) is the one that works.** §3–§5 develop it; §6 shows precisely
where (B) breaks and what that says about the language. The short
version of the lesson, stated here so the rest reads in the right light:

> Stellogen's execution branches when a ray has several possible
> partners, and all branches land in the *same* result constellation.
> For branching to mean *choice*, the alternatives must be kept apart —
> which happens automatically when the state is a single term, and
> cannot happen when the state is spread over independent stars.

---

## 3. Encoding A: the marking is a term

### 3.1 Enabling is pattern matching, firing is unification

Represent a marking as one term with one argument per place, and token
counts as unary numerals:

```
  (m I1 W1 C1 I2 W2 C2 X)
```

Then a transition is a single star relating a marking to its successor,
and the whole formalism disappears into the pattern:

```stellogen
(def net *{
  [(+step req1   (m (s I1) W1 C1 I2 W2 C2 X)     (m I1 (s W1) C1 I2 W2 C2 X))]
  [(+step enter1 (m I1 (s W1) C1 I2 W2 C2 (s X)) (m I1 W1 (s C1) I2 W2 C2 X))]
  [(+step exit1  (m I1 W1 (s C1) I2 W2 C2 X)     (m (s I1) W1 C1 I2 W2 C2 (s X)))]
  [(+step req2   (m I1 W1 C1 (s I2) W2 C2 X)     (m I1 W1 C1 I2 (s W2) C2 X))]
  [(+step enter2 (m I1 W1 C1 I2 (s W2) C2 (s X)) (m I1 W1 C1 I2 W2 (s C2) X))]
  [(+step exit2  (m I1 W1 C1 I2 W2 (s C2) X)     (m I1 W1 C1 (s I2) W2 C2 (s X)))]})
```

Read one line, say `enter1`. On the left, `(s W1)` in the `wait_1` slot
and `(s X)` in the `mutex` slot: *these two places must hold at least one
token* — that is the enabling condition, and it is expressed by the
shape of the pattern rather than by a test. On the right the same
variables reappear with the `s` moved to `crit_1`: that is the firing.
The untouched slots are variables carried across unchanged, which is
exactly the locality property of §1.3 — a transition mentions only its
neighbourhood, and the rest of the marking is one variable per place
that it never looks at.

Three consequences worth noticing:

- **Arc weights are free.** An input arc of weight 2 is `(s (s P))`; an
  output arc of weight 3 is `(s (s (s P)))`. No arithmetic relation is
  needed anywhere.
- **Inhibitor arcs are free too.** "Fire only if place `b` is empty" is
  the literal pattern `0` in that slot. Verified:

  ```stellogen
  (def net *{[(+step t (m (s P) 0) (m P (s 0)))]})
  (show (exec *#net [(-step T (m (s (s 0)) 0) M) (fired T M)]))
  ; => (fired t (m (s 0) (s 0)))
  (show (exec *#net [(-step T (m (s (s 0)) (s 0)) M) (fired T M)]))
  ; => [(-step T (m (s (s 0)) (s 0)) M) (fired T M)]      (stuck: not enabled)
  ```

  The extension that takes Petri nets from decidable to Turing-complete,
  and that most tools bolt on as a special arc type, is one character
  here. That is a fair advertisement for pattern matching as a modelling
  primitive.
- **The transition name is data.** Carrying `req1`, `enter1`, ... as the
  first argument costs nothing and buys firing-sequence witnesses in
  §4.2. A net analysis tool without witnesses is not much use.

This is the same shape as `examples/states/nfa.sg`, and it would read
better with the same kind of sugar:

```stellogen
; PROPOSAL, in the style of nfa.sg's (if read C1 on Q1 then Q2)
(def (fire T from M to M2) [(+step T M M2)])
```

### 3.2 Reachability

The net is now a transition system, so the reachability relation is the
bounded-unrolling relation from the verification study, unchanged:

```stellogen
(def reach *{
  [(+reach _ M M)]                                          ; stop any time
  [(+reach (s N) M M2) (-step _ M M1) (-reach N M1 M2)]})   ; or take a step
```

```stellogen
(show (exec *#net *#reach
  [(-reach (s 0) (m (s 0) 0 0 (s 0) 0 0 (s 0)) M) (r M)]))
```
```
{ [(r (m 0 (s 0) 0 (s 0) 0 0 (s 0)))]      ; process 1 requested
  [(r (m (s 0) 0 0 0 (s 0) 0 (s 0)))] }    ; process 2 requested
```

Both successors, because saturation branches on every applicable
transition. Building the reachability graph is not something the
programmer does; it is what the engine does anyway. And here branching
*is* choice, because each branch carries its own complete marking term.

---

## 4. Analysis

### 4.1 Safety: mutual exclusion

The pattern is the "totalize, then filter" idiom: make the verdict a
value, and let the good case reduce to the empty star so that an empty
result means "verified".

```stellogen
(def bad *{                                     ; 1 iff both are critical
  [(+bad (m _ _ (s _) _ _ (s _) _) 1)]
  [(+bad (m _ _ 0 _ _ _ _) 0)]
  [(+bad (m _ _ (s _) _ _ 0 _) 0)]})

(def report *{
  [(+report 1 M) (both_critical M)]
  [(+report 0 M)]})

(def (safety N)
  [(-reach N (m (s 0) 0 0 (s 0) 0 0 (s 0)) M) (-bad !M V) (-report !V M)])

(show (exec *#net *#reach *#bad *#report #(safety (s (s (s (s 0)))))))
```
```
{}
```

Verified to depth 4. Break the net — drop the `(s X)` from `enter2`, so
process 2 no longer takes the mutex — and the same query answers:

```
{ [(both_critical (m 0 0 (s 0) 0 0 (s 0) 0))] ... }
```

Note the shape of `bad`: because there is no negation-as-failure, the
complement cases have to be written out by hand as patterns
(`(m _ _ 0 ...)` and `(m _ _ (s _) _ _ 0 _)`). For a three-place
predicate that is fine; for a large net it is the main ergonomic cost of
this encoding, and it is the same gap that
`temporal_logic_and_verification.md` §4.2 had to work around. Stratified
negation, in the Datalog sense, would remove it.

### 4.2 Deadlock, with a firing-sequence witness

Deadlock is "reachable, and nothing is enabled". Add a marking-shaped
enabledness predicate (again total, again with hand-written
complements), and thread the firing sequence through `reach` as a list:

```stellogen
; p --t1--> q --t2--> r, and nothing leaves r
(def net *{
  [(+step t1 (m (s P) Q R) (m P (s Q) R))]
  [(+step t2 (m P (s Q) R) (m P Q (s R)))]})

(def en *{
  [(+en (m (s _) _ _) 1)]
  [(+en (m _ (s _) _) 1)]
  [(+en (m 0 0 _) 0)]})

(def reach *{
  [(+reach _ M M [])]
  [(+reach (s N) M M2 [T|Seq]) (-step T M M1) (-reach N M1 M2 Seq)]})

(def report *{
  [(+report 0 M Seq) (deadlock M after Seq)]
  [(+report 1 M Seq)]})

(show (exec *#net *#en *#reach *#report
  [(-reach (s (s (s (s 0)))) (m (s (s 0)) 0 0) M Seq)
   (-en !M V) (-report !V M Seq)]))
```
```
{ [(deadlock (m 0 0 (s (s 0))) after [t1 t1 t2 t2])]
  [(deadlock (m 0 0 (s (s 0))) after [t1 t2 t1 t2])] }
```

Both firing sequences that reach the dead marking, which is exactly what
a Petri net tool prints. The witness came for free: `Seq` is a list built
by the same unification that drives the search, not an instrumented log.

### 4.3 Boundedness by covering (Karp–Miller)

A net is unbounded if some reachable `M` **covers** the initial marking
strictly: `M ≥ M0` componentwise with at least one place strictly
greater. (Then the firing sequence that produced the surplus can be
repeated forever.) Comparison on unary counts is addition run backwards:

```stellogen
; unbounded producer:  p --t--> p + b
(def net *{[(+step t (m (s P) B) (m (s P) (s B)))]})
(def plus *{[(+plus 0 Y Y)] [(-plus X Y Z) (+plus (s X) Y (s Z))]})

(def strict *{                       ; at least one delta is non-zero
  [(+strict (s _) _ 1)] [(+strict 0 (s _) 1)] [(+strict 0 0 0)]})

(def rep *{
  [(+rep 1 M) (covering_marking M is_unbounded)]
  [(+rep 0 M)]})

(show (exec *#net *#plus *#reach *#strict *#rep
  [(-step _ (m (s 0) 0) M1) (-reach (s 0) M1 (m A B))
   (-plus (s 0) DA !A) (-plus 0 DB !B)
   (-strict !DA !DB S) (-rep !S (m A B))]))
```
```
{ [(covering_marking (m (s 0) (s 0)) is_unbounded)]
  [(covering_marking (m (s 0) (s (s 0))) is_unbounded)] }
```

`(-plus (s 0) DA !A)` reads "solve `1 + DA = A` for `DA`" — the
subtraction that computes the surplus, obtained by running the addition
relation backwards, which is the same reversibility that
`examples/relational/arithmetic.sg` demonstrates and that
`temporal_logic_and_verification.md` §6.1 exploits for circuits. The
`!A` guard is what stops the solver from also running it forwards and
enumerating markings.

### 4.4 Coloured nets: tokens carrying data

In a coloured Petri net a token is not a bare dot but a value, and a
transition may inspect it. In this encoding a place slot simply holds a
list of values instead of a count, and the transition's guard is a
negative ray:

```stellogen
(def cnet *{
  [(+cstep route (c [V|In] Out Err) (c In [V|Out] Err)) (-ok !V)]
  [(+cstep drop  (c [V|In] Out Err) (c In Out [V|Err])) (-bad !V)]})
(def guards *{[(+ok a)] [(+ok b)] [(+bad x)]})

(show (exec *#cnet *#guards [(-cstep T (c [a x b] [] []) M) (step T M)]))
```
```
{ [(step drop (c [x b] %nil [a])) (-bad a)]     ; guard unsatisfied: stuck
  [(step route (c [x b] [a] %nil))] }           ; a is ok, routed
```

Only the `route` branch completes; the `drop` branch stays as residue
carrying the obligation it could not discharge (`(-bad a)` — *"I would
have needed `a` to be bad"*). That is the same residue-as-explanation
effect as elsewhere, and it is genuinely useful here: the leftover star
tells you which guard failed.

Coloured nets are arguably where Stellogen is *most* competitive with
existing tools, because the colour domain is unification terms rather
than a bolted-on expression language, and guards are ordinary relations.

### 4.5 Temporal properties: the net plugs into the LTL machinery

Because the net is a transition system over marking terms, it is a
Kripke structure, and the LTL evaluator of
`temporal_logic_and_verification.md` §4.3 accepts it unchanged. The only
new code is the labelling — which atoms hold in which markings — and it
is patterns again:

```stellogen
(def labels *{
  [(+val (m _ _ (s _) _ _ (s _) _) both 1)]
  [(+val (m _ _ 0 _ _ _ _) both 0)]
  [(+val (m _ _ (s _) _ _ 0 _) both 0)]})

(def run *{
  [(+run 0 M [M])]
  [(+run (s N) M [M|T]) (-step _ M M2) (-run N M2 T)]})

(show (exec *#bool *#ltl *#net *#labels *#run *#report
  [(-run (s (s (s (s 0)))) (m (s 0) 0 0 (s 0) 0 0 (s 0)) T)
   (-ev (alw (not (p both))) !T V) (-report !V T)]))
```

On the broken net this prints full counterexample traces of markings:

```
{ [(counterexample [(m (s 0) 0 0 (s 0) 0 0 (s 0))
                    (m 0 (s 0) 0 (s 0) 0 0 (s 0))
                    (m 0 0 (s 0) (s 0) 0 0 0)
                    (m 0 0 (s 0) 0 (s 0) 0 0)
                    (m 0 0 (s 0) 0 0 (s 0) 0)])] ... }
```

Nothing had to be adapted: `-t` became `-step`, the states became
markings, and the entire LTL evaluator, the bounded model checker and
the `§`-marked check-phase assertions apply as written. That
composability is the real argument for encoding A — a Petri net is not a
special-purpose thing in Stellogen, it is *one more transition relation*,
and every tool built for transition relations works on it.

---

## 5. What encoding A costs

Being honest about the trade:

- **Interleaving, not true concurrency.** Concurrent transitions are
  modelled by exploring both orders. The state space is the interleaved
  one, so it suffers the usual blowup, and partial-order reduction (the
  standard fix) is not something this encoding can express.
- **A fixed arity.** One argument per place means the net's shape is
  baked into the term, so a generic "fire any transition of any net"
  interpreter needs a different representation (a list of place/count
  pairs, plus multiset arithmetic).
- **Hand-written complements.** Every "not enabled" / "not both
  critical" predicate needs its negative patterns spelled out (§4.1).
- **Duplicate answers and manual fuel.** Both are the tabling gap
  recorded in `inspirations_from_other_languages.md` §2.3: the same
  marking is rediscovered along every path to it, and every recursive
  relation needs an explicit bound. A memoizing engine would turn this
  encoding from "bounded search" into "genuine reachability analysis".

None of these is specific to Petri nets, and three of the four are
already on the backlog.

---

## 6. Encoding B: tokens as stars, and why it fails

This is the encoding the language's own chemical vocabulary suggests: a
token is a star `[(+tok p)]`, a transition is a catalyst consuming
token-rays and producing others.

### 6.1 It works beautifully for the easy case

```stellogen
(def t3 *[(-tok a) (+tok b)])
(def t4 *[(-tok c) (+tok d)])
(show (exec *#t3 *#t4 [(+tok a)] [(+tok c)]))
```
```
{ [(+tok b)] [(+tok d)] }
```

Two independent transitions fired. Not "in some interleaving" — there is
no interleaving here, the two reactions simply happened, locally and
independently, and the final marking is the distributed result. This is
exactly the true concurrency that encoding A gives up, and for the
conflict-free (persistent) fragment of Petri nets it is correct and
elegant.

### 6.2 Failure 1: conflict duplicates tokens

```stellogen
(def t1 *[(-tok p) (+tok q)])
(def t2r [(-tok q) (-tok r) (+tok s)])
(show (exec *#t1 #t2r [(+tok p)] [(+tok r)]))
```
```
{ [(+tok q)] [(+tok s)] }
```

The correct final marking is one token in `s`. What came back is a token
in `s` **and** a token in `q` — the same `p` token was consumed twice,
once down each branch. The reason is the semantics stated in §2: when
`(+tok p)` finds two possible partners, execution takes both, and both
products land in the same constellation. In Petri net terms, Stellogen
resolved a conflict by firing both transitions rather than choosing.

Making the transition reactive instead of a catalyst does not help
(that is what `#t2r` above already is), because the duplication comes
from the *token* having two partners, not from the rule being copied.
There is no way in the current language to say "these two results are
alternative worlds".

### 6.3 Failure 2: a place that is both input and output annihilates

A transition consuming two tokens from `p` and returning one:

```stellogen
(def t5 *[(-tok p) (-tok p) (+tok p)])
(show (exec *#t5 [(+tok p)] [(+tok p)] [(+tok p)]))
```
```
{}
```

Everything vanished. After the rule copy consumes its first token, the
merged star holds `(-tok p)` and `(+tok p)` side by side — dual and
unifiable — so the **internal cut** fires and the transition eats its own
output. The correct answer is one token left in `p`.

Routing the output through a distinct species and relaying it back
(`*[(-tok p) (-tok p) (+new p)]` plus `*[(-new P) (+tok P)]`) avoids the
internal cut but diverges, since the relay and the transition feed each
other indefinitely.

### 6.4 The lesson

This is the same wall that `inspirations_from_other_languages.md` §1.3
hit with Gamma's `max`, and Petri nets make the diagnosis sharper because
the formalism is so simple:

> Stellogen's reaction is **resolution** — merge two stars, cancel a dual
> pair — not **multiset rewriting** — remove tokens, insert tokens. The
> two coincide only when a transition never produces into a species it
> also consumes, and when no token is contested. Petri nets in general
> do both.

And the deeper point, about branching:

> Branching means *choice* only if the alternatives cannot be confused.
> A marking held in one term keeps them apart automatically, because
> each branch owns a complete copy of the state. A marking spread over
> independent stars cannot: the branches share the soup, so a contested
> token gets spent twice.

Both would be fixed by the **membrane** proposed in
`inspirations_from_other_languages.md` §7.1: if a firing could be
enclosed in a boundary that reacts to inertia and then exports its
products, the output could not cut against the inputs, and alternative
firings could be separate solutions rather than a shared soup.
Encoding B is therefore a good acceptance test for that proposal — if a
membrane construct is ever built, `[(+tok p)] [(+tok p)] [(+tok p)]` with
a self-looping transition should give one token back.

---

## 7. What this says about Stellogen

**In favour.** Petri nets land in Stellogen more cleanly than automata
do, because the two hardest parts of the formalism are exactly the two
things unification is good at:

- enabling conditions are patterns, not tests, so weights and inhibitor
  arcs are notation rather than features;
- the frame — "everything the transition does not mention stays as it
  is" — is one variable per untouched place, which is the locality
  axiom written down directly.

And because a net becomes an ordinary transition relation, the entire
verification stack from the LTL study applies to it unchanged, right down
to `§`-marked check-phase assertions that fail at compile time with the
offending firing sequence in the error message.

**Against.** The encoding that makes all of that work is the *sequential*
one. The concurrent encoding — the one Stellogen's own chemical
vocabulary advertises — is wrong for nets with conflict or with
self-loops, for reasons that are structural rather than incidental. It is
worth being clear about this in any user-facing material: Stellogen
executes multisets, but it does not rewrite them.

---

## 8. Next steps

1. `examples/petri/mutex.sg` — §3 and §4.1 as they stand, with the safety
   property as a `§(== ... {})` assertion so `sgen check` verifies it.
   Runs today; it is a better concurrency demo than anything currently in
   `examples/`.
2. `examples/petri/deadlock.sg` — §4.2, since the firing-sequence witness
   is the most immediately convincing output in this document.
3. A `(fire T from M to M2)` sugar in the style of
   `examples/states/nfa.sg`, and a short note that inhibitor arcs are the
   `0` pattern.
4. Coloured nets (§4.4) deserve their own example; that is where the
   comparison with real tools is most favourable.
5. Use §6 as the acceptance test for the membrane proposal, and until
   then keep the tokens-as-stars encoding out of the examples directory —
   it looks right and is wrong, which is the worst combination for a
   teaching example.
6. Longer term, and only after tabling exists: a generic net interpreter
   (marking as a list of place/count pairs, transitions as data) would
   turn this from "a net compiled by hand into stars" into "a Petri net
   library", and would make invariant computation over the incidence
   matrix expressible.
