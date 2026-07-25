open Sedlexing
open Parser

exception LexerError of string * Lexing.position

let last_token = ref None

let delimiters_stack : (char * Lexing.position) list ref = ref []

let space = [%sedlex.regexp? Plus (' ' | '\t')]

let newline = [%sedlex.regexp? '\r' | '\n' | "\r\n"]

let push_delimiter sym (pos : Lexing.position) =
  delimiters_stack := (sym, pos) :: !delimiters_stack

let opposite_delimiter = function
  | '(' -> ')'
  | '[' -> ']'
  | '{' -> '}'
  | ')' -> '('
  | ']' -> '['
  | '}' -> '{'
  | _ ->
    (* This case should be unreachable - if hit, it indicates a bug in the lexer *)
    assert false

let pop_delimiter sym (pos : Lexing.position) =
  match !delimiters_stack with
  | [] -> ()
  | (opening, _) :: _ when opening <> sym ->
    let msg =
      Printf.sprintf "No opening delimiter for '%c'." (opposite_delimiter sym)
    in
    raise (LexerError (msg, { pos with pos_cnum = pos.pos_cnum + 1 }))
  | _ :: rest -> delimiters_stack := rest

let set_newline_pos lexbuf =
  let open Sedlexing in
  let start_pos, _ = lexing_positions lexbuf in
  let new_pos =
    { start_pos with
      pos_lnum = start_pos.pos_lnum + 1
    ; pos_bol = start_pos.pos_cnum
    }
  in
  set_position lexbuf new_pos

let rec comment lexbuf =
  let tok =
    match%sedlex lexbuf with
    | newline ->
      set_newline_pos lexbuf;
      read lexbuf
    | eof -> read lexbuf
    | _ ->
      ignore (Sedlexing.next lexbuf);
      comment lexbuf
  in
  last_token := Some tok;
  tok

and read lexbuf =
  let get_pos () = fst (Sedlexing.lexing_positions lexbuf) in
  let tok =
    match%sedlex lexbuf with
    (* Ground guard on a variable occurrence: !X. Listed before the
       generic symbol rule so it wins the tie; '!' followed by
       anything else (e.g. the != ban) still lexes as a symbol. *)
    | '!', ('A' .. 'Z' | '_'), Star (Compl (Chars "; \t\n\r()[]{}|")) ->
      let lexeme = Utf8.lexeme lexbuf in
      GVAR (String.sub lexeme 1 (String.length lexeme - 1))
    | ( Compl (Chars "';\" \t\n\r()[]{}|@#*" | 0xA7)
      , Star (Compl (Chars "; \t\n\r()[]{}|")) ) -> (
      let lexeme = Utf8.lexeme lexbuf in
      match lexeme.[0] with '_' | 'A' .. 'Z' -> VAR lexeme | _ -> SYM lexeme )
    | '(' ->
      push_delimiter '(' (get_pos ());
      LPAR
    | ')' ->
      pop_delimiter '(' (get_pos ());
      RPAR
    | '[' ->
      push_delimiter '[' (get_pos ());
      LBRACK
    | ']' ->
      pop_delimiter '[' (get_pos ());
      RBRACK
    | '{' ->
      push_delimiter '{' (get_pos ());
      LBRACE
    | '}' ->
      pop_delimiter '{' (get_pos ());
      RBRACE
    | '*' -> STAR
    | '@' -> AT
    | '#' -> SHARP
    | 0xA7 -> SECTION (* the section sign, written as U+00A7 *)
    | '|' -> BAR
    | ';' -> comment lexbuf
    | '"' -> string_literal lexbuf
    | space -> read lexbuf
    | newline ->
      set_newline_pos lexbuf;
      read lexbuf
    | eof -> EOF
    | _ ->
      let msg =
        Printf.sprintf "Unexpected character '%s' during lexing"
          (Utf8.lexeme lexbuf)
      in
      raise (LexerError (msg, get_pos ()))
  in
  last_token := Some tok;
  tok

and string_literal lexbuf =
  let buffer = Buffer.create 32 in
  let get_pos () = fst (Sedlexing.lexing_positions lexbuf) in
  let rec loop () =
    match%sedlex lexbuf with
    | '"' -> STRING (Buffer.contents buffer)
    | '\\', any ->
      let escaped =
        match%sedlex lexbuf with
        | 'n' -> '\n'
        | 't' -> '\t'
        | '\\' -> '\\'
        | '"' -> '"'
        | _ ->
          let msg =
            Printf.sprintf "Unknown escape sequence '\\%s'"
              (Sedlexing.Utf8.lexeme lexbuf)
          in
          raise (LexerError (msg, get_pos ()))
      in
      Buffer.add_char buffer escaped;
      loop ()
    | eof -> raise (LexerError ("Unterminated string literal", get_pos ()))
    | any ->
      Buffer.add_string buffer (Sedlexing.Utf8.lexeme lexbuf);
      loop ()
    | _ ->
      let msg =
        Printf.sprintf "Invalid character in string literal: '%s'"
          (Sedlexing.Utf8.lexeme lexbuf)
      in
      raise (LexerError (msg, get_pos ()))
  in
  loop ()
