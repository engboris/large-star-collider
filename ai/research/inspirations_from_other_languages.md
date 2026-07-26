# Ideas Worth Stealing: Chemical Programming, Smalltalk, Scheme, Erlang, Prolog

**Date:** 2026-07-26
**Status:** exploration. Every Stellogen snippet marked as executed was
run against the current `sgen` binary and the outputs are real; proposals
for things that do not exist yet are marked as such.

Stellogen's stated influences are Prolog/Datalog, Smalltalk, Rocq,
Scheme, Shen and Girard's transcendental syntax. This document goes back
through five of those families (plus chemical programming, which is not
on the list but should be) and asks, feature by feature: *is this already
in Stellogen, is it worth importing, or does it genuinely not fit?*

The exercise turned out to be more useful than expected, because several
features from very different languages point at the **same three gaps**:
no way to observe only the finished stars, no reaction boundary
(membrane), and no namespacing of ray heads. Those three recur in every
section below and are collected in §7.

---

## 1. Chemical programming (Gamma, CHAM, HOCL, Linda)

### 1.1 What it is

Gamma (Banâtre & Le Métayer, 1986) proposes computing as chemical
reaction. The program state is a **multiset** of data ("molecules"). A
program is a set of **reaction rules**, each a pattern plus a condition
plus an action:

```
  max  =  replace x, y  by x  if x ≥ y
```

Any pair of molecules matching the pattern may react, anywhere in the
multiset, in any order, in parallel. Execution stops at **inertia**: no
rule applies any more. There is no control flow, no data structure, no
ordering — the programmer specifies only what may react.

The Chemical Abstract Machine (Berry & Boudol, 1990) adds two things
Gamma lacks: **solutions** (a molecule may itself be a nested multiset,
written `⟨ ... ⟩`) and the **airlock** operator, which controls what
crosses a solution boundary. HOCL adds *higher-order* chemistry: reaction
rules are themselves molecules, so a reaction can produce new rules.
Linda's tuple space is the same idea used for coordination.

### 1.2 Stellogen is already a chemical language

The match is close enough to be a little startling:

| Gamma / CHAM | Stellogen |
|---|---|
| multiset of molecules | constellation (unordered set of stars) |
| reaction rule | catalyst star |
| reaction condition | unification + `\|\|` constraints |
| any reaction, any order, in parallel | saturation, branching on all partners |
| inertia | saturation; the result *is* the inert multiset |
| catalyst (unconsumed reactant) | `*` — the same word, independently arrived at |
| solution `⟨ ... ⟩` | nested `exec` (partially) |
| higher-order rules | *absent* |

The `*` mark in Stellogen and the notion of catalyst in Gamma mean the
same thing, and CLAUDE.md's phrasing ("looked up as needed and never
consumed") is a chemistry description. So the question is not whether to
adopt the chemical metaphor — Stellogen has it — but which of the pieces
it is *missing*.

### 1.3 The mismatch: resolution is not multiset rewriting

I tried to write Gamma's `max` directly:

```stellogen
(def geq *{[(+geq X 0)] [(+geq (s X) (s Y)) (-geq X Y)]})
(def maxr *[(-n X) (-n Y) (+n X) (-geq !X !Y)])   ; "replace x,y by x if x >= y"
(show (exec *#geq *#maxr [(+n (s 0))] [(+n (s (s (s 0))))] [(+n (s (s 0)))]))
```
```
{ [(-geq !X0 (s 0))] [(-geq !X4 (s (s (s 0))))] [(-geq !X8 (s (s 0)))] }
```

It does not work, and the reason is instructive. When the rule copy fuses
with one `(+n 3)` molecule, the merged star contains *both* the produced
`(+n 3)` and the still-unconsumed `(-n Y)`. Those are dual and unify, so
the **internal cut** fires and the reaction eats itself.

