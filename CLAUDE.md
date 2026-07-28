# Stellogen - Project Guide for Claude Code

## Overview

Stellogen is an experimental, **logic-agnostic** programming language based on **term unification**. It explores a radically different approach to programming where both computation and meaning are built from the same raw material, without primitive types or fixed logical rules imposed from above.

**Status:** Research project / proof of concept / esoteric language (not production-ready)

## Core Philosophy

Unlike traditional typed languages where types constrain and shape program design, Stellogen offers elementary interactive building blocks where computation and meaning coexist in the same language. The compiler/interpreter's role is reduced to checking that blocks connect - semantic power and responsibility belong entirely to the user.

## How Stellogen Works - Essential Mechanics

### 1. Terms - Everything is a Term
A **term** is either:
- **Variable**: Starts with uppercase (e.g., `X`, `Y`, `Result`)
  - Variables are local to each star
- **Function**: Lowercase/special symbol start with arguments in parentheses
  - Examples: `(f X)`, `(add X Y)`, `(s (s 0))`
  - Constants (0-arg functions) can omit parentheses: `a`, `bob`, `0`

### 2. Unification - The Foundation
**Unification** = finding substitutions that make two terms identical
- `(f X)` ~ `(f (h a))` ⇒ succeeds with `{X := (h a)}`
- `(f X)` ~ `X` ⇒ fails (circular)
- `(f X)` ~ `(g X)` ⇒ fails (different head symbols)

### 3. Rays - Terms with Polarity
A **ray** is a term with polarity:
- `(+f X)` → **positive** polarity (provides/offers)
- `(-f X)` → **negative** polarity (requests/demands)
- `(f X)` → **neutral** (does not interact)

**Compatibility**: Two rays can interact if:
1. They have **opposite polarities** (+/-)
2. Their terms **unify**

Example: `(+f X)` and `(-f (h a))` are compatible → unify with `{X := (h a)}`

### 4. Stars - Blocks of Rays
A **star** is a block of rays in square brackets:
```stellogen
[(+f X) (-g Y) (result X Y)]  ; A star with 3 rays
(+f X)                         ; Single ray (brackets optional)
```

**Important**: Variables are **local to each star** - different stars have separate variable scopes.

### 5. Constellations - Groups of Stars
A **constellation** is a group of stars in curly braces:
```stellogen
{
  [(+add 0 Y Y)]
  [(-add X Y Z) (+add (s X) Y (s Z))]
}
```

Constellations are **unordered sets** - the order doesn't matter.

### 6. Reactive Stars and Catalysts (CRITICAL)
**This is essential for execution to work!**

Every star is one of two things:
- **Reactive** (unmarked): exists once, consumed the moment it fuses.
  Reactive stars interact freely, with each other and even with
  themselves (two dual rays of one star can cancel: an "internal cut").
  Whatever reactive stars are left when nothing more can react is the
  result; an untouched reactive star simply stays in the result.
- **Catalyst** (marked with `*`): reusable (a fresh copy is made every
  time it is used), passive (it only reacts when a reactive ray comes
  looking for it), inert toward other catalysts, and dropped from the
  result once execution ends.

```stellogen
{
  *[(+add 0 Y Y)]              ; Catalyst (reusable rule)
  [(-add 2 2 R) R]             ; Reactive (the query, part of the result)
}
```

**Intuition**:
- No mark means **what you're computing**: the data/query, consumed as it reacts
- `*` means **how you compute**: rules and facts, looked up as needed and never consumed

You can mark an entire constellation a catalyst: `*{...}` makes every star inside one.

### 7. Star Fusion - How Execution Works
**Fusion** = stars colliding along compatible rays and merging

When two stars have compatible rays (opposite polarity + unifiable):
1. The compatible rays **disappear** (consumed)
2. Their **substitution applies** to neighboring rays
3. The two stars **merge** into one

Example:
```stellogen
Star 1: [(+f X) X]
Star 2: [(-f a)]

Step 1: (+f X) and (-f a) are compatible
Step 2: Unify with {X := a}
Step 3: Rays disappear, substitution propagates
Result: [a]  ; The merged star
```

This is **Robinson's resolution** from formal logic!

### 8. Execution - exec, reactive stars, and catalysts
**Execution** = stars interacting through fusion until no more interactions possible

