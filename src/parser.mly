%{
open Expression.Raw
%}

%token <string> VAR
%token <string> GVAR
%token <string> SYM
%token <string> STRING
%token STAR
%token AT
%token BAR
%token LPAR RPAR
%token LBRACK RBRACK
%token LBRACE RBRACE
%token SHARP
%token SECTION
%token EOF

%start <Expression.Raw.t list> expr_file

%%

let delimited_opt(l, x, r) :=
  | ~=x; <>
  | ~=delimited(l, x, r); <>

let revlist(x) :=
  | { [] }
  | t=revlist(x); h=x; { h::t }

let pars(x) == ~=delimited(LPAR, x, RPAR); <>
let bracks(x) == ~=delimited(LBRACK, x, RBRACK); <>
let braces(x) == ~=delimited(LBRACE, x, RBRACE); <>

let expr_file :=
  | EOF; { [] }
  | es=expr+; EOF; { es }

let params :=
  | BAR; BAR; ~=expr+; <>

(* Every expr, not just top-level declarations, is wrapped with its own
   source span. Nested exec stages need their own location to be
   traceable line by line, not just the declaration that encloses them. *)
let expr :=
  | e=raw_expr; {
      let pos_start = { $startpos(e) with Lexing.pos_fname = !(Parser_context.current_filename) } in
      let pos_end = { $endpos(e) with Lexing.pos_fname = !(Parser_context.current_filename) } in
      Positioned (e, pos_start, pos_end)
    }

let raw_expr :=
  | ~=pars(expr+); <List>
  | ~=bracks(revlist(expr)); <Cons>
  | ~=braces(revlist(expr)); <Group>
  | LBRACK; ~=revlist(expr); ~=params; RBRACK; <ConsWithParams>
  | LBRACK; ~=revlist(expr); BAR; ~=expr; RBRACK; <ConsWithBase>
  | SHARP; ~=expr; <Call>
  | STAR; ~=expr; <Catalyst>
  | AT; ~=expr; <Seed>
  | SECTION; ~=expr; <Static>
  | ~=SYM; <Symbol>
  | ~=VAR; <Var>
  | ~=GVAR; <GuardedVar>
  | ~=STRING; <String>