Renaming the output (`(+m X)`) avoids the internal cut, but then the
product cannot react again, so iterating to inertia needs manual staging
with `then` — and that explodes combinatorially (I tried; the output is
hundreds of half-reacted stars).

The finding is worth stating precisely:

> Stellogen is chemical in its **execution discipline** — multiset,
> local, nondeterministic, parallel, run to inertia — but its reaction is
> **resolution** (merge two stars, cancel a dual pair) rather than
> **rewriting** (remove a sub-multiset, insert another). Resolution
> merges; Gamma replaces. The difference only becomes visible when a rule
> wants to *re-emit into the same species it consumes*, which is exactly
> what iterative chemical algorithms do.

This is not a defect to fix by changing the kernel — resolution is the
point of the language. But it does mean the chemical-programming
literature's *examples* (max, sort, primes sieve, convex hull) are not
the natural idiom, and Stellogen documentation should not promise them.

### 1.4 What is worth stealing: the membrane

The CHAM's solution boundary and airlock is the piece Stellogen lacks and
would clearly benefit from. Concretely, a way to say: *let this
sub-constellation react to inertia on its own, then expose only these
rays to the outside.*

```stellogen
; PROPOSAL, does not exist
(def counter (membrane {...internal stars...} exports (+tick _)))
```

This would supply, in one construct, four things currently missing:

- **encapsulation**: internal ray names cannot collide with the
  environment (see §5.4 for why this matters a lot);
- **rounds**: the chemical iteration structure that §1.3 had to fake with
  `then`, and which `ai/research/local_modalities.md` already records as
  kernel debt under "staging";
- **residue containment**: stuck stars inside a membrane never escape,
  which is most of the problem in
  `ai/research/temporal_logic_and_verification.md` §5.4;
- **a home for `then`**: `(then a b)` becomes "put `a` in a membrane,
  react, hand the exports to `b`", which is a definition rather than a
  built-in special case.

The other CHAM/HOCL feature — **rules as molecules**, so that a reaction
can produce a new reaction rule — is a much larger change, because `*` is
currently a static syntactic mark rather than something a computation can
attach. It is the same capability Erlang's hot code loading and Prolog's
`assert` need (§4.4, §5.5), so it may be worth a dedicated study in
`meta_kernel.md` terms rather than a feature request.

### 1.5 Verdict

Already have: the model. Steal: **membranes/airlock** (high value,
touches three separate open problems). Do not steal: Gamma's rewriting
semantics or its example canon.

---

## 2. Prolog

Prolog is the closest relative and the influence is well digested, so
this section is about the parts that were *not* taken.

### 2.1 Already better than Prolog: all solutions

Prolog gives one solution at a time and needs `findall/3` to collect
them; the result of a Stellogen `exec` is already every solution at once,
as a constellation. Saturation over ordered backtracking is a deliberate
and, I think, correct choice.

### 2.2 Definite clause grammars — free, and worth naming

Prolog's DCG notation is sugar for threading a difference list through a
grammar. Stellogen's automata examples are *already written in that
style* — `[(-a [C|W] Q1) (+a W Q2)]` in `examples/states/nfa.sg` is a DCG
rule — and full context-free grammars work today:

```stellogen
(def gram *{
  [(+s S0 S) (-np S0 S1) (-vp S1 S)]
  [(+np S0 S) (-det S0 S1) (-noun S1 S)]
  [(+vp S0 S) (-verb S0 S1) (-np S1 S)]
  [(+det [the|S] S)] [(+det [a|S] S)]
  [(+noun [cat|S] S)] [(+noun [dog|S] S)]
  [(+verb [sees|S] S)]})

(show (exec *#gram [(-s [the cat sees a dog] []) parsed]))   ; => parsed
```

A failing parse is again informative rather than silent:

```stellogen
(show (exec *#gram [(-s [the sees dog] []) parsed]))
```
```
{ [parsed (-noun [sees dog] [sees the cat])] ... }
```

