# The Stellogen Kernel

This document is the kernel specification: an exhaustive list of every
form the language accepts, with its exact semantics.

**Normativity.** The specification is written in language-level terms
only; the implementation conforms to it, not the other way around. Where
the implementation and this document disagree, one of them has a bug.

The kernel rule: **if a feature can be defined as a macro, it must not be
in the kernel; if it cannot and is not essential, it does not belong in
the language.**

The kernel has two parts with deliberately different semantics:

- The **object kernel** (part I): stellar resolution proper. Terms, rays,
  stars, constellations, the reactive/catalyst distinction, ground
  guards, constraints, and the fusion dynamics. Unordered, interactive,
  possibly non-terminating. Anything that computes lives here.
- The **meta kernel** (part II): the functional glue that assembles
  constellations, runs them, and compares the results. Deterministic and
  ordered. It never computes anything itself.

The sorting rule between them: **anything that computes belongs in the
object language; a meta construct must justify itself as glue (assemble,
run, compare).**

Everything above these two layers (notation macros, checkers, logics,
type disciplines) is user space, written in ordinary `.sg` files.
`sgen preprocess` is the witness: run it on any file and what remains is
kernel forms only.

Part III specifies the code-as-term encoding, the contract for checkers
that inspect code as data. Part IV specifies the base observations and
the judgment contract.

---

## Part I: the object kernel

### 1.1 Terms

Lexical rules:

- A token starting with an uppercase letter or `_` is a **variable**
  (`X`, `Result`, `_Tail`). The bare token `_` is a wildcard: each
  occurrence stands for a fresh variable.
- A token starting with `!` followed immediately by an uppercase letter
  or `_` is a **guarded variable** (`!X`, `!_Tail`): the same variable,
  wrapped with a ground guard (1.4).
- Any other token is a **symbol** (`a`, `bob`, `0`, `s`, `+add`, `%cons`).
  Symbols may contain any characters except whitespace, the delimiters
  `( ) [ ] { }`, `|` and `;`; they may not start with `'`, `"`, `@` or `#`.
  `@` is not otherwise a valid character anywhere in the source: it is
  simply not lexed, so any occurrence is a lexer error.
- `; ...` is a line comment. There are no block comments; stack `;` lines.
- `"chars"` is a string literal with escapes `\n \t \\ \"`.

Grammar of terms:

```
term ::= VAR                    variable, local to its star
       | !VAR                   sugar: guarded variable (1.4)
       | sym                    constant (0-ary function)
       | (sym term ...)         function application
       | [term ...]             sugar: cons list (%cons/%nil, see part III)
       | [term ... | term]      sugar: cons list with explicit tail
       | "chars"                sugar: (%string chars)
```

The head of an application must be a symbol; a variable in head position
is an error, as is the empty application `()`.

### 1.2 Rays and polarity

A symbol whose first character is `+` or `-` is a **polarized** symbol;
the polarity is not part of the name, so `+add`, `-add` and `add` share
the name `add` with polarities positive, negative, neutral.

A **ray** is a term used as an interaction point of a star. Two function
symbols are **compatible** when they have the same name and dual
polarities (`+`/`-`), or are both neutral. Two rays can fuse when they are
unifiable under this compatibility relation, both are polarized, and both
are **eligible** (1.4).

Precisely:

1. **Duality applies pointwise at every depth.** Unification descends
   through subterms with the same compatibility test, so `(+f (+g a))`
   unifies with `(-f (-g a))`, not with `(-f (+g a))`. Polarized symbols
   inside arguments must also invert.
2. **A ray is polarized when a polarized symbol occurs anywhere in it**,
   at any depth. A neutral-headed ray with a polarized subterm is
   therefore eligible for fusion (modulo 1.4).
3. **Guards are erased before unification.** A guarded variable `!X`
   unifies exactly as `X` would; guards restrict *when* a ray may fuse,
   never *what* it may fuse with.

### 1.3 Stars and constraints

A **star** is a finite block of rays, optionally with constraints:

```
star ::= ray
       | [ray ...]
       | [ray ... || ban ...]

ban  ::= (!= term term)         inequality
       | (slice term term)      incompatibility
```

Variables are **local to each star**. Before each fusion the two stars are
renamed apart, so no variable is ever shared between two stars.

