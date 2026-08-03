Error Messages Test Suite
=========================

This test suite verifies that syntax errors produce proper error messages
with correct location information (file:line:column).

Lexer Errors
------------

Test unterminated string literal:
  $ sgen run errors/unterminated_string.sg
  error: Unterminated string literal
    --> errors/unterminated_string.sg:2:24
  
      2 | (def test "unterminated
        |                        ^
  
  
  found 1 error(s)
  [1]

Test that internal %-names cannot be forged:
  $ sgen run errors/reserved_percent.sg
  error: '%' starts an internal name and is reserved
    --> errors/reserved_percent.sg:2:19
  
      2 | (show (exec [(-f (%! X)) (out X)] [(+f a)]))
        |                   ^
  
  
  found 1 error(s)
  [1]

Test unknown escape sequence:
  $ sgen run errors/unknown_escape.sg
  error: Unknown escape sequence '\x'
    --> errors/unknown_escape.sg:2:18
  
      2 | (def test "hello\xworld")
        |                  ^
  
  
  found 1 error(s)
  [1]

Test invalid escape sequence:
  $ sgen run errors/invalid_string_char.sg
  error: Unknown escape sequence '\q'
    --> errors/invalid_string_char.sg:2:18
  
      2 | (def test "valid\qinvalid")
        |                  ^
  
  
  found 1 error(s)
  [1]

Delimiter Matching Errors
-------------------------

Test mismatched parenthesis and bracket:
  $ sgen run errors/mismatched_paren.sg
  error: No opening delimiter for ']'.
    --> errors/mismatched_paren.sg:2:20
  
      2 | (def test (foo bar]
        |                    ^
  
  
  found 1 error(s)
  [1]

Test mismatched bracket and brace:
  $ sgen run errors/mismatched_bracket.sg
  error: No opening delimiter for '}'.
    --> errors/mismatched_bracket.sg:2:20
  
      2 | (def test [foo bar})
        |                    ^
  
  
  found 1 error(s)
  [1]

Test unclosed parenthesis:
  $ sgen run errors/unclosed_paren.sg
  error: unclosed delimiter '('
    --> errors/unclosed_paren.sg:2:20
  
      2 | (def test (foo bar)
        |                    ^
  
  
    hint: add the missing closing delimiter
  
  found 1 error(s)
  [1]

Declaration Errors
------------------

Test that any expression is now valid as a term (unified design):
  $ sgen run errors/invalid_declaration.sg

Test that a call inside a term is rejected:
  $ sgen run errors/call_in_term.sg
  error: misplaced call '#k'
    --> errors/call_in_term.sg:3:7
  
      3 | (show [(-run #k idle T)])
        |       ^
    hint: A call is resolved when the program runs, so it cannot be part of a term.
  
  [1]


Fail-Fast on Multiple Errors
-----------------------------

Test multiple errors (reports first error only, no recovery):
  $ sgen run errors/multiple_errors.sg
  error: Unterminated string literal
    --> errors/multiple_errors.sg:4:1
  
  
  found 1 error(s)
  [1]

