Test examples directory
========================

Binary4 example:
  $ sgen run ../examples/binary4.sg
  { [(+b b1 1 0)] [(+b b1 2 0)] [(+b b1 3 0)] [(+b b1 4 1)] }
  { [(+b b2 1 0)] [(+b b2 2 0)] [(+b b2 3 1)] [(+b b2 4 1)] }
  { [(+b r 1 0)] [(+b r 2 0)] [(+b r 3 0)] [(+b r 4 1)] }
  { [(+b r 1 0)] [(+b r 2 0)] [(+b r 3 1)] [(+b r 4 1)] }
  { [(+b r 1 1)] [(+b r 2 1)] [(+b r 3 1)] [(+b r 4 0)] }
  { [(+b r2 1 1)] [(+b r2 2 1)] [(+b r2 3 1)] [(+b r2 4 0)] }
  { [(+b r3 1 0)] [(+b r3 2 0)] [(+b r3 3 1)] [(+b r3 4 0)] }

Hello world example:
  $ sgen run ../examples/hello.sg
  (hello world)

Lambda calculus example:
  $ sgen run ../examples/lambda/lambda.sg
  [(out [r X3]) (lproj (exp [r l X3] d))]

Linear lambda example:
  $ sgen run ../examples/lambda/linear_lambda.sg
  [(out [X7]) (x X7)]
  [(out [r X7]) (ida [l X7])]

MALL (multiplicative-additive linear logic) example:
  $ sgen run ../examples/proofnets/mall.sg
  { [(+3 [l r X]) (d X)] [(+5 [r l X]) (+5 [r r X]) || (slice c b)] [(+5 [l r X3]) (c X3) || (slice c a)] }

MLL (multiplicative linear logic) example:
  $ sgen run ../examples/proofnets/mll.sg

Natural numbers example:
  $ sgen run ../examples/naive_nat.sg
  (+nat (s (s (s 0))))
  (+nat (s (s (s (s 0)))))
  (res 1)
  (res 0)

NPDA (non-deterministic pushdown automaton) example:
  $ sgen run ../examples/states/npda.sg
  { [accept] [accept] }
  accept
  accept
  {}

Relational arithmetic example:
  $ sgen run ../examples/relational/arithmetic.sg
  (result 0 + 0 = 0)
  (result 0 + (s (s (s (s 0)))) = (s (s (s (s 0)))))
  (result (s (s 0)) + (s (s 0)) = (s (s (s (s 0)))))
  (result (s (s 0)) + (s (s 0)) = (s (s (s (s 0)))))
  (result 0 - 0 = 0)
  (result (s (s (s (s 0)))) - (s (s 0)) = (s (s 0)))
  (result (s (s (s (s 0)))) - (s (s 0)) = (s (s 0)))

Relational joins example:
  $ sgen run ../examples/relational/joins.sg
  { [c] [d] }
  { [c] [d] }

Relational constraints example:
  $ sgen run ../examples/relational/constraints.sg
  { [(pair 1 2) || (!= 1 2)] [(pair 1 3) || (!= 1 3)] [(pair 2 1) || (!= 2 1)] [(pair 2 3) || (!= 2 3)]...
  [(pair 3 1) || (!= 3 1)] [(pair 3 2) || (!= 3 2)] }

Sum types example:
  $ sgen run ../examples/sumtypes.sg
  a

Turing machine example:
  $ sgen run ../examples/states/turing.sg
  reject
  reject
  reject
  accept
  accept
  accept
  accept
  accept

NFA (non-deterministic finite automaton) example:
  $ sgen run ../examples/states/nfa.sg
  {}
  accept
  {}
  {}

Boolean circuits example (reactive net with ground guards):
  $ sgen run ../examples/circuits.sg
