# Stellogen Core Patterns & Mechanics

## Syntax Quick Reference

```stellogen
; Comments (single line)
;  Multi-line comments

; Terms
X Y Z              ; Variables (uppercase, local to each star)
a bob 0            ; Constants (lowercase/digits)
(f X a)            ; Function application
(+f X)             ; Positive polarity (provides)
(-f X)             ; Negative polarity (requests)

; Structures
[ray1 ray2 ...]    ; Star (block of rays)
{ star1 star2 }    ; Constellation (group of stars)
@[...]             ; Focused star (state — REQUIRED for execution targets)
@{...}             ; Focus all stars in constellation
*[...]             ; Linear star (consumable — used at most once)
*{...}             ; Mark every star in constellation consumable

; Definitions & calls
(def name value)          ; Definition
(def (name A B) value)    ; Parameterised definition
#name                     ; Call/reference
#(name a b)               ; Call parameterised definition
@#name                    ; Call and focus

; Execution
(exec actions @states)    ; actions reusable by default
(exec *actions @states)   ; * marks actions consumable (used at most once)
(exec c3 (exec c2 c1))    ; Chain: exec c2 on c1, then c3 on the result

; Testing & display
(show expr)               ; Display result
(== e1 e2)                ; Assert syntactic equality
(~= r1 r2)                ; Check unifiability (polarity is ignored)

; Syntactic sugar
[a b c]                   ; Cons list: (%cons a (%cons b (%cons c %nil)))
[a|Tail]                  ; Cons with tail variable

; Constraints
[rays... || (!= X Y)]    ; Inequality constraint on star

; Types (galaxy-based)
(spec typename { tests }) ; Define type as galaxy of tests
(:: value typename)       ; Assert value passes all tests (needs prelude)
(forall Galaxy G body)    ; Iterate over galaxy entries

; Phases (two superposed programs per file)
§expr                     ; Top-level expression in the check phase (sgen check)
                          ; Unmarked top-level expressions: run phase (sgen run)
(object name value)       ; Definition shared by both phases

; Macros
(macro (pattern) (expansion))
(macro (pattern A B ...) (expansion using A B ...))

; Imports
(use "path.sg")           ; Import definitions and macros
```

## Fundamental Mechanics

### Star Fusion

When two stars have **compatible rays** (opposite polarity + unifiable terms):
1. Compatible rays are **consumed** (disappear)
2. The **unifying substitution** applies to all remaining rays
3. The two stars **merge** into one

```
Star 1: [(+f X) (result X)]
Star 2: @[(-f hello)]

Fusion: (+f X) matches (-f hello) with {X := hello}
Result: [(result hello)]
```

### Execution Model

- **Action stars** (no `@`): rules, duplicated as needed during `exec`
- **State stars** (`@`): data being transformed, consumed during execution
- Execution = repeated fusion until **saturation** (no more interactions possible)
- Result = remaining constellation after saturation

### Chaining execs

There is no staging form: nest `exec` instead. `(exec c3 (exec c2 c1))`
means:
1. Execute c1 → result r1
2. Execute c2 against r1 → result r2
3. Execute c3 against r2 → final result

Long pipelines read better as a chain of named steps, each `exec`ing
against the previous one:

```stellogen
(def s1 (exec #c2 #c1))
(def s2 (exec #c3 #s1))
```

## Paradigm Patterns

### Pattern: State Machines (Automata Hierarchy)

All automata share the same core idea: a state term consumed (-) and produced (+) at each step, with input read from a cons list. The complexity grows by adding **stacks** (also cons lists).

**Finite automaton (NFA)** — state + input consumption:
```stellogen
; State term: (+a InputWord CurrentState)
(def (initial Q) [(-i W) (+a W Q)])
(def (accept Q) [(-a [] Q) accept])
(def (if read C on Q1 then Q2) [(-a [C|W] Q1) (+a W Q2)])
```

**Pushdown automaton (NPDA)** — adds an auxiliary stack:
```stellogen
; State term: (+a InputWord Stack CurrentState)
(def (initial Q) [(-i W) (+a W [] Q)])
(def (accept Q) [(-a [] [] Q) accept])
(def (if read C on Q1 then Q2 and push D) [(-a [C|W] S Q1) (+a W [D|S] Q2)])
(def (if read C with D on Q1 then Q2) [(-a [C|W] [D|S] Q1) (+a W S Q2)])
(def (if on Q1 then Q2) [(-a W S Q1) (+a W S Q2)])
```

**Turing machine** — two stacks simulate a tape (left of head + right of head):
```stellogen
; State term: (+m State LeftTape CurrentSymbol RightTape)
; Moving right = push current onto left, pop from right
; Moving left  = push current onto right, pop from left
(def (initial Q) {
  [(-i [C|W]) (+m Q [e e] C W)]
  [(-i [])    (+m Q e e e)]})
(def (accept Q) [(-m qa L e R) accept])
(def (if C on Q1 then Q2 , write D , right)
  [(-m Q1 L C [N|R]) (+m Q2 [D|L] N R)])
(def (if C on Q1 then Q2 , write D , left)
  [(-m Q1 [N|L] C R) (+m Q2 L N [D|R])])
```

**General principle**: a state machine is a state term with an arbitrary number of cons-list stacks. Each stack supports push (`[D|S]` on output), pop (`[D|S]` on input), and passthrough (`S`). The specific automaton class is determined by how many stacks you use and how you constrain them:

| Stacks | Model |
|--------|-------|
| 0 extra | Finite automaton (NFA) — input is the only "stack", strictly consumed |
| 1 extra | Pushdown automaton (NPDA) |
| 2 (as tape) | Turing machine — left + right of head |
| n | Multi-tape TM, custom machines |

You can freely define new machine models by adding more stacks to the state term and writing parameterised transitions for them.

### Pattern: Logic / Relations
Facts as positive rays, queries as focused negative rays:
```stellogen
(def facts { [(+rel a b)] [(+rel b c)] })
(def query @[(-rel a X) (result X)])
(show (exec #facts #query))
```

### Pattern: Recursive Computation
Base case as positive, recursive case links negative to positive:
```stellogen
(def add {
  [(+add 0 Y Y)]
  [(-add X Y Z) (+add (s X) Y (s Z))]})
```

### Pattern: Proof Structures (MLL)

MLL proof-structures are graphs with axiom links, cuts, tensor (⊗), and par (⅋) connectives. They are encoded as constellations where **addresses** track the path from a conclusion to an atom through connectives.

**Addresses**: each atom gets an address `c(path)` where `c` is the conclusion vertex it is reachable from, and `path` is a sequence of `l`/`r` directions recording the path through par/tensor nodes. In Stellogen, this is a cons list: `c([l|[r|X]])` means "go left then right from conclusion `c`". A direct atom has address `c(X)`.

**Axioms** — binary positive stars linking two atoms by their addresses:
```stellogen
; Axiom between atoms with addresses from conclusions 1 and 2
[(+1 X) (+2 X)]

; Axiom above a par (conclusion 7), left and right paths
[(+7 [l|X]) (+7 [r|X])]

; Axiom with left path to tensor (conclusion 8)
[(+3 X) (+8 [l|X])]
```

**Cuts** — binary negative stars connecting two conclusions:
```stellogen
[-7 -8]             ; First-order MLL (no connectives)
[(-7 X) (-8 X)]    ; Full MLL (with connectives, addresses flow through)
```

**Cut-elimination** = stellar execution. When a par/tensor cut is eliminated, the cut star duplicates into two cuts connecting the left and right subpaths respectively, because `[l|X]` unifies with `[l|X]` and `[r|X]` with `[r|X]`.

**Type checking (tests)** encodes correctness criteria. Par and tensor produce different test shapes:

- **Tensor** test — both premises consumed in a single star:
  `[(-u X) (-w X) (+v X)]`

- **Par** test — two switching variants (one premise active, one absorbed):
  - Left:  `[(-u X) (+v X)]` + `[(-w X)]`
  - Right: `[(-u X)]` + `[(-w X) (+v X)]`

- **Conclusion** test: `[(-v X) ok]` or `[(-v X) +concl]` with `[-concl ok]`

### Pattern: Linear Lambda Calculus (via MLL Proof Nets)

Linear lambda terms are encoded as MLL proof nets. Each lambda term translates to a constellation of axiom stars with addresses. The key is the **Curry-Howard correspondence**: a linear function `A ⊸ B` corresponds to `A^⊥ ⅋ B` in MLL.

**Translation of terms** — each term becomes axiom stars where addresses encode the binding structure:

- **Variable** `x`: a single axiom linking the variable's binding site to the function output.
- **Abstraction** `λx.M`: introduces a par (⅋) — the bound variable goes left (`[l|X]`), the body goes right (`[r|X]`), both under the same conclusion.
- **Application** `(M N)`: introduces a tensor (⊗) / cut — the function goes left, the argument goes right, and a cut connects them.

**Identity function** `λx.x` — one axiom above a par:
```stellogen
; Two addresses from same conclusion (par): left = bound var, right = body
(def id [(+id [l|X]) (+id [r|X])])
```

**Application** `(M N)` — a linker with a cut between function and argument:
```stellogen
; Argument term (e.g. another id, or a variable)
(def id_arg [(ida [l|X]) (+arg [l r|X])])

; Cut connecting function to argument, with focused output
(def linker [
  [(-id X) (-arg X)]
  @[(+arg [r|X]) (out X)]])

(show (exec #id #id_arg #linker))
```

**Linear types** as galaxy-based specs — `A ⊸ A` is `A^⊥ ⅋ A`, tested with par switchings:
```stellogen
(spec (larrow a a)
  {[+test1 [
    [(-x X) (+parxy X)]    ; left switching: x active
    [(-y X)]
    @[(-parxy X) ok]]]}
  {[+test2 [
    [(-x X)]
    [(-y X) (+parxy X)]    ; right switching: y active
    @[(-parxy X) ok]]]})

; Adapt proof-net conclusions to type variable names
(def adapter {
  [(-id [l|X]) (+x X)]     ; left of par = bound variable
  [(-id [r|X]) (+y X)]})   ; right of par = body/output
```

See `examples/lambda/linear_lambda.sg` and `examples/proofnets/mll.sg` for complete examples.

### Pattern: Type Checking
Types are galaxies (collections of constellations) of interactive tests.
`::` hides a `§` in its expansion, so assertions live in the check phase:
verified by `sgen check`, skipped by `sgen run`.
```stellogen
§(spec typename { test1 test2 ... })  ; type only used for checking
(object val ...)      ; value used by both the checks and the run program
(:: val typename)     ; Passes if every test yields ok (check phase)
```

## Cleaning Results

- `(def kill (-unwanted _ _))` — absorb leftover rays after execution
- `(exec #kill (exec ...))` — chain a cleanup step