```stellogen
(def x [(+f X) X])
(def y (-f a))

(exec #x #y)    ; both reactive: consumed by their fusion
(exec #x *#y)   ; y is a catalyst: reusable, dropped from the result
```

**Execution process**:
1. A reactive ray may fuse with any dual, unifiable, eligible ray:
   another reactive star, a catalyst, or (an **internal cut**) a dual ray
   of its own star
2. Catalysts are **duplicated** as needed (never with each other) and
   dropped from the result; reactive stars are consumed when they react
   and simply remain in the result when they never get the chance
   (no weakening)
3. If a ray has several possible partners, execution branches: it fuses
   with all of them at once, producing one new star per partner
4. Continue until **saturation** (no more possible interactions)
5. Result is a new, all-reactive constellation

**Termination**: every fusion consumes two rays from a fixed pool, so a
constellation with no catalysts always terminates. Divergence needs a
catalyst that keeps feeding a computation fresh copies of itself, like a
recursive rule set marked `*` chased by a query.

### 9. Ground Guards
A variable occurrence written `!X` instead of `X` is a **ground guard**:
the ray it belongs to cannot take part in any fusion until that position
is fully instantiated (no variables left). The guard survives
substitution by inheritance (`!X` under `X := (s Y)` becomes `(s !Y)`),
and once the guarded position is ground the guard is silently discharged.

```stellogen
; (-table !X R) will not try to interact until X is a value
(def guarded (exec
  {[(-val X) (-table !X R) (out R)]
   [(+val 5)]}
  *[(+table 5 found)]))
(show #guarded)  ; (out found)
```

Use this when a ray should behave like a function waiting for its
argument rather than a relation that could run backwards, for example a
circuit gate that should only fire once its inputs are known
(`examples/circuits.sg`).

### 10. Staged Execution
Pipelines are just nested `exec`: an `exec` result is already reactive,
so it feeds the next stage as is (no refocusing).
```stellogen
(def c (exec
  [(-n1 X) (+n2 (s X))]      ; last stage
  (exec
    [(-n0 X) (+n1 (s X))]    ; first stage
    (+n0 0))))               ; base constellation
(show #c)                    ; (+n2 (s (s 0)))
```
Long pipelines read better as a chain of named steps:
```stellogen
(def s0 (+n0 0))
(def s1 (exec [(-n0 X) (+n1 (s X))] #s0))
(def s2 (exec [(-n1 X) (+n2 (s X))] #s1))
(show #s2)                   ; (+n2 (s (s 0)))
```

### 11. Phase Separation - check vs run (§ and object)
A file is two superposed programs. Every top-level expression belongs to
exactly one of three kinds:

| kind | `sgen check` (phase 1) | `sgen run` (phase 2) |
|---|---|---|
| `(object x ...)` shared definition | visible | visible |
| `(spec x ...)` specification | evaluated | skipped |
| `§X` where X is any expression | evaluated | skipped |
| unmarked expression | skipped | evaluated |

- `§` (section sign) before ANY top-level expression puts it in the
  check phase: `§(def x ...)`, `§(== ...)`, `§(show ...)`. It is a
  lexer token, only legal at top level; nested `§` is a diagnosed error.
- `object` is a keyword (not a sigil): a definition shared by both
  phases - the only thing crossing the boundary. `§(object ...)` is an
  error.
- `spec` is check-only by nature: a specification is a test suite/type,
  so a top-level `(spec ...)` lands in the check phase on its own. `§`
  is therefore redundant on it (`§(spec ...)` still works but the marker
  does nothing).
- `def` is phase-neutral; its phase comes solely from `§`.
  Each phase resolves `#name` calls against its own definitions plus the
  shared objects; referencing a name defined in the other phase is an
  error with a phase-aware message.
- The prelude's `::` macro hides a `§` in its expansion, so type
  assertions live in the check phase; `sgen run` skips them all (that
  skip is the performance point; `sgen check` in CI is what verifies).
- Imports (`use`) run in both phases; the imported file's items
  self-classify. `§(use ...)` imports only in the check phase (library
  definitions meant to be visible must be `object`s). Macros are
  phase-less (expanded before phases exist); `§(macro ...)` is an error.

