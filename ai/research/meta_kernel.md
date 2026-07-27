# The Meta-Kernel: Admission Rule, Census, and Reflection

**Date:** 2026-07-07
**Status:** Design note. Companion to `evaluation_and_directions.md`
(sections 5.2, 5.4, 7.3), `refocusing_plan.md` (2.5.2, 2.9),
`macro_system.md`, and KERNEL.md parts II and IV. Written after the
meta-kernel census question: what is fair to add to the meta-kernel,
what is lacking, what deserves factorization.

---

## 1. The question

The meta-kernel is a small glue language: it names, assembles, runs, and
observes constellations. Like any language it invites additions, and
without a rule for admission it will accrete forms the way glue languages
always do. This note fixes the rule, applies it to the current forms, and
then addresses the deeper problem the census exposes: the meta-kernel's
expressivity ceiling is its fixed menu, and some practices will
legitimately need ways of executing and observing that the menu does not
offer.

## 2. Stratification and the admission rule

The meta-kernel divides into four strata, each with its own bar:

1. **Read-time** (`use`, `macro`): term-to-term rewriting only, no
   evaluation. Fair to add: anything preserving "programs are terms"
   (aliases, import prefixing; see `macro_system.md`). Never fair:
   anything inspecting run-time results.
2. **Assembly** (`def`, `#`, `@`, galaxy formation): naming and grouping
   only, no computation. Essentially complete.
3. **Execution** (`exec`): the one interaction operation. Its
   axes are not separate execution forms but modalities on stars: `@`
   (focus) and `*` (linearity, which subsumed the former `fire`). Fair
   to add: a genuinely new axis, preferably as a modality; a step
   bound (fuel) is the only other candidate in sight (section 8).
4. **Observation** (`show`, `==`, `~=`, `forall`): the trusted base.
   Every practice's soundness bottoms out here, so each addition is
   something all users must trust rather than inspect. Highest bar.

**The rule: a form is admitted only if it is inexpressible by the strata
below it plus macros, and observation-stratum additions cost the most.**
Intent, ergonomics, and convenience never qualify; that is what macros
and aliases are for.

## 3. Census of the current forms

Applying the rule sorts the current fourteen forms into three groups.

**Genuine primitives.** `def`/`#` (the environment), `@` (focus), `*`
(linearity), `exec` (the interaction interface), `show` (the only
effect), `==` (the trusted judgment). No argument.

**Stranded by the fixed-arity macro system.** `spec` (settled: an alias
of `def`, demotes when bare-symbol aliases land; see `macro_system.md`
pillar 3).

**Earn their seats, but need sharper justification.**

- `~=` is primitive for a clean reason worth stating in KERNEL.md:
  polarity-blindness is inexpressible from inside the language.
  Interaction always respects polarity, and no object-level or
  macro-level operation strips or flips polarities inside an arbitrary
  term, so "compatible, ignoring polarity" is a judgment only the meta
  level can render. However, its current *strength* looks accidental
  rather than chosen: the implementation flattens both constellations to
  ray lists and succeeds if any single ray of one unifies with any
  single ray of the other. `(~= {[a] [x]} {[x] [b]})` passes. That is a
  very weak judgment for the trusted base, and probably not what a
  practice author assumes from "check unifiability of constellations".
  Candidate revisions: star-wise matching, or every-ray-has-a-partner,
  or keep the existential reading and state it loudly in the spec.
- `forall` looks ad hoc only if read as a quantifier (where is
  `exists`? why no combination of judgments?). Read structurally it is
  forced. Galaxies are the meta-level's only collection; a collection
  needs exactly one eliminator; `forall` is it. Its real content is
  **separation of interaction spaces**: run the tested constellation
  against each member in isolation. Separation is a meta-level notion by
  construction; no object-level encoding can express "these tests must
  not see each other", because putting them in one constellation is
  precisely what un-separates them. The missing `exists` is not missing:
  existential checking is running against the union of tests in a single
  space, which the object level already expresses for free.
  Universal-with-separation is the only member of the family needing
  meta-level help, and it is the one that exists. The implementation
  confirms the framing: `forall` discards environment changes made by
  its body; it is a judgment iterator, deliberately not a loop.