The residue says what the parser wanted and where. That is a parse error
message with a position, obtained for free — the same
residue-as-diagnostic effect noted for type errors in
`ai/research/optional_typing_shen_style.md` §3.4.

Worth stealing: only the *notation*. A `(grammar s --> np vp)` sugar over
parametric definitions would cost a few lines and would make the
connection to `examples/states/` explicit for readers.

### 2.3 Tabling (XSB) — the biggest single win available

Every recursive relation in the verification and typing studies needed a
manual **fuel argument** to guarantee termination, and every search
produced duplicate answers. Both are exactly what SLG resolution/tabling
fixes: memoize each call, detect repeats, reach a least fixed point.

For Stellogen this would mean:

- left-recursive and cyclic relations (graph reachability with a free
  endpoint, which `examples/relational/arithmetic.sg` explicitly warns
  against) would terminate;
- fuel arguments would largely disappear;
- duplicate results would collapse;
- and the engine would become genuinely Datalog-like, which is what
  CLAUDE.md already claims saturation resembles.

The cost is a real change to the executor (a call table, subsumption
checking) and a semantic decision about whether memoization is sound in
the presence of ground guards and `||` constraints. It is the highest
value/effort ratio item in this whole document, and it is worth a
dedicated design note.

### 2.4 Constraint logic programming (CLP(FD), attributed variables)

Stellogen's `|| (!= X Y)` is a one-constraint constraint store. Prolog
systems generalise this to arbitrary domains: attach a domain to a
variable, propagate, and only enumerate when propagation is exhausted.

The pull for Stellogen is specific: the verification study showed that
circuits run backwards *are* a SAT solver, and that saturation is a bad
one. A finite-domain constraint store attached to variables would make
backward circuit execution and bounded model checking tolerable rather
than merely demonstrable. It also fits the existing `||` syntax:
`|| (in X [0 1])`, `|| (= (+ X Y) Z)`.

This is a large project and probably the wrong one for a research
language to take on directly. A more proportionate version: allow `||`
constraints to be an extensible set with a documented interface, so the
question can be revisited without touching the kernel again.

### 2.5 Cut, assert/retract, and the occurs check

- **Cut (`!`)**: deliberately rejected, and rightly — it depends on
  clause order, which Stellogen does not have. The legitimate need behind
  it (pruning the search) is better served by ground guards, which are
  declarative.
- **`assert`/`retract`**: a dynamic clause database. In Stellogen terms,
  a reaction that installs a new catalyst. Same capability as HOCL's
  higher-order rules (§1.4) and Erlang's hot loading (§4.4). Three
  independent traditions asking for the same thing is a signal.
- **Occurs check**: Prolog omits it by default and is unsound as a
  result; Stellogen does it. No change needed, but it is a point worth
  making in the documentation, since it is a place where the "toy"
  language is more correct than the mature one.

### 2.6 Verdict

Already have or better: all-solutions, DCG shape, occurs check. Steal:
**tabling** (highest value), DCG notation as sugar. Consider: an
extensible constraint interface. Do not steal: cut.

---

## 3. Smalltalk

### 3.1 The philosophical alignment is already there

Smalltalk: everything is an object, the only operation is sending a
message, and the language is defined by a handful of rules. Stellogen:
everything is a star, the only operation is fusion, and the kernel is one
rule. CLAUDE.md's "message passing" influence is real — a positive ray is
an offer and a negative ray a request, and matching them by name and
shape is a message send with pattern-matched dispatch.

Two differences are worth keeping in view: Smalltalk's dispatch is
directed (a message has *one* receiver) whereas fusion is symmetric and
may branch; and Smalltalk's objects have identity and mutable state
whereas stars have neither. The second is a feature, not a gap.

### 3.2 `doesNotUnderstand:` — the residue handler

Smalltalk's most distinctive reflective hook: when a message finds no
matching method, the runtime calls `doesNotUnderstand:` on the receiver,
handing it the message as an object. Proxies, remote objects, DSLs and
mocks are all built on it.

