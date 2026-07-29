Test syntax - basic syntax tests
==================================

Reactive rule consumption test:
  $ sgen run syntax/linear.sg

Relational recursion test:
  $ sgen run syntax/relational.sg

Records test:
  $ sgen run syntax/records.sg

Multi-star def test:
  $ sgen run syntax/multistar_def.sg

Galaxy and forall test:
  $ sgen run syntax/galaxy.sg
  [(-check a) ok]
  [(-check b) ok]

Match (~=) is polarity-blind structural unifiability:
  $ sgen run syntax/match.sg

Variable renaming (same-named locals in fused stars stay distinct):
  $ sgen run syntax/var_renaming.sg
  [(o2 7) (o1 5)]

Variable identity is the (name, index) pair, not its printed form:
  $ sgen run syntax/var_index_collision.sg
  [(out a) (h V1) (h V2) (h V3) (h V4) (h V5) (h V6) (h V7) (h V8) (h V9) (h X)]

Polarity is read off a symbol, never off string contents or a bare +/-:
  $ sgen run syntax/polarity_of_symbols.sg
  { [+a ok] [-a no] }
  
  { [(result X + Y = R) one] [(result a - b = c) two] }
  [(result X + Y = R) (result 1 + 2 = 3)]
  [one two]