### 12. Key Operators
- **Definition**: `(def name value)` - bind name to value
- **Spec**: `(spec name value)` - like `def` but check-phase only (marks intent: the thing defined is a test suite/type; no `§` needed)
- **Object**: `(object name value)` - definition shared by both phases (see above)
- **Static marker**: `§expr` - put a top-level expression in the check phase
- **Call**: `#name` - retrieve definition
- **Catalyst**: `*expr` - mark as reusable, passive, dropped from the result
- **Ground guard**: `!X` - a variable occurrence that blocks its ray from fusing until that position is ground
- **Show**: `(show expr)` - display result
- **Expect**: `(== expr1 expr2)` - assert syntactic equality (ignores the reactive/catalyst mark, not guards)
- **Match**: `(~= r1 r2)` - check structural unifiability; polarity AND ground guards are IGNORED (e.g. `(~= (+f X) (+f a))` succeeds)
- **Forall**: `(forall Galaxy X body)` - evaluate `body` once per member of a galaxy, binding each to `X` (used to run every test of a type)
- **Macro**: `(macro pattern expansion)` - syntactic preprocessing; **fixed arity only** (no `...` variadic patterns; a name may have several patterns of different arities)
- **Import**: `(use "path")` imports both definitions and macros. Relative paths resolve **relative to the importing file**, not the working directory.

## Syntax Elements

### Comments
- Single-line: `; comment text` (runs to end of line; stack several `;` lines for longer comments)

### Syntactic Sugar
- **Cons lists**: `[a b c]` in **term position** is `(%cons a (%cons b (%cons c %nil)))`; `[1|Tail]` for head/tail construction
- **Brackets are resolved by position**: `[...]` at constellation level is a **star**; `[...]` inside a term is a **list**
- **Groups**: `{...}` for constellations
- **Stacking**: there is NO `<f a b>` angle-bracket sugar and NO `stack` macro; write nested terms directly: `(s (s 0))`
- **Catalyst**: `*expr` marks a star (or, as `*{...}`, every star of a constellation) a catalyst: reusable, passive, dropped from the result
- **Ground guard**: `!X` marks a variable occurrence: the enclosing ray waits until that position is ground

### Declarations
- **Definition**: `(def name value)`
- **Shared definition**: `(object name value)` - visible in both phases
- **Specification**: `(spec name value)` - check-phase-only definition (no `§` needed)
- **Check-phase item**: `§expr` - any top-level expression
- **Macro**: `(macro (pattern) (expansion))`
- **Show**: `(show expr)` - display result
- **Expect**: `(== expr1 expr2)` - assertion/testing (checks equality)
- **Match**: `(~= c1 c2)` - checks unifiability of constellations (polarity-blind and guard-blind)

### Syntax Reference
**See `examples/syntax.sg`** for comprehensive examples of all syntactic features including:
- Rays, stars, and constellations
- Reactive stars (default) vs catalysts (`*`), and identifiers (`#`)
- Ground guards (`!X`)
- String literals and cons lists
- Inequality constraints (`|| (!= X Y)`)
- Staged execution with nested `exec`
- Fields and field access
- Nested structures
- File imports with `(use "path")`
- Expect (`==`) for equality assertions
- Match (`~=`) for unifiability checks
- Parametric definitions `(def (f a b) ...)` and calls `#(f a b)`
- Phase separation: `§` and `object`

### Type System (Unconventional)
Types are defined as **sets of interactive tests**. Type checking =
interaction between the tested constellation and each test, whose result
is judged by a base observation (`==`).

Simple version (type = ONE test constellation):
```stellogen
; Define nat type as a test constellation
(def nat {
  [(-nat 0) ok]                ; Base case: 0 is a nat
  [(-nat (s N)) (+nat N)]})    ; Recursive: (s N) is nat if N is nat

; Macro for type checking: success = residue is exactly `ok`
; Tested is reactive, Test a catalyst (it is consulted, not consumed)
(macro (:: Tested Test)
  (== (exec #Tested *#Test) ok))

; Use the type
(def two (+nat (s (s 0))))
(:: two nat)  ; Type check passes - interaction yields ok
```

The real prelude (`examples/milkyway/prelude.sg`) is more general: a type
may be a **galaxy** of several tests, and the tested must pass **each test
separately** (in its own interaction space). That is what `forall` is for.
The `§` in the expansion sends every call site to the check phase:
```stellogen
(macro (:: Tested Test)
  §(forall Test T
    (== (exec #Tested *#T) ok)))
```

