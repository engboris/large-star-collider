Phase separation test suite
===========================

A program is two superposed programs: § items form the check phase,
unmarked items the run phase, and object definitions are shared.

Basics: each command sees the shared object and its own items:
  $ sgen run phases/basics.sg
  run-sees (+f a)
  $ sgen check phases/basics.sg
  check-sees (+f a)

eval does both, check phase first:
  $ sgen eval phases/basics.sg
  check-sees (+f a)
  run-sees (+f a)

A failing check phase stops eval before the run phase:
  $ sgen eval phases/eval_fail.sg
  error: assertion failed
    --> phases/eval_fail.sg:2:2
  
      2 | §(== a b)
        |  ^
  
    Expected: b
         Got: a
  
  [1]

Separate namespaces: one name, a different value per phase:
  $ sgen run phases/name_reuse.sg
  (+q two)
  $ sgen check phases/name_reuse.sg
  (+q one)

Cross-phase reference from check to run is a diagnosed error:
  $ sgen check phases/cross_phase_check.sg
  error: identifier not visible in this phase
    --> phases/cross_phase_check.sg:3:8
  
      3 | §(show #query)
        |        ^
    hint: 'query' is defined in the run phase but referenced from a check-phase expression.
  
  [1]

The same file runs fine, since the run phase never looks the name up:
  $ sgen run phases/cross_phase_check.sg

Cross-phase reference from run to check:
  $ sgen run phases/cross_phase_run.sg
  error: identifier not visible in this phase
    --> phases/cross_phase_run.sg:3:7
  
      3 | (show #aux)
        |       ^
    hint: 'aux' is defined in the check phase but referenced from a run-phase expression.
  
  [1]

And check is fine with it:
  $ sgen check phases/cross_phase_run.sg

Nested § inside a term is rejected, not absorbed:
  $ sgen run phases/nested_static.sg
  error: misplaced '§' in '(§ a)'
    --> phases/nested_static.sg:2:8
  
      2 | (def x (f §a))
        |        ^
    hint: The '§' marker can only prefix a whole top-level expression.
  
  [1]

§ on an object definition is contradictory:
  $ sgen run phases/static_object.sg
  error: '§' cannot be applied to an object definition
    --> phases/static_object.sg:2:1
  
      2 | §(object x (+f a))
        | ^
    hint: Objects are shared between both phases; remove the marker.
  
  [1]

§ on a macro definition is meaningless (macros are phase-less):
  $ sgen run phases/static_macro.sg
  error: '§' cannot be applied to a macro definition
    --> phases/static_macro.sg:2:1
  
      2 | §(macro (id X) X)
        | ^
    hint: Macros are expanded before phases exist; remove the marker.
  
  [1]

§(use ...) imports definitions into the check phase only:
  $ sgen check phases/static_use.sg
  (+h ok)
  $ sgen run phases/static_use.sg
  error: identifier not found
    --> phases/static_use.sg:7:7
  
      7 | (show #helper)
        |       ^
    hint: The identifier 'helper' was not defined.
  
  [1]

Check collects assertion failures per top-level item and keeps going:
  $ sgen check phases/collect.sg
  done
  error: assertion failed
    --> phases/collect.sg:2:2
  
      2 | §(== a b)
        |  ^
  
    Expected: b
         Got: a
  
  error: unification failed
    --> phases/collect.sg:4:2
  
      4 | §(~= (+f a) (+g b))
        |  ^
  
    Term 1: (+f a)
    Term 2: (+g b)
  
  [1]