Stellogen's equivalent situation is precise and currently unhandled: a
ray reaches saturation without ever finding a partner. Today that ray
just sits there, and the only recourse is the `kill` idiom from
`examples/states/nfa.sg` — a hand-written catch-all positive ray in a
second `exec` stage. That idiom is fragile (it must enumerate every
symbol), unsound (killing a ray can leave a neutral ray that then reads
as success), and it cannot touch guard-blocked rays.

The Smalltalk framing suggests the right shape:

```stellogen
; PROPOSAL, does not exist
(def fallback ?[(+add X Y unknown)])   ; '?' : fires only at saturation
```

A star marked as a **saturation handler** would be inert during normal
execution and offered only to rays that have no other partner once
nothing else can react. That single mechanism would give:

- a principled `kill` (a handler that produces nothing);
- error reporting (a handler that produces a diagnostic term);
- defaults and fallbacks in relational code;
- proxies: a handler that reifies the unmatched ray and forwards it.

It also composes with the "keep only finished stars" observation that the
verification study asked for: `doesNotUnderstand:` is that observation
turned into a hook instead of a filter, and it is the more Stellogen-ish
of the two because it stays inside interaction rather than adding an
outside-the-language projection.

### 3.3 The image and the inspector

Smalltalk's other great idea is the live image: the running system is the
development environment, and you inspect and edit objects while they run.
Stellogen has `sgen trace`, which is the seed of this.

Given the chemical reading of the language, the natural version is a
**reaction vessel REPL**: a persistent constellation you add stars to and
watch react, with the ability to pause at saturation, inspect the residue,
inject a molecule, and continue. This is a tooling project rather than a
language change, but it is unusually well motivated here for two reasons.
First, the main difficulty of writing Stellogen (as the other two studies
both concluded) is understanding *why* a star got stuck, and an inspector
answers exactly that. Second, an incremental engine is the natural home
for the `@`-slices and the confluent-fragment work already planned.

`ai/research/playground_ux.md` presumably overlaps here; the Smalltalk
angle to add is that the vessel should be *persistent and editable*, not
a run-and-print loop.

### 3.4 Traits over inheritance

Smalltalk-family languages ended up preferring traits (composable named
groups of methods) over deep inheritance. Stellogen already has the
better version of this: a constellation is a set of stars, and
composition is union. `(def m *#lookup *#stlc)` in the typing study is a
trait composition. Nothing to steal; worth saying out loud in the
documentation, because "how do I structure a large program" currently has
no answer and "union of constellations, with membranes for
encapsulation" is a good one.

### 3.5 Verdict

Already have: message-passing semantics, trait-style composition. Steal:
**`doesNotUnderstand:` as a saturation handler** (solves a problem three
other sections also raise), and the **live inspectable vessel**.

---

## 4. Erlang / Elixir

### 4.1 Processes and mailboxes map cleanly

An Erlang process is a private state plus a mailbox plus a `receive`
loop that pattern-matches messages. A `gen_server` is that loop
factored into a behaviour. Written in Stellogen it is a recursive
relation over a message list, and it works today:

```stellogen
(def counter *{
  [(+loop N []) (stopped N)]
  [(+loop N [inc|Ms]) (-loop (s N) Ms)]
  [(+loop N [get|Ms]) (reply N) (-loop N Ms)]})

(show (exec *#counter (-loop 0 [inc inc get inc])))
```
```
[(reply (s (s 0))) (stopped (s (s (s 0))))]
```

The reply and the final state come out together, because the star
accumulates its outputs rather than performing them. Notice also that
`share-nothing`, Erlang's central discipline, is not a convention here
but a law: **variables are local to a star**, so two stars physically
cannot share mutable state.

### 4.2 Selective receive, and what ground guards already do