The success convention is deliberately user-defined: different practices
judge differently (e.g. `examples/proofnets/mll.sg` defines `::lin` with
plain markless `exec`, so both sides must be exactly consumed, instead
of putting the test under `*`). The fixed, trusted part is only the base
observations `==`/`~=`; every checking macro must bottom out in them.

### Common Patterns for Writing Stellogen

#### Pattern 1: Relational/Logic Programming (saturation-style, NOT Prolog)
```stellogen
; Facts (positive rays), as catalysts: looked up, never consumed
(def facts *{
  [(+parent tom bob)]
  [(+parent bob ann)]})

; Rule: POSITIVE head (conclusion), NEGATIVE premises, also a catalyst
(def rules *{
  [(+grandparent X Z) (-parent X Y) (-parent Y Z)]})

; Query (negative ray, reactive by default)
(show (exec { #facts #rules } [(-grandparent tom Z) (result Z)]))
; => (result ann)
```

**Key**: Facts are `+`; rule heads are `+` and rule premises are `-`;
the query is `-` and reactive. A rule head must be positive so the
negative query can fuse with it: a rule written with a negative head
can never answer a negative query. Facts and rules are marked `*`
(catalysts) so the query can consult them without consuming them and any
untouched fact does not linger in the result.

**Warning**: putting a positive premise in a rule (e.g.
`[(+grandparent X Z) (-parent X Y) (+parent Y Z)]`) lets rule copies feed
each other and typically **diverges** under `exec` once the rule is a
catalyst. Keep exactly one positive ray (the conclusion) per rule.

Simple joins don't need a rule at all: put several negative rays in the
query star:
```stellogen
(show (exec #facts [(-parent tom Y) (-parent Y Z) (grandchild Z)]))
; => (grandchild ann)
```

Execution is **saturation** (all consequences at once, Datalog-like), not
Prolog's ordered depth-first search: no clause order, no cut, and failed
branches leave stuck residue stars instead of silently backtracking.

#### Pattern 2: Database Queries
```stellogen
; Database (facts), as a catalyst
(def employees *{
  [(+employee alice engineering)]
  [(+employee bob sales)]})

; Query constellation (reactive by default)
(def query {
  [(-employee Name engineering) (result Name)]})

; Execute
(show (exec #query #employees))
```

**Key**: Mark the database `*` (catalyst) so the query can look facts up
without consuming them and any fact it doesn't touch stays out of the
result.

#### Pattern 3: Recursive Computation
```stellogen
; Addition on natural numbers, as a catalyst since the rule recurses
(def add *{
  [(+add 0 Y Y)]                           ; Base case
  [(-add X Y Z) (+add (s X) Y (s Z))]})    ; Recursive case

; Query
(def query [(-add (s (s 0)) (s (s 0)) R) R])

(show (exec #add #query))
```

**Key**: Mix positive base cases with negative-to-positive recursive
rules, and mark the rule set `*` so each recursive step can reuse it.

#### Pattern 4: Pipelines with Nested exec
```stellogen
(def s0 (+n0 0))                            ; base constellation
(def s1 (exec [(-n0 X) (+n1 (s X))] #s0))   ; step 1: consumes s0
(def s2 (exec [(-n1 X) (+n2 (s X))] #s1))   ; step 2: consumes s1
(show #s2)                                  ; => (+n2 (s (s 0)))
```
Each step is executed against the result of the previous one. Naming the
steps is only for readability: `(exec c2 (exec c1 base))` says the same
thing in one expression, with no refocusing between stages (an `exec`
result is already reactive).

#### Pattern 5: Inequality Constraints
```stellogen
; Find different pairs
(def data {
  [(+item a)]
  [(+item b)]
  [(-item X) (-item Y) (pair X Y) || (!= X Y)]})

(show (exec #data))
```

**Key**: Use `|| (!= X Y)` after star to prevent X and Y from unifying to same value

## Project Structure

