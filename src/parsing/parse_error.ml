(* Structured, single-error reporting for the incremental parser *)

(* Structured parse error *)
type parse_error =
  { position : Lexing.position
  ; message : string
  ; hint : string option
  }

let create_error ~position ~message ?hint () = { position; message; hint }

(* Convert token to string for error messages *)
let string_of_token = function
  | Parser.VAR s | Parser.SYM s | Parser.STRING s -> s
  | Parser.GVAR s -> "!" ^ s
  | Parser.STAR -> "*"
  | Parser.AT -> "@"
  | Parser.BAR -> "|"
  | Parser.LPAR -> "("
  | Parser.RPAR -> ")"
  | Parser.LBRACK -> "["
  | Parser.RBRACK -> "]"
  | Parser.LBRACE -> "{"
  | Parser.RBRACE -> "}"
  | Parser.SHARP -> "#"
  | Parser.SECTION -> "\xc2\xa7"
  | Parser.EOF -> "EOF"

(* Generate a helpful error message based on context *)
let contextualize_error last_token delimiters_stack =
  match last_token with
  | Some Parser.EOF when delimiters_stack <> [] ->
    let delim_char, _ = List.hd delimiters_stack in
    ( Printf.sprintf "unclosed delimiter '%c'" delim_char
    , Some "add the missing closing delimiter" )
  | Some Parser.EOF -> ("unexpected end of file", Some "the input is incomplete")
  | Some ((Parser.RPAR | Parser.RBRACK | Parser.RBRACE) as tok) ->
    let tok_str =
      match tok with
      | Parser.RPAR -> ")"
      | Parser.RBRACK -> "]"
      | Parser.RBRACE -> "}"
      | _ -> "?"
    in
    ( Printf.sprintf "no opening delimiter for '%s'" tok_str
    , Some "remove this delimiter or add a matching opening delimiter" )
  | Some tok ->
    let tok_str = string_of_token tok in
    ( Printf.sprintf "unexpected symbol '%s'" tok_str
    , Some "check if this symbol is in the right place" )
  | None -> ("unexpected end of input", None)

(* Extract error information from parser environment *)
let error_from_env env last_token delimiters_stack =
  let error_pos, _ = Parser.MenhirInterpreter.positions env in
  let message, hint = contextualize_error last_token delimiters_stack in
  create_error ~position:error_pos ~message ?hint ()
