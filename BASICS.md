# Learn Stellogen

Stellogen is an experimental, logic-agnostic programming language built on
**term unification**. Instead of types or fixed logic, programs and meaning are
expressed with the same raw material.

This guide walks you through the basics.

---

## Let's start!

Follow the install instructions in the README file of the repository.

Open your favorite text editor and create a file `test.sg`. You can evaluate
your file with `sgen eval test.sg`.

Check that everything works fine by writing and running the following program:

```
(show "Hello, world")
```

It displays `(%string Hello, world)`. Do not worry about the shape of the
output: in Stellogen even strings are terms, and `show` displays the term
hidden behind the double quotes notation.

## Show

The `show` command is used to display an expression on the screen. It will be
useful through this whole guide.

---

## Comments

You can add comments to explain what your program does or to make it more
readable. A comment starts with `;` and runs to the end of the line. For
longer comments, stack several lines.

```stellogen
; single line

; a longer comment
; written on
; several lines
```

## Everything is a term!

In stellogen **everything** is a term.

A **term** is either:

* A variable: starts with uppercase (`X`, `Y`, `Var`).
* A function: a sequence of symbols surrounded by parentheses, beginning with a
  lowercase or special symbol, followed by terms:

```
; this program does nothing but you can check the validity of expressions
(f a X)
(:: x t)

; several terms can be on the same line
(add 2 2) (fact 3)
```

In the special case of constants (function without argument) we can omit
parentheses:

```
a
$
a $ :b c
```

## Rays and compatibility

**Unification** = finding substitutions that make two terms identical.

You can check if two terms are matchable with the term `(~= t u)` where `t` and
`u` are terms.

For example:

```stellogen
(~= (f X)  (f (h a)))    ; they match with {X := (h a)}
; (~= (f X)  X)          ' ❌ fails with an error (circular)
; (~= (f X)  (g X))      ' ❌ fails with an error (different head symbol)
```

Note that `~=` checks *structural* unifiability and ignores polarity:
`(~= (+f X) (+f a))` succeeds even though two positive rays cannot interact.

A **ray** is a term with polarity:

* `(+f X)` → positive
* `(-f X)` → negative
* `(f X)`  → neutral (does not interact)

Two rays are **compatible** and can interact if they have opposite polarities
**and** their terms unify.

```stellogen
; (+f X) and (-f (h a))  are compatible with {X := (h a)}
; (+f X) and (+f a)      are incompatible because they have same head polarity
```

---

## Definitions and calls

Our most useful term will be definitions written `(def x t)` where `x` is the
name associated to the definition and `t` is a term. For example:

```stellogen
(def a (+f X))
```

You can invoke a definition by prefixing a name with `#`:

```stellogen
(show #a)
```

---

## Syntactic sugar

There are shorthands to build complex but useful terms.

### Cons lists

Square brackets inside a term build a list:

```stellogen
(show (list [a b c]))  ; [a b c] means (%cons a (%cons b (%cons c %nil))), a list containing a, b and c
(show (list []))       ; [] means %nil, the empty list
```

Beware: brackets are resolved by position. Inside a term they build a list,
but at the top level of a constellation they build a star (see below).

### Groups

```stellogen
(show { a b c })  ; means (%group a b c)
(show {})         ; means (%group), the empty group
```

---

## Make terms interact with Stars and Constellations

Stars and constellations are special terms which can interact with each other.

* A **star** is a block of rays:

```stellogen
[(+f X) (-f (h a)) (+g Y)]
```

Square brackets can be omitted when there is a single ray.

* A **constellation** is a group of stars:

```stellogen
{ (+f X) [(-f X) (+g a)] }
```

Variables are local to each star. So, in the above example, the `X` in `(+f X)`
and the one in `[(-f X) (+g a)]` are two distinct variables.

## Principles of Star Fusion

The idea of **fusion** is that stars can collide along compatible rays and merge.

When rays of two stars unify:

* They disappear (consumed).
* Their substitution applies to their neighbors rays.
* Their stars merge.

Example of interaction:

```stellogen
; star 1: [(+f X) X]
; star 2: (-f a)
;
; ' connexion
; (-f a) ------ (+f X) X
;
; ' annihilation and merge with resolution {X:=a}
; X
;
; ' propagation
; a         ' <-- this is the result of execution
```

Note: this corresponds to the so-called Robinson's resolution rule in formal
logic.

## Reactive Stars and Catalysts

Execution needs to know which stars are the "stuff" being computed and
which are reusable rules. Every star is one of two things:

* An **unmarked star is reactive**: it exists once, and it is consumed as
  soon as it reacts (fuses along one of its rays). Reactive stars interact
  freely with each other, and even with themselves: if one star holds two
  dual rays that unify, they cancel on the spot (an **internal cut**).
  Whatever reactive stars are left when nothing more can react is the
  result. A reactive star that never gets a chance to react simply stays
  in the result untouched: there is no silent discarding.