```
stellogen/
├── src/                      # OCaml source code
│   ├── core/                 # Fundamental types and algorithms
│   │   ├── unification.ml       # Generic unification algorithm
│   │   ├── constellation.ml     # Rays, stars, constellations (core AST)
│   │   ├── expression.ml        # Expression types and macro expansion
│   │   ├── expression_error.ml  # Expression error types
│   │   └── syntax.ml            # High-level Stellogen AST
│   ├── parsing/              # Lexing, parsing, preprocessing
│   │   ├── parse_error.ml       # Parse error handling
│   │   └── stellogen_parsing.ml # Parser integration and imports
│   ├── eval/                 # Evaluation and execution
│   │   ├── evaluator.ml         # Main expression evaluator
│   │   ├── executor.ml          # Star fusion execution engine
│   │   └── constellation_eval.ml # Constellation evaluation helpers
│   ├── output/               # Display and visualization
│   │   ├── terminal.ml          # Terminal formatting and error display
│   │   ├── pretty.ml            # Pretty-printing for constellations
│   │   └── tracer.ml            # Execution trace visualization
│   ├── web/                  # Web-specific code
│   │   └── web_interface.ml     # Web playground interface
│   ├── lexer.ml              # Sedlex-based lexer
│   ├── parser.mly            # Menhir parser
│   └── parser_context.ml     # Parser state
├── bin/                      # Executable entry points
│   └── sgen.ml                  # Main CLI
├── test/                     # Test suite (cram tests)
├── examples/                 # Example programs (.sg files)
│   ├── hello.sg                 # Hello world
│   ├── naive_nat.sg             # Natural numbers
│   ├── syntax.sg                # Canonical syntax reference
│   ├── milkyway/                # The prelude (the :: type-assertion macro)
│   ├── lambda/                  # Lambda calculus examples
│   ├── prolog/                  # Logic programming examples
│   ├── proofnets/               # MLL proof nets (correctness as tests)
│   ├── states/                  # State machine examples
│   └── ...
├── ai/                       # AI-assisted research notes (strategy docs)
├── BASICS.md                 # Fundamental mechanics reference
├── web/                      # Web playground
└── nvim/                     # Neovim integration
```

## Multi-Paradigm Support

| Paradigm        | Stellogen Equivalent                                  |
|-----------------|-------------------------------------------------------|
| Logic           | Constellations (elementary blocks)                    |
| Functional      | Layered constellations enforcing interaction order    |
| Imperative      | Iterative recipes for building constellations         |
| Object-oriented | Structured constellations                             |

## Building & Running

### Build from Sources (Dune)
```bash
# Install dependencies
opam install . --deps-only --with-test

# Build
dune build

# Executables in: _build/default/bin/
```

### Build with Nix
```bash
nix develop
dune build
```

### Running Programs
```bash
# Using built executable
./_build/default/bin/sgen.exe eval <inputfile>

# Using Dune
dune exec sgen eval -- <inputfile>

# Subcommands
sgen eval <file>         # both phases: check first, then run if it passed
sgen run <file>          # run phase only (every check skipped)
sgen check <file>        # check phase only (objects + specs + § items)
sgen preprocess <file>   # show code after macro expansion
sgen trace <file>        # run with interactive execution trace

# eval is the normal way to invoke a program; run and check are the two
# phases in isolation. All three exit non-zero on failure. check collects
# assertion failures per top-level item; run stops at the first error.
# Nothing at runtime verifies that check ever ran: gate it in CI, or use
# eval.

# Help
sgen --help
```

**Tip**: when running with a timeout (programs can diverge), invoke the
built binary directly: `timeout -s KILL 10 ./_build/default/bin/sgen.exe
run file.sg`, because `dune exec` wraps the process and defeats `timeout`.

## File Extensions
- `.sg` - Stellogen source files

## Example: Natural Number Addition

```stellogen
; Define addition constellation (a catalyst: the recursive rule is reused)
(def add {
  [(+add 0 Y Y)]
  [(-add X Y Z) (+add (s X) Y (s Z))]})

; Query: 2 + 2 = R
(def query [(-add (s (s 0)) (s (s 0)) R) R])

; Execute interaction
(show (exec *#add #query))   ; => (s (s (s (s 0))))
```

## Example: Type Definition

```stellogen
; spec binds like def but lands in the check phase on its own (no § needed)

; Macro for type assertion; the § sends call sites to the check phase.
; Tested is reactive, Test a catalyst: it is consulted, not consumed
(macro (:: Tested Test)
  §(== (exec #Tested *#Test) ok))

; Define nat type as interactive tests (check phase, thanks to spec)
(spec nat {
  [(-nat 0) ok]
  [(-nat (s N)) (+nat N)]})

; Define and check a value used by both phases
(object zero (+nat 0))
(:: zero nat)  ; verified by sgen check, skipped by sgen run
```