Erlang's `receive` scans the mailbox and takes the *first* message
matching one of its patterns, leaving the rest queued. This is how you
write "wait for the reply to *this* request, ignore unrelated traffic".

Stellogen's ground guard is a partial analogue: `(-f !X R)` refuses to
fire until `X` is known, which is "wait until this arrives" rather than
"pick this out of a queue". The mailbox-as-list encoding above is
explicit and works, but it is sequential; a genuinely concurrent
selective receive would want the mailbox to *be* the surrounding
constellation, with the process picking rays out of it. That is what
fusion does — so arguably Stellogen has selective receive and lacks only
the *ordering* guarantee, which it deliberately does not want.

Where this becomes interesting is fairness. Erlang's scheduler is
preemptive and fair; Stellogen's saturation has no fairness notion at
all. For a language that wants to model concurrent systems (and the
verification study says it should), the absence of a fairness assumption
is a semantic gap, not just an implementation one: liveness properties
are only meaningful relative to a fairness condition. This connects
directly to the confluent-fragment engine decision already recorded in
project notes — fairness is a property that decision should be checked
against.

### 4.3 Let it crash, and supervision

Erlang's error philosophy: do not defensively code, let the process die,
let a supervisor restart it in a known-good state. The Stellogen analogue
is almost too neat — a stuck star *is* a crashed process, and it is
already isolated (its variables are local, so it cannot corrupt anything
else). What is missing is the supervisor: something that notices the
crash and reacts to it. Which is, again, §3.2's saturation handler.

So "let it crash" is a good frame for what Stellogen should say about
residue: do not try to make every star succeed; let failures be visible
objects and give the programmer a way to react to them at saturation.
That is a more attractive story than "residue is noise you must kill",
and it is closer to what actually happens.

### 4.4 Hot code loading

Erlang can replace a module in a running system. In Stellogen terms:
replace a catalyst mid-execution. Blocked by the same thing as HOCL's
higher-order rules and Prolog's `assert` (§1.4, §2.5): `*` is static.
Third independent request for the same capability.

### 4.5 Behaviours

`gen_server`, `gen_statem` etc. are parameterised templates: you supply
the callbacks, OTP supplies the loop. Stellogen's parametric definitions
already do this — `(def (if read C1 on Q1 then Q2) ...)` in
`examples/states/nfa.sg` is a behaviour for state machines. Worth
generalising into a small library of such templates (automaton, gen
server, pipeline stage) rather than a language feature.

### 4.6 Verdict

Already have: share-nothing, actor shape, pattern-matched dispatch.
Steal: **"let it crash" as the framing for residue**, plus the supervisor
hook (= §3.2). Confront: **fairness**, which is a semantic gap with
consequences for verification. Blocked on reflection: hot loading.

---

## 5. Scheme

### 5.1 Ellipsis patterns in macros

`syntax-rules` matches variadic shapes with `...`:

```scheme
(define-syntax my-or
  (syntax-rules ()
    ((_) #f)
    ((_ e) e)
    ((_ e1 e2 ...) (let ((t e1)) (if t t (my-or e2 ...))))))
```

Stellogen's macros are fixed-arity with no ellipsis, and — a separate
limitation found while prototyping the Shen study — **their patterns
cannot contain literal symbols** other than the head:
`(macro (rule P1 yields C) ...)` fails with `MacroError`, while the
equivalent parametric definition `(def (from P1 infer C) ...)` works.
That asymmetry is what blocks readable rule DSLs at the macro level.

Two changes, in order of value:

1. allow literal symbols in macro patterns, matching what `def` already
   does — small, and it immediately enables sequent-style and
   DSL-style notation;
2. add ellipsis patterns — larger, and it enables `datatype`-style blocks
   with an arbitrary number of rules, `n`-ary `then`, and variadic
   constellation builders.

### 5.2 Quasiquotation and term-level splicing