* A star prefixed with `*` is a **catalyst**: reusable (a fresh copy is
  made every time it is used), passive (it only reacts when a reactive
  ray comes looking for it, never on its own initiative or against
  another catalyst), and dropped from the result once execution ends.

```stellogen
(def d { [+a b] *[-c d] })  ; +a b is reactive, -c d is a catalyst
```

**Intuition:** think of catalysts as rules/data you look up as needed, and
reactive stars as the actual computation happening, consumed as it goes.

You can mark every star of a constellation a catalyst at once with `*`:

```stellogen
(def f *{ [a] [b] [c] })
```

There is no equivalent marker for reactive, because reactive is what a
star is by default; a bare `{ ... }` is already all-reactive.

## Ground Guards

A variable occurrence written `!X` instead of `X` is a **ground guard**:
the ray it appears in cannot take part in any fusion until that position
becomes ground (fully instantiated, no variables left). The guard rides
along with substitution: if `X` gets bound to `(s Y)`, the guard moves to
`Y`, so `!X` becomes `(s !Y)`. Once the guarded position is ground the
guard is silently discharged and disappears from the result.

```stellogen
; (-table !X R) will not try to interact until X is a value
(def guarded (exec
  {[(-val X) (-table !X R) (out R)]
   [(+val 5)]}
  *[(+table 5 found)]))
(show #guarded)  ; (out found)
```

This is handy whenever you want a ray to behave like a function waiting
for its argument instead of a relation that could just as well run
backwards, for example a circuit gate that should only fire once its
inputs are known values (see `examples/circuits.sg`).

## Execution of Constellations

Execution is **one fusion rule** applied over and over: a reactive ray may
fuse with any dual, unifiable, eligible ray, whether that partner sits in
another reactive star, in a catalyst, or (the internal cut) in the very
same star. Each fusion consumes the two rays that matched, applies the
resulting substitution to what is left of both stars, and merges them
into one new star; a reactive partner is consumed by the fusion, a
catalyst is not (it stays around, ready to be copied again). If a ray has
several possible dual partners at once, execution branches: it tries all
of them, producing one result star per partner (the reactive stars
actually involved are consumed in each branch; catalysts persist in all of
them).

Execution keeps going until no more fusions are possible (saturation).
What is left is the result. Because every fusion strictly consumes two
rays and reactive stars are never duplicated, a constellation with no
catalysts always terminates: there is only a finite, shrinking amount of
reactive material to consume. Divergence needs a catalyst that keeps
feeding a computation new copies of itself, for example a recursive rule
set marked `*` chased by a query.

**Let's execute constellations!**

```stellogen
(def x [(+f X) X])
(def y (-f a))

(def res1 (exec #x #y))   ; both reactive: consumed by their fusion
(show #res1)

(def res2 (exec #x *#y))  ; y is a catalyst: reusable, dropped from the result
(show #res2)
```

Both print `a`: with only one interaction available it does not matter
here whether `y` was reactive or a catalyst, but it would if `y` were
needed more than once (or not needed at all, in which case a reactive `y`
would linger in the result while a catalyst `y` would simply vanish).

You can watch fusion happen step by step with `sgen trace test.sg`. It is a
precious tool to understand what happens during an execution.

---

## Inequality Constraints

Add constraints with `[ some star || (!= X1 Y1) ... (!= Xn Yn)]`:

```stellogen
(def ineq {
  [(+f a)]
  [(+f b)]
  [(-f X) (-f Y) (r X Y) || (!= X Y)]})
(show (exec #ineq))
; => { [(r a b) || (!= a b)] [(r b a) || (!= b a)] }
```

where several equality constraints can be chained after `||`.

This prevents `X` and `Y` from unifying to the same concrete value.

---

## Relational Programming

Constellations can act like relational databases: facts are positive rays and
a query is a star with negative rays. Facts (and rules) are usually marked
`*`, as catalysts: the query looks them up as many times as it needs, and
whichever facts it doesn't touch do not linger in the result.

### Facts

```stellogen
(def edges *{
  [(+edge a b)]
  [(+edge b c)]
})
```

### Query

A query asks for all values matching a pattern:

```stellogen
(show (exec #edges [(-edge a X) (res X)]))
; => (res b)
```

### Rules

A rule is a single star with a positive conclusion and negative premises:

```stellogen
(def hop *[(-edge X Y) (-edge Y Z) (+hop X Z)])
```

It reads: if there is an edge from `X` to `Y` and an edge from `Y` to `Z`,
then there is a hop from `X` to `Z`. Beware: since variables are local to
each star, a rule must be one star, otherwise its premises cannot share
variables with its conclusion. A rule is normally a catalyst too, so it
can be reused for every hop the query asks for.

### Putting it together

```stellogen
(def edges *{
  [(+edge a b)]
  [(+edge b c)]
})

(def hop *[(-edge X Y) (-edge Y Z) (+hop X Z)])

(show (exec { #edges #hop } [(-hop a Z) (res Z)]))
; => (res c)
```