## Dependencies (OCaml)
- `base` - Standard library alternative
- `menhir` - Parser generator
- `sedlex` - Unicode-friendly lexer
- `ppx_deriving` - Code generation
- `alcotest` - Testing framework

## Key Implementation Files

- `src/core/unification.ml` - Generic term unification algorithm (functor)
- `src/core/constellation.ml` - Core types: polarity, rays, stars, constellations, `Marked` module
- `src/core/syntax.ml` - High-level AST: `sgen_expr`, `program`, `env`, `err`
- `src/core/expression.ml` - Expression preprocessing and macro expansion
- `src/eval/evaluator.ml` - Main expression evaluator and interaction engine
- `src/eval/executor.ml` - Star fusion execution (queue-based algorithm)
- `src/output/pretty.ml` - Pretty-printing for terms and constellations
- `bin/sgen.ml` - CLI entry point

### Module Name Reference

| Module | Purpose |
|--------|---------|
| `Constellation` | Core types (rays, stars, constellations) |
| `Syntax` | High-level AST and error types |
| `Expression` | Macro expansion and preprocessing |
| `Evaluator` | Program evaluation |
| `Executor` | Star fusion engine |
| `Pretty` | Pretty-printing |
| `Tracer` | Execution tracing |
| `Stellogen_parsing` | Parser integration |

## Testing

Run tests with:
```bash
dune test
```

## Influences & Related Work

- **Prolog/Datalog**: Unification and logic programming
- **Smalltalk**: Minimalism and message-passing
- **Rocq/Coq**: Proof-as-program paradigm
- **Scheme/Racket**: Metaprogramming spirit
- **Shen**: Optional type systems philosophy
- **Girard's Transcendental Syntax**: Theoretical foundation

## Learning Resources

- **Wiki**: https://github.com/engboris/stellogen/wiki/Basics-of-Stellogen
- **Examples**: See `examples/` directory for practical demonstrations
- **README**: Project overview and philosophy

## Working with this Codebase

### When modifying:
1. The language is **experimental** - syntax and semantics change frequently
2. Understand term unification before touching `core/unification.ml`
3. AST changes require updates to parser, evaluator (`eval/evaluator.ml`), and pretty-printer (`output/pretty.ml`)
4. Test with existing examples in `examples/` after changes
5. **Always run `dune fmt` after finishing code modifications** to ensure consistent formatting
6. Key modules have `.mli` interfaces - update both implementation and interface when changing public APIs

### Important concepts for contributors:
- **Polarity** drives interaction - positive/negative rays fuse
- **Constellations** are the core computational unit
- **Stars** are blocks of rays that can fuse
- **Reactive vs catalyst (`*`)** is CRITICAL - what's being computed vs the reusable rules computing it
- Variables are **local to each star** - not shared between stars
- The evaluator orchestrates term interactions, not traditional evaluation
- Catalysts are **duplicated** during execution and dropped from the result;
  reactive stars are **consumed** when they react, or **kept as is** when they never get the chance (no weakening)

### Common Mistakes When Writing Stellogen

❌ **Mistake 1**: Forgetting `*` on rules/facts that need to be reused
```stellogen
; WRONG - add is reactive, so it is consumed after one recursive step
(def add {
  [(+add 0 Y Y)]
  [(-add X Y Z) (+add (s X) Y (s Z))]})
(def query [(-add (s (s 0)) (s (s 0)) R) R])
(exec #add #query)  ; Gets stuck: leftover query and partial rule, not a number

; CORRECT - mark add a catalyst so each recursive step can reuse it
(def add *{
  [(+add 0 Y Y)]
  [(-add X Y Z) (+add (s X) Y (s Z))]})
(exec #add #query)  ; => (s (s (s (s 0))))
```

❌ **Mistake 2**: Thinking variables are shared between stars
```stellogen
; WRONG assumption: X is shared
{
  [(+f X)]      ; This X is local to this star
  [(-g X)]      ; This X is a DIFFERENT variable!
}

; CORRECT - X shared within ONE star
{
  [(+f X) (-g X)]  ; Same X - shared within this star
}
```

