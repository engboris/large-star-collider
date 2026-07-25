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