This asks: *where can we go from `a` in exactly two steps?*

Note that execution computes all answers at once by saturation. There is no
clause order, no search and no backtracking.

---

## Expect assertion

This is a more strict version of the matching `~=` term which expects
syntactic equality.

```stellogen
(== a a)    ; does nothing
; (== a b)  ' fails with an error
```

---

## Advanced syntax manipulation

### Parametric definitions

Definitions are actually terms like others so they can be *parametric*:

```stellogen
(def (initial Q) [(-i W) (+a W Q)])
```

In this case, calling

```stellogen
#(initial q0)
```

will replace `Q` by `q0` in `[(-i W) (+a W Q)]` so we get

```stellogen
[(-i W) (+a W q0)]
```

### Macros

**Macros** work like definitions except that are applied before actual
execution in a preprocessing phase:

```stellogen
; replace (assert X Y) by (== X Y) everywhere in the code
(macro (assert X Y) (== X Y))
(assert a a)
```

Notice that they do not involve any call with `#`, they replace terms.

You can display your code after macro expansion with `sgen preprocess test.sg`
to check what your macros actually do.

### Nested phantom constellations

Some terms like `def`, `show` or `==` are not interactive terms which can
be executed as constellations but they have an effect on the environment.

In fact, they can occur anywhere in the code and produce an effect when
evaluated but they are considered like empty constellations `{}`.

For example:

```stellogen
(exec [(+f X) X] (-f a) (def x hello1))
(show #x)
(def y (show hello2))
#y
```

---

## File import

It is possible to import the content of a file through their relative path:

```stellogen
(use "filename")
```

This imports both the definitions and the macros of the file. Paths are
resolved relative to the importing file.

---

## Types as Sets of Tests

In Stellogen, **types are sets of tests** that a constellation must pass to be
of that type.

For example, we define a type for natural numbers which is simply a
constellation corresponding to a "test". We use `spec` instead of `def`: it
binds a name just like `def`, but marks the intent that the definition is a
specification. Because a specification only matters to type checking, a
top-level `spec` lives in the check phase on its own (see below), so
`sgen run` skips it:

```stellogen
(spec nat {
  [(-nat 0) ok]
  [(-nat (s N)) (+nat N)]})
```

A constellation must pass **all tests** to be considered of type `nat`.

We then define the behavior of type assertions with a macro:

```stellogen
(macro (:: Tested Test) (== (exec #Tested *#Test) ok))
```

It says that a `Tested` is of type `Test` when their interaction, with
`Tested` reactive and `Test` a catalyst, is equal to `ok`.

```stellogen
; passes the test
(def two (+nat (s (s 0))))
(:: two nat)

; does not pass the test
(def bad (+nat foo))
; (:: bad nat)
```

Notice that a constellation can have several types providing it passes all
the tests of those types.

---

## Phase Separation: check and run

Since typing is user-side, a Stellogen file is really two superposed
programs: a layer that typechecks and a layer that actually runs. Every
top-level expression belongs to exactly one of three kinds:

| kind | `sgen check` (phase 1) | `sgen run` (phase 2) |
|---|---|---|
| `(object x ...)` shared definition | visible | visible |
| `(spec x ...)` specification | evaluated | skipped |
| `§X` where X is any expression | evaluated | skipped |
| unmarked expression | skipped | evaluated |

`§` moves a top-level expression to the check phase, whatever it is: a
`§(== ...)` is a check-phase assertion. `spec` needs no `§`: a
specification is a test suite, so a top-level `(spec ...)` already lives in
the check phase (`§` on it is redundant). `def` is phase-neutral, its phase
coming from `§`; `object` is shared between both phases.

```stellogen
(object add {
  [(+add 0 Y Y)]
  [(-add X Y Z) (+add (s X) Y (s Z))]})

; check phase: types and assertions, skipped by sgen run
(spec nat {
  [(-nat 0) ok]
  [(-nat (s N)) (+nat N)]})
§(== (exec *#add [(-add (s 0) (s 0) R) R]) (s (s 0)))

; run phase: the shipped program
(show (exec *#add [(-add (s (s 0)) (s (s 0)) R) R]))
```

Each phase resolves `#name` calls against its own definitions plus the
shared objects; referencing a name defined in the other phase is reported
as such.

The prelude's `::` macro hides a `§` in its expansion, so every type
assertion written with it automatically lives in the check phase. A check
goes right after the definition it checks.

`sgen eval` evaluates both phases in order, the check phase first and the
run phase only if it passed. That is how a Stellogen program is normally
invoked: a checked program, checks included.

The two phases are also available separately. `sgen run` skips every
check and pays nothing for them, so nothing at runtime verifies that
checking ever happened; if you ship that way, `sgen check` must pass
first (e.g. as a CI gate).

Imports (`use`) are executed by both phases and the imported file's items
classify themselves; `§(use ...)` imports only in the check phase. Macros
are phase-less: they are expanded before phases exist.