Constraints restrict fusion. After a fusion, the merged star's constraints
are checked for coherence; an incoherent fusion is discarded, producing no
star:

- `(!= t1 t2)` is violated when the two terms have become syntactically
  equal.
- `(slice box s)` is violated when two `slice` constraints share an equal
  first component but differ on the second. It forces all `slice`
  assignments to the same box to agree.

### 1.4 Ground guards

A guarded variable `!X` (1.1) marks a position that must be **ground**
(no variables left in it, after every substitution collected so far) before
the ray holding it may take part in a fusion.

- **Erasure.** Guards play no role in unification: fusing a ray strips
  every guard first (1.2.3), so `!X` unifies exactly as `X` would.
- **Eligibility.** A ray is **eligible** exactly when every guarded
  position inside it is ground. A ray with no guards at all is always
  eligible. Eligibility is checked before a ray is offered as a fusion
  candidate, in either role (the reactive ray looking for a partner, or
  the partner ray it is tested against).
- **Inheritance under substitution.** A guard survives the substitution
  that discharges other variables around it: applying `X := (s Y)` to
  `!X` yields `(s !Y)`, moving the guard onto `Y` rather than dropping
  it. Internally this is a `%!` wrapper around the guarded subterm, so
  `!X` under that substitution really is `(%! (s Y))` reduced to
  `(s (%! Y))` by pushing the wrapper down to the variable.
- **Discharge.** Once a guarded position becomes ground, its guard is
  dropped (simplified away): a wrapper around `(s (s 0))`, once every
  variable under it is solved, reduces to plain `(s (s 0))`, and no
  `%!` wrapper survives into a printed result.

Guards are the kernel's only synchronization device: they say nothing
about what a ray unifies with, only when it is allowed to try.

### 1.5 Constellations: reactive stars and catalysts

A **constellation** is a finite multiset of stars. Each star carries
exactly one of two marks, which decides its role in execution (1.6):

```
cell  ::= star | *star
const ::= cell | { cell ... } | *{ cell ... }
```

- An unmarked star is **reactive**: it exists once, is a candidate to
  fuse (with another reactive star, with a catalyst, or with itself),
  and is consumed the moment one of its rays reacts.
- A star marked `*` is a **catalyst**: reusable (a fresh renamed copy is
  produced for every fusion it takes part in), passive (it never
  initiates a search for a partner; a reactive ray must come looking for
  it), inert toward other catalysts (two catalysts never fuse with each
  other), and dropped from the result once execution ends.

`*` on a group marks every star inside a catalyst, hereditarily: it
distributes through `{...}` and is idempotent. There is no mark for
"reactive" beyond the absence of `*`, since reactive is the default for
every star.

Constellations are unordered as far as the semantics is concerned; the
implementation keeps them in some order, and observable orderings
(printing, `==`) reflect that order without it being part of the
specification. See section 4.1.

### 1.6 Execution

Execution is **one operation**: saturation of a soup of stars under a
single fusion rule. There is a single top-level form, `exec`; whether a
star is reactive or a catalyst is a per-star tag, not a mode of the call,
and staging is not a variant at all:

- **The fusion rule.** A reactive ray may fuse with any dual, unifiable,
  eligible (1.4) ray, wherever that ray is found: in another reactive
  star, in a catalyst, or in the very same star (an **internal cut**: two
  dual rays of one star cancelling each other, with no renaming since
  they already share the star's scope). A fusion consumes the matched
  pair of rays, applies the resulting substitution to what remains of
  both stars, and merges the remainder into one new star, exactly as in
  1.3's fusion mechanics; an incoherent result (1.3) is discarded.
- **Consumption by role.** A reactive star involved in a fusion is
  consumed by it (used once, gone). A catalyst involved in a fusion is
  not consumed: the specific copy that fused is spent, but the catalyst
  itself remains available, ready to be copied again for the next
  fusion that solicits it.
- **No weakening on reactive stars.** A reactive star that saturation
  never gets to react stays in the result untouched. Nothing is silently
  discarded except catalysts, which are dropped from the result
  precisely because they were never part of the reactive material being
  computed.
- **Branching.** If a reactive ray has several dual eligible partners at
  once (several matches across reactive stars and catalysts combined),
  execution does not pick one arbitrarily: it fuses with **all** of them
  in the same step, producing one new star per partner. All of these new
  stars join the single continuing multiset side by side (this is not a
  fork into separate parallel results: there is still exactly one
  ongoing constellation). Every reactive partner that matched is
  consumed, alongside the source star; every catalyst that matched
  persists, since a catalyst is never exhausted by being used.

Operationally, execution proceeds as follows:

1. Split the input constellation into catalysts and reactive stars by
   their mark.
2. Look for an internal cut first: a reactive star with two dual,
   unifiable, eligible rays of its own. If several reactive stars have
   one, the first one found (implementation order, not specified) has
   that one star replaced by its cancellation (or, per the branching
   rule, by one cancelled star per internal partner if its chosen ray
   has several).
3. If no internal cut applies, scan the reactive stars for one holding
   an eligible ray that has at least one dual, unifiable, eligible
   partner ray among the *other* reactive stars and the catalysts taken
   together. Perform **all** such fusions for that one ray at once
   (the branching rule above); remove the source reactive star and
   every reactive partner that matched; add every fused star produced.
   Catalysts that matched are never removed by this step.
4. Repeat from step 2 until no reactive star has any eligible ray with
   an internal or external dual partner (saturation). Empty stars are
   dropped. The final reactive stars are the result; catalysts are
   discarded.

The order in which reactive stars and candidate fusions are picked is
implementation-determined and not part of the specification, except that
internal cuts are tried before cross-star fusions (a scheduling choice,
not part of the result's meaning): only the saturation semantics is.

The result of `exec` is re-marked as all-reactive (any `*` tags on the
input are dropped), and is used directly as the next stage's input; there
is no re-focusing step, since focus no longer exists. Staging is
therefore just nesting `exec` calls, with no extra marking (2.2).

Execution may diverge; that is a property of the object language,
accepted, and it requires a catalyst somewhere: a constellation with no
catalysts always terminates, because every fusion strictly consumes two
rays from a fixed, finite, never-duplicated pool of reactive material.
Divergence needs a catalyst repeatedly feeding a computation fresh copies
of itself, for example a recursive rule set marked `*` chased through a
query. Termination guarantees for fragments that do use catalysts are
user-space theorems, not kernel features.

### 1.7 What is not in the object kernel

No numbers or arithmetic, no booleans or conditionals, no strings as
anything but term sugar, no ordering of stars, no notion of function call,
no record system (the fields idiom, a `(+field k) v` star plus a `get`
macro, is a user-space pattern and stays one), no module or scope
construct. Symbols are global addresses: any two constellations sharing a
function symbol with opposite polarities can interact when placed in one
space, and curating interaction spaces is the user's job, done at the meta
level. Hygiene exists only for variables, which are per-star. All of the
above are encodings or user-space conventions.

---

## Part II: the meta kernel

The complete inventory of forms the language accepts. Any expression not
matching a form below is read as a raw term (a single-ray constellation,
or a constellation if it uses the encodings of part III).

| Form | Role | Justification as glue |
|---|---|---|
| `(def name e ...)` | bind | naming things |
| `(def (name p ...) e)` | parametric bind | naming families of things |
| `#name`, `#(name a ...)` | reference | using named things |
| `*e` | catalyst | marking a reusable, passive star (shared with the object kernel) |
| `(exec e ...)` | run | running interactions; each star's own mark decides its role |
| `(show e ...)` | display | observation |
| `(== e1 e2 [msg])` | assert equal | base observation (part IV) |
| `(~= e1 e2 [msg])` | assert unifiable | base observation (part IV) |
| `(forall g X e)` | iterate over a galaxy | the one binder; the forall of orthogonality |
| `(use "path")` | import | files are files |
| `(macro (name X ...) body ...)` | fixed-arity rewrite | the tower's growth mechanism |
| `(spec name e ...)` | bind a specification | like `def` but check-phase only; a fixed-arity macro cannot alias a variadic form |

What is deliberately absent: closures, higher-order functions, arithmetic,
conditionals, general recursion, mutable state, `eval` (term to running
code). The meta language's only data are terms and constellations; its
only verbs are build, run, compare.

### 2.1 `def` and `#`

`(def name e)` binds `name` to the **unevaluated** expression `e`.
References evaluate at use site (call by name): `#x` where `x` is bound to
`(exec ...)` re-runs the execution at every reference.

`(def name e1 e2 ...)` with several values builds a **galaxy**. If every
value is a `{...}` group, each group becomes one galaxy member and each
member is evaluated **eagerly**, at definition time. Otherwise the values
are wrapped into a single group (one member, call by name as above).
Galaxies are the domain of `forall`; in an `exec`, a galaxy flattens into
the union of its members.

Identifiers are rays, so definitions can be parametric:
`(def (pair X Y) ...)` binds the key `(pair X Y)`; the reference
`#(pair a b)` unifies against stored keys and applies the resulting
substitution to the stored expression. Binding a key that unifies with an
existing key replaces that binding.

`(spec ...)` is accepted wherever `def` is and binds identically; it marks
the intent that the defined thing is a test suite. Because a specification
only matters to type checking, a top-level `spec` is classified into the
check phase on its own (as if it carried a `§`), so `sgen run` skips it
while `sgen check` evaluates it. It is a kernel form rather than a macro
because `def` is variadic (galaxy formation) and macros are fixed-arity: no
macro can faithfully alias it.

### 2.2 `exec`

`(exec e1 ... en)` evaluates its arguments, combines them into one
constellation (groups and galaxies flatten), and saturates it as in 1.6:
each star reacts or persists as a catalyst according to its own `*` tag.
The result is an all-reactive constellation (1.6), with every `*` tag
from the input gone.

Staging needs no form of its own: `(exec c2 (exec c1 base))` runs `c1`
against `base` and then `c2` against the result, with no refocusing (an
`exec` result is already reactive, so it feeds the next stage as is).
Long chains are usually written as a sequence of named steps, each
`exec`ing against the previous one.

### 2.3 `forall`

`(forall g X e)` evaluates the reference `g`, splits the result into
galaxy members (a non-galaxy value is a singleton), and evaluates `e` once
per member with `X` bound to that member. `X` must be written as a
variable but is bound as an ordinary identifier (so `e` refers to it as
`#X`). Each iteration runs in a local environment; bindings made inside
the body do not escape, and tests run in separate interaction spaces. A
**member** is precisely: one immediate group of a multi-group `def`
(2.1), or the whole value otherwise.

`forall` is kernel, not user space: it iterates over galaxy structure
unknown at macro-expansion time, so no fixed-arity macro can express it.
It is the "for all tests e in E" of orthogonality, which is why checking
macros are built on it.

### 2.4 `show`, `use`

`(show e ...)` evaluates each argument and prints the resulting
constellations, space-separated, in the surface syntax.

`(use "path")` (or `(use sym)`, which appends `.sg`) resolves the path
**relative to the importing file**, parses it, and (a) brings its macros
into scope during preprocessing, (b) evaluates its program into the
current environment, importing definitions. One form imports both;
circular imports are detected and rejected.

### 2.5 `macro`

`(macro (name X1 ... Xn) body ...)` defines a rewrite with **fixed
arity**. Arguments must be variables. One name may carry several patterns
of different arities; a call expands the pattern whose arity matches
exactly. Expansion order: arguments are expanded first, substituted into
the body, and the result is expanded again. Macros expand before
kernel-form recognition, so a macro whose head and arity collide with a
kernel form shadows it; do not do this.

There are no variadic patterns and no computation in patterns; the macro
layer is spelling, not evaluation. Expansion terminates if and only if
macro references are acyclic: a macro whose expansion mentions itself,
directly or mutually, makes preprocessing diverge. Acyclicity is an
obligation on the user; under it the meta language is total, and every
file's elaboration halts (only object-level interaction may diverge).

---

## Part III: the code-as-term encoding

Every surface expression is a first-order term; this section makes the
encoding a **contract**. Shape checkers unify against these shapes, so the
encoding must stay stable; changing it is a breaking change to every
checker in user space.

The `%`-prefixed names below, plus `*`, `#`, `!=` and `slice` in encoded
positions, are reserved for the encoding.

### 3.1 Surface syntax to terms (read time)

```
[a b c]            -> (%cons a (%cons b (%cons c %nil)))     lists
[h | t]            -> (%cons h t)
"chars"            -> (%string chars)
{e1 ... en}        -> (%group e1' ... en')                   groups
[r1 ... || b ...]  -> (%params RAYLIST BANLIST)              star with bans
                      RAYLIST a %cons list of rays; BANLIST a %cons list
                      of ("!=" t1 t2) / ("slice" t1 t2) terms
#e                 -> ("#" e')                               reference marker
*e                 -> ("*" e')                               catalyst marker
!X                 -> ("%!" X)                               ground guard (1.4)
(f a ...)          -> (f a' ...)                             applications are themselves
```

Every surface form embeds in term position: `*`, `#`, `!X` and `{...}`
occurring inside a term become plain `"*"`-, `"#"`-, `"%!"`- and
`%group`-headed subterms.
This is what lets a macro splice one body into both code position and term
position; no `quote` primitive is needed, and a `quote` notation, if ever
added, is a user-space no-op marker over this encoding.

### 3.2 Constellations to terms (run time)

Evaluation results are terms in the same vocabulary, and the language
reads them back by the same rules:

```
reactive star [r1 ... rn] -> (%cons r1 (... (%cons rn %nil)))
star with bans            -> (%params RAYLIST BANLIST)
  ban (!= t1 t2)          -> ("!=" t1 t2), in a %cons list
  ban (slice t1 t2)       -> ("slice" t1 t2), in a %cons list
catalyst star             -> ("*" STAR)
constellation, one star   -> STAR              (not wrapped)
constellation, n stars    -> (%group S1 ... Sn)
galaxy                    -> (%galaxy T1 ... Tn)
```

Reading back: `%galaxy` and `%group` flatten and concatenate; `"*"`
forces every star it wraps to be a catalyst. A `%cons` list of rays is a
reactive star; any other term is a single-ray reactive star. Ray
polarities ride inside these terms as ordinary polarized symbols. A
guarded position inside a ray survives as a `"%!"`-headed subterm
wherever it occurs, at any depth (1.4); it is not a property of the star
or the ray as a whole, only of the specific position it wraps.

---

## Part IV: base observations and the judgment contract

Typing in Stellogen is user-defined: a checking macro is a practice
declaring its orthogonality relation. Trust cannot be tests all the way
down, so the kernel fixes exactly two **base observations**, plus the
binder `forall` (2.3). They are the only trusted judges; everything else
is spelling above them.

### 4.1 `==` : syntactic equality of results

`(== e1 e2)` evaluates both sides, converts both to constellations, strips
the reactive/catalyst mark off every star, and compares **syntactically**:
same stars with the same rays and the same constraints, in the same
order, with the same variable names. No unification, no reordering, no
renaming. Consequences: `==` does not care whether a star was reactive or
a catalyst; it is order-sensitive, so it compares the order the
implementation produced (fix the expected constellation from an actual
run, or compare single-star results); it is name-sensitive on variables;
and it does not strip ground guards, so a `!X` still present in a result
must be matched by a `!X` in the expected side.

On failure the program aborts, reporting both sides and the source
location. An optional third argument replaces the default message.

### 4.2 `~=` : polarity-blind structural unifiability

`(~= e1 e2)` evaluates both sides and succeeds when **some ray of the
first unifies with some ray of the second after all polarities and all
ground guards are stripped away**. Polarity is ignored at every depth:
`(~= (+f X) (+f a))` succeeds. Guards are ignored the same way unification
already ignores them for fusion (1.2.3): `(~= (-f !X) (-f a))` succeeds
just as `(~= (-f X) (-f a))` would. The check is existential over rays,
not a matching of whole constellations. Failure aborts with a report of
both sides; optional third argument as above.

### 4.3 The judgment contract

**A checking macro must expand to assertions**, that is, bottom out in
`==` or `~=` (usually under `forall`). Assertions are the only way
anything reports pass or fail, so generic tooling counts failures
identically across all practices, whatever their success conventions:
an `ok` residue, annihilation (empty residue), witness shapes, or exact
consumption checked by leaving everything markless. A typical practice
defines its type assertion as

```stellogen
(macro (:: Tested Test)
  (forall Test T
    (== (exec #Tested *#T) ok)))
```

with `Tested` reactive and `Test` a catalyst, so each test is consulted
without being consumed by the interaction. A stricter practice can demand
exact consumption instead, by leaving both sides markless:

```stellogen
(macro (::lin Tested Test)
  (forall Test T
    (== (exec #Tested #T) ok)))
```

and this is user space, not a kernel form: each practice declares its own
orthogonality relation this way, and all of them rest on the same two
trusted observations.