❌ **Mistake 3**: Wrong polarity direction
```stellogen
; WRONG - both negative
{
  [(-data X)]
  [(-result X)]   ; Nothing to provide data!
}

; CORRECT - provider (+) and requester (-)
{
  [(+data X)]     ; Provides
  [(-data X)]     ; Requests
}
```

❌ **Mistake 4**: Expecting clause-based execution (Prolog style)
```stellogen
; Stellogen is NOT clause-based!
; Constellations are UNORDERED sets of stars
; Order doesn't determine execution flow
; Use polarity and the reactive/catalyst mark instead
```

### Debugging tips:
- **Stuck or cluttered result?** Check whether a rule or fact that should be reused is missing its `*`
- **No interaction happening?** Verify polarity: need `+` and `-` to match, and check any `!X` guard is actually ground
- **Variables not binding?** Remember: variables are local to each star
- Use `(show ...)` to inspect intermediate results
- Examine `examples/*.sg` for canonical usage patterns
- **Read `BASICS.md`** for fundamental mechanics
- Parser errors: check parenthesis balance and syntax sugar
- Unification failures: verify term structure and polarity
- **Test incrementally**: Start simple, add complexity gradually

## License

GPL-3.0-only

## Maintainers

- Author: Boris Eng
- Maintainer: Boris Eng

## Quick Reference Card

### Syntax Quick Lookup
```stellogen
; Comments
; single line (stack ; lines for longer comments)

; Terms
X Y Z           ; Variables (uppercase)
(f a b)         ; Function application
a bob 0         ; Constants

; Rays
(+f X)          ; Positive polarity (provides)
(-f X)          ; Negative polarity (requests)
(f X)           ; Neutral (no interaction)

; Stars and Constellations
[ray1 ray2]     ; Star (block of rays), reactive by default
{ star1 star2 } ; Constellation (group of stars)
*[...]          ; Catalyst star (reusable, dropped from the result)
!X              ; Ground guard: the ray waits until X is ground
[(+f X) || (!= X Y)]  ; Star with inequality constraint

; Definitions and Calls
(def name value) ; Define (in the phase of the enclosing item)
(object name value) ; Define shared between check and run phases
(spec name value) ; Define in the check phase only (no § needed)
#name           ; Call/reference
*#name          ; Call and mark a catalyst

; Phases
§expr           ; Any top-level expression: check phase (sgen check)
                ; Unmarked top-level expressions: run phase (sgen run)
                ; (spec ...) is check-phase on its own

; Execution
(exec c1 c2)    ; c1 and c2's reactive stars react freely; *-marked ones are catalysts
                ; Staged execution: nest them, (exec c2 (exec c1 base))

; Utilities
(show expr)     ; Display result
(== e1 e2)      ; Assert equality (ignores the reactive/catalyst mark)
(~= r1 r2)      ; Check unifiability (ignores polarity and guards)
(forall G X e)  ; Evaluate e for each member of galaxy G bound to X

; Imports
(use "path")    ; Import definitions and macros (path relative to this file)

; Syntactic Sugar
[a b c]         ; In TERM position: list (%cons a (%cons b (%cons c %nil)))
                ; At constellation level: a star of three rays!
                ; No stacking sugar: write (s (s 0)) directly
{ a b c }       ; Group: (%group a b c)

; Macros
(macro pattern expansion)
```

### Mental Model
```
FACTS (data)     = Positive rays (+), usually catalysts (*)
QUERIES (goals)  = Negative rays (-), reactive (the default)
RULES            = Stars with a POSITIVE head (conclusion) and
                   NEGATIVE premises, usually catalysts (*) too
EXECUTION        = Saturation via star fusion (reactive/reactive,
                   reactive/catalyst, or a star with itself)
```

### Typical Program Structure
```stellogen
; 1. Define facts/data (positive), as a catalyst
(def facts *{
  [(+parent tom bob)]
  [(+parent bob ann)]})

; 2. Define rules (positive conclusion, negative premises), also a catalyst
(def rules *{
  [(+grandparent X Z) (-parent X Y) (-parent Y Z)]})

; 3. Execute against a reactive query (negative)
(show (exec { #facts #rules } [(-grandparent tom Z) (result Z)]))
; => (result ann)
```

---

*Last updated: 2026-07-15. All code examples in this file are verified to run against the current implementation.*
*For current implementation details, always refer to `BASICS.md`, `KERNEL.md`, the wiki, and source code as the language evolves rapidly.*