Scheme's `` `(a ,x c) `` builds a datum with a computed hole. Stellogen
has no equivalent: `#name` works at expression level but **not inside a
term**, which bit in every study — fuel bounds, type constants and
formulas all had to be written out literally inside rays, and
`#(bmc PHI #k)` silently produces the term `(# k)` rather than
substituting.

A term-level splice is the fix, and it should probably reuse `#`:

```stellogen
(def depth (s (s (s 0))))
(def query [(-run #depth idle T) (trace T)])   ; PROPOSAL: # inside a ray
```

Of everything in this document, this is the smallest change with the most
immediate day-to-day effect on writing Stellogen.

### 5.3 Hygiene

Scheme macros are hygienic: identifiers introduced by a macro cannot
capture identifiers at the use site. Stellogen has an unusual situation
here, because variables are already star-local — the usual capture
problem is mostly absent by construction. But *ray head names* are
global, and a macro that introduces a fresh ray head (say a helper
`(+tmp ...)`) can absolutely collide with the use site. Hygiene for
Stellogen therefore means hygiene over ray names, not variables, which
leads straight to the next point.

### 5.4 Modules, and why namespacing is urgent here

R7RS libraries have explicit imports and exports and renaming. Stellogen
has `(use "path")`, which imports everything with no namespace.

This is more dangerous in Stellogen than in an ordinary language, because
**ray head names are the linking mechanism**. Importing a file does not
merely add names you might shadow; it adds stars that will *react* with
yours. Demonstrated:

```stellogen
(def lib_a *{[(+add 0 Y Y)] [(-add X Y Z) (+add (s X) Y (s Z))]})
(show (exec *#lib_a [(-add (s 0) (s 0) R) (r R)]))
; => (r (s (s 0)))

; a second library, written independently, that also happens to say 'add'
(def lib_b *{[(+add A B (colour A B))]})
(show (exec *#lib_a *#lib_b [(-add (s 0) (s 0) R) (r R)]))
```
```
{ [(r (colour (s 0) (s 0)))] [(r (s (s 0)))] [(r (s (colour 0 (s 0))))] }
```

The correct answer is still in there, next to two nonsensical ones, and
*nothing was shadowed or overwritten* — the two libraries simply
interfered. As soon as Stellogen has more than a handful of shared
libraries this will happen constantly, and it will produce wrong answers
rather than errors.

Two complementary fixes:

- **renaming imports**: `(use "arith.sg" as ar)` prefixing every ray head
  the file introduces, so `ar/add`. Cheap, purely syntactic, solves the
  accidental case.
- **membranes** (§1.4): a constellation whose internal vocabulary is not
  visible outside at all. Solves the deliberate case and gives
  encapsulation.

This should probably be considered the most urgent *practical* item in
the document, distinct from the most *interesting* ones.

### 5.5 Continuations

`call/cc` reifies the rest of the computation. Stellogen has a natural
notion of "the rest": a star's remaining unfused rays are precisely the
obligations still outstanding, which is a continuation in normal form.
The residue that all three studies keep tripping over is, read
generously, *a first-class continuation you cannot yet invoke*. Delimited
continuations correspond to membranes.

I do not think there is a concrete feature request here yet, but it is a
good lens: the recurring complaint "I cannot tell finished stars from
stuck ones, and I cannot do anything about the stuck ones" is the
complaint that continuations are visible but not manipulable.

### 5.6 Verdict

Steal, in order: **term-level splicing** (smallest, highest daily value),
**literal symbols in macro patterns**, **module renaming**, ellipsis
patterns. Keep in mind: continuations as a frame for residue.

---

## 6. Two influences already listed, briefly

**Rocq/Coq.** The check phase plus `==` is a proof obligation mechanism,
and the typing study showed a stuck derivation is a readable error. The
piece Rocq has that Stellogen does not is *tactics* — a language for
constructing derivations interactively. Given the reaction-vessel idea
(§3.3), an interactive mode where the user drives fusions by hand toward
a goal is a natural convergence of the Smalltalk inspector and the Coq
proof assistant. Speculative but well-founded.

