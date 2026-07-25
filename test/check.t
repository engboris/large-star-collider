Check phase of the examples
===========================

The type assertions of the examples live in the check phase, so they
only have test coverage if sgen check runs here. A silent success with
exit 0 is the expected outcome for each file.

  $ sgen check ../examples/naive_nat.sg
  $ sgen check ../examples/sumtypes.sg
  $ sgen check ../examples/binary4.sg
  $ sgen check ../examples/lambda/linear_lambda.sg
  $ sgen check ../examples/proofnets/mll.sg
  $ sgen check ../examples/states/nfa.sg
  $ sgen check ../examples/states/npda.sg