**Why assertions stay effects.** Assertions being effects rather than
values is what keeps the trusted base logic-free. The moment judgments
become combinable values (booleans, and/or/not), a propositional logic
is installed in the kernel of a logic-agnostic language. The only
aggregation is "all assertions in the program must pass", and `forall`
is its bounded form. This is the minimal and philosophically consistent
choice, and it is also why judgment combinators are rejected in
section 9.

## 4. The expressivity ceiling

The census settles what the menu should contain, but the deeper problem
is that a fixed menu is a ceiling. Macros can rearrange
`exec`/`==`/`~=` but can never create a new execution discipline
or a new judgment. The `::lin` practice (`examples/proofnets/mll.sg`)
exists only because the `*` modality happened to be on the menu. The
next practice
that needs "run for at most n steps", or "the result contains no
polarized ray", or "equal up to star reordering", is stuck. The pressure
for "more flexibility in execution and observation" is real and will
recur with every serious practice.

## 5. Three ways to lift the ceiling

**Way 1: grow the menu case by case** (add a disequality assertion, an
emptiness check, a fuel variant, ...). Honest but losing: every practice
with a new need files a kernel request, the observation stratum
accretes, and the trusted base grows monotonically. This is how glue
languages rot.

**Way 2: make the glue a real programming language** (values,
conditionals, functions at the meta level). The precedent is LCF: ML was
invented because proof tactics needed real programming. But LCF had to,
because its object language (logic formulas) could not compute.
Stellogen's object language computes. A second programming language on
top of the first duplicates machinery, bloats the trusted base, and
quietly turns Stellogen into a scripting language with a unification
library. Rejected.

**Way 3: reflection.** The object level is already the programming
language; what is missing is the bridge between levels. The precedent is
exact: Maude faced this same question (users wanting custom rewrite
strategies and custom analyses) and answered with its META-LEVEL, where
terms and modules reify as data and strategies are written in Maude
itself. Lisp's quote/eval is the same move. Stellogen is unusually well
prepared for it: the read-time %-encoding already defines what
constellations look like as terms, KERNEL.md part III already treats it
as a contract, and the evaluation doc (5.2) already established that
quotation of *code* exists structurally. Reflection also fits the
theory: reifying dynamics into a static inspectable object is the
thesis's Constat move.

This note adopts way 3, staged as two primitives of very different cost.

## 6. The cheap half: quote (results become data)

One new meta-form that takes an execution result and yields its
%-encoding as an inert term. Note what is new here relative to
evaluation doc 5.2: that section covers reified *code* (programs are
already terms at read time). This is reification of *results*. Today an
execution result is a constellation-as-value that can only be shown,
compared by `==`/`~=`, or fed onward as the input of another `exec`; it
can never
be inspected as data. Quote closes that gap.

With it, every observation becomes ordinary object-level programming
over encoded data, judged by `==` against `ok`:

- emptiness and non-emptiness of results;
- "no polarized ray remains" (saturation reached cleanly);
- equality up to star reordering;
- counting results;
- disequality: `!=` bans already exist at the object level, so negative
  tests need no new assertion form;
- `~=` itself: over a reified term, polarity is structure to match on,
  so polarity-blind matching becomes user space and the census's
  primitivity argument for `~=` (section 3) is retroactively discharged.

The trust trend inverts. Way 1 grows the trusted base with every need;
quote shrinks it: `~=`, disequality, and every future judgment move from
"forms all users must trust" to "code any user can read", bottoming out
in the single judgment `==`. The kernel converges toward `def`/`#`, the
star modalities, one execution operation, quote, `show`, and `==`. This is
a stronger version of the LCF factoring than the current one (KERNEL.md
part IV).