**Datalog.** Named in CLAUDE.md as the model for saturation. The two
things Datalog has that Stellogen lacks are exactly §2.3's tabling
(semi-naive evaluation to a fixed point, no duplicates) and stratified
negation. The latter would give the negation-as-failure that the LTL
study had to work around by totalising the verdict. Both are engine work,
both are well understood, and both would remove workarounds rather than
add surface.

---

## 7. The three things everything points at

Across five language families, the same three gaps came up repeatedly.
That convergence is the main result of this document.

### 7.1 A reaction boundary (membrane)

Requested by: CHAM solutions and airlock (§1.4), Scheme modules (§5.4),
delimited continuations (§5.5), and independently by the `then` staging
debt already recorded in `ai/research/local_modalities.md` and by the
residue containment problem in the verification study.

One construct — react to inertia in isolation, export a declared
interface — would address encapsulation, namespacing, staging, rounds and
residue containment at once. It is the single highest-leverage addition
identified here.

### 7.2 Something to do about unfinished stars

Requested by: Smalltalk's `doesNotUnderstand:` (§3.2), Erlang's
supervision (§4.3), the `kill` idiom's inadequacy in
`examples/states/nfa.sg`, the counterexample-extraction problem in the
verification study, and the fact that the typing study's *best* feature
is residue read as an error message.

The two candidate shapes are a **projection observation**
(`(saturated e)` keeps only stars with no polarized ray left) and a
**saturation handler** (`?[...]` stars offered only to otherwise-unmatched
rays). The handler is more expressive and stays inside interaction; the
projection is smaller and easier to specify. They are not exclusive, and
the projection is probably the right first step.

The framing matters as much as the mechanism. "Residue is noise to kill"
is the current implicit story and it is wrong: residue is a partial
proof, a type error, a parse error, or a crashed process, and the
language should let you *react* to it rather than only erase it.

### 7.3 Namespacing of ray heads

Requested by: Scheme modules (§5.4), macro hygiene (§5.3), CHAM
encapsulation (§1.4). Unlike the other two this is not conceptually deep,
but it is the one that will bite first in practice, because in Stellogen
an accidental name collision between two libraries silently produces
extra wrong answers instead of an error. `(use "f.sg" as p)` with head
prefixing is a few hours of work and should probably just be done.

### 7.4 Runners-up

- **Tabling** (§2.3): would remove fuel arguments, duplicate answers, and
  a whole class of nontermination. Highest value/effort ratio of the
  engine-level items.
- **Term-level `#` splicing** (§5.2): smallest change, most immediate
  quality-of-life gain.
- **Literal symbols in macro patterns** (§5.1): unblocks DSL notation and
  removes an unexplained asymmetry with `def`.
- **Reflection** (`*` as something a reaction can produce): requested
  independently by HOCL, Prolog's `assert` and Erlang's hot loading.
  Large, deserves its own study.
- **Fairness** (§4.2): a semantic gap that matters as soon as Stellogen
  claims to model concurrent systems.

---

## 8. What not to steal

Worth recording, because the temptation is real and the answer is no:

- **Prolog's cut and clause order.** Depends on an ordering Stellogen
  does not have and should not acquire.
- **Gamma's rewriting semantics.** Resolution is the point; adding
  multiset rewrite rules alongside it would be a second, incompatible
  execution model (§1.3).
- **Smalltalk's object identity and mutable state.** Star-local variables
  and immutability are load-bearing.
- **Erlang's process addressing.** Naming a receiver would break the
  symmetry of fusion, which is what makes composition-by-union work.
- **A fixed type theory from Rocq.** The whole position of the language
  is that there is not one.

The pattern is that Stellogen should take *ergonomics, tooling and
boundaries* from these languages and refuse their *execution models*. The
kernel is not the part that needs help.