**Prerequisite: polarities must be inspectable in reified terms.** An
object-level rule must be able to match "a ray with some polarity"
generically. This is exactly the shape-checker requirement that decided
evaluation doc 5.4 toward option (B), inert internal polarities:
under (B), a reified `(+f X)` stored at depth is matched by equality,
and checkers write the polarities they mean. If (A) (ban internal
polarities) were chosen instead, the encoding would need structural
wrappers like `(%pos (f X))`. Either way the decision belongs to the
encoding contract (plan 2.5.2) and must be made before quote is
designed. Quote is one more client pushing toward (B).

## 7. The expensive half: eval (data becomes execution)

The dual primitive: run an encoded constellation. This is what
user-defined *execution* needs. With both halves, a practice can write a
metacircular executor, an alternative strategy, a step debugger, or a
bounded-run driver as object-level code over encoded stars, with native
`exec` remaining the fast path. A metacircular executor is also
the artifact the theory keeps asking for: the language accounting for
its own execution. With eval, even `forall` becomes derivable in
principle (iterate the encoded galaxy at the object level, judging each
member in its own reflected space).

Eval has history: it existed and was removed on 2025-11-16 (commit
`3025e62`), correctly, for kernel purity. Evaluation doc 5.2 and plan
2.5.2 both say: keep it out until a concrete need arrives, then
reintroduce deliberately with a written staging and trust story. This
note does not overturn that; it names the likely first client (a
strategy or tactic practice) and records that when eval returns, it
returns as the second half of a reflection pair, not as a convenience.
It enlarges the trusted surface more than quote does (the evaluator
becomes invocable from inside programs), which is why the two halves are
staged rather than shipped together.

If Maude's history is a guide, pure reflection eventually gets verbose
and users want a small strategy DSL. Fine, but by then the DSL can be
defined by translation to reflection: derived and inspectable, not
kernel.

## 8. Fuel: the one native addition reflection cannot replace

A step bound on `exec` must be native, because divergence is a
property of the native engine and no object-level code can observe
"did not terminate within n steps" from outside. Fuel is a second
honest axis next to the `*` linearity modality, and it is what makes
negative tests and tooling divergence-safe. It also composes with quote: "run bounded,
reify, inspect the partial result" is the step-debugging story without
any debugger machinery.

## 9. Deliberately not proposed

- **A meta-level programming language** (way 2): values, conditionals,
  loops, functions in the glue. Duplicates the object level and changes
  the project's identity.
- **Judgment combinators / boolean assertions**: installs a logic in the
  kernel of a logic-agnostic language (section 3). Rich judgments are
  object-level interactions judged by `==`, and with quote that covers
  negation and beyond.
- **Full computational reflection** (self-modifying constellations,
  fexpr-style tricks): stays out regardless, as evaluation doc 5.2
  already records.
- **New observation forms case by case** (way 1): superseded by quote.
  In particular the census's candidate `=/=` assertion is withdrawn;
  quote plus `!=` bans covers it.

## 10. Actions, in order

1. **Decide the internal-polarity question** (evaluation doc 5.4;
   recommendation (B) stands, quote adds a client). Gates the encoding
   contract (plan 2.5.2), which gates everything below.
2. **Sharpen the KERNEL.md entries** for `~=` (state the existential
   semantics or revise it) and `forall` (justify as the galaxy
   eliminator whose content is separation). Pure documentation.
3. **Design and implement quote** (result reification into the
   %-encoding). Small language work once the encoding contract is fixed.
4. **Fuel axis** on the execution operation. Small language work.
5. **Eval**, when a strategy or tactic practice actually wants it, with
   the staging and trust story written first (per plan 2.5.2). Not
   before.

Items 1 and 2 are unconditionally good. Item 3 is the pivot: it is small
and it changes the trust story of the whole observation stratum. Items 4
and 5 land with their first real clients.
