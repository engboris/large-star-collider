open Base
open Constellation
open Constellation.StellarRays
open Constellation.Raw

let string_of_polarity = function Pos -> "+" | Neg -> "-" | Null -> ""

let string_of_polsym (p, f) = string_of_polarity p ^ f

let string_of_var (x, index_opt) =
  match index_opt with None -> x | Some i -> x ^ Int.to_string i

(* Mirror of the escapes the lexer accepts inside a string literal. *)
let escape_string_contents =
  String.concat_map ~f:(function
    | '\\' -> "\\\\"
    | '"' -> "\\\""
    | '\n' -> "\\n"
    | '\t' -> "\\t"
    | c -> String.of_char c )

let rec string_of_ray = function
  | Var var -> string_of_var var
  | Func ((Null, "%nil"), []) -> "[]"
  | Func (pf, []) -> string_of_polsym pf
  | Func ((Null, "%group"), terms) ->
    (* Pretty-print constellation groups as {...} *)
    if List.is_empty terms then "{}"
    else
      let stars_str =
        List.map terms ~f:string_of_ray |> String.concat ~sep:" "
      in
      Printf.sprintf "{ %s }" stars_str
  | Func ((Null, "%cons"), [ head; tail ]) -> (
    (* Cons lists as [a b c], and a non-nil tail as [a b|tail] *)
    let rec collect_list acc = function
      | Func ((Null, "%cons"), [ h; t ]) -> collect_list (h :: acc) t
      | Func ((Null, "%nil"), []) -> (List.rev acc, None)
      | other -> (List.rev acc, Some other)
    in
    let elements, rest = collect_list [ head ] tail in
    let elems_str =
      List.map elements ~f:string_of_ray |> String.concat ~sep:" "
    in
    match rest with
    | None -> Printf.sprintf "[%s]" elems_str
    | Some t -> Printf.sprintf "[%s|%s]" elems_str (string_of_ray t) )
  | Func ((Null, "*"), [ inner ]) ->
    (* Catalyst marker *)
    Printf.sprintf "*%s" (string_of_ray inner)
  | Func ((Null, "@"), [ inner ]) ->
    (* Seed marker *)
    Printf.sprintf "@%s" (string_of_ray inner)
  | Func ((Null, "%!"), [ inner ]) ->
    (* Ground guard on a position *)
    Printf.sprintf "!%s" (string_of_ray inner)
  | Func ((Null, "%params"), [ rays; bans ]) ->
    (* Star with constraints *)
    Printf.sprintf "%s || %s" (string_of_ray rays) (string_of_ray bans)
  | Func ((Null, "%string"), [ Func ((Null, s), []) ]) ->
    Printf.sprintf "\"%s\"" (escape_string_contents s)
  | Func ((Null, "%string"), [ content ]) -> string_of_ray content
  | Func (pf, terms) ->
    Printf.sprintf "(%s %s)" (string_of_polsym pf)
      (List.map terms ~f:string_of_ray |> String.concat ~sep:" ")

let string_of_subst substitution =
  substitution
  |> List.map ~f:(fun (var, ray) ->
    Printf.sprintf "%s->%s" (string_of_var var) (string_of_ray ray) )
  |> String.concat ~sep:", " |> Printf.sprintf "{%s}"

let string_of_ban = function
  | Ineq (b1, b2) ->
    Printf.sprintf "(!= %s %s)" (string_of_ray b1) (string_of_ray b2)
  | Incomp (b1, b2) ->
    Printf.sprintf "(slice %s %s)" (string_of_ray b1) (string_of_ray b2)

(* ---------------------------------------
   Display names for variables
   --------------------------------------- *)

(* A variable is a (name, index) pair, the index coming from the
   renamings the executor performs during fusion. Printing the pair as
   name ^ index leaks those indices and can even give two distinct
   variables the same name (("V1", 1) and ("V11", None) both read V11).
   Since variables are local to a star, a star can be printed with the
   names that were written in the source: each variable keeps its base
   name, and only a variable whose name is already taken by another one
   falls back to the indexed form. *)
let display_names (vars : StellarSig.idvar list) =
  let taken = ref [] in
  let is_taken name = List.mem !taken name ~equal:String.equal in
  let rec disambiguate candidate =
    if is_taken candidate then disambiguate (candidate ^ "'") else candidate
  in
  List.fold vars ~init:[] ~f:(fun assoc v ->
    if List.Assoc.mem assoc v ~equal:StellarSig.equal_idvar then assoc
    else begin
      let base, _ = v in
      let name =
        if is_taken base then disambiguate (string_of_var v) else base
      in
      taken := name :: !taken;
      (v, name) :: assoc
    end )

let rays_of_ban = function Ineq (r1, r2) | Incomp (r1, r2) -> [ r1; r2 ]

let map_ban ~f = function
  | Ineq (r1, r2) -> Ineq (f r1, f r2)
  | Incomp (r1, r2) -> Incomp (f r1, f r2)

let with_display_names (star : star) : star =
  let rays = star.content @ List.concat_map star.bans ~f:rays_of_ban in
  let assoc = display_names (List.concat_map rays ~f:StellarRays.vars) in
  let rename =
    StellarRays.map Fn.id (fun v ->
      match List.Assoc.find assoc v ~equal:StellarSig.equal_idvar with
      | Some name -> Var (name, None)
      | None -> Var v )
  in
  { content = List.map star.content ~f:rename
  ; bans = List.map star.bans ~f:(map_ban ~f:rename)
  }

(* Prints the (name, index) pairs verbatim. Everything user-facing goes
   through string_of_star / string_of_constellation instead. *)
let string_of_indexed_star star =
  match star.content with
  | [] -> "[]"
  | content ->
    let rays_str =
      List.map content ~f:string_of_ray |> String.concat ~sep:" "
    in
    let bans_str =
      if List.is_empty star.bans then ""
      else
        Printf.sprintf " || %s"
          (List.map star.bans ~f:string_of_ban |> String.concat ~sep:" ")
    in
    Printf.sprintf "[%s%s]" rays_str bans_str

let string_of_star star = string_of_indexed_star (with_display_names star)

let string_of_constellation cs =
  match List.map cs ~f:with_display_names with
  | [] -> "{}"
  | [ { content = [ single_ray ]; bans = _ } ] -> string_of_ray single_ray
  | [ single_star ] -> string_of_indexed_star single_star
  | head :: tail ->
    let max_line_length = 80 in
    let init_str = "{ " ^ string_of_indexed_star head ^ " " in
    let _, result_str, _ =
      List.fold_left tail
        ~init:(List.length tail, init_str, String.length init_str)
        ~f:(fun (remaining, acc, current_line_len) star ->
          let star_str = string_of_indexed_star star in
          let star_len = String.length star_str in
          let new_len = current_line_len + star_len in
          if remaining = 1 then (0, acc ^ star_str, 0)
          else if new_len < max_line_length then
            (remaining - 1, acc ^ star_str ^ " ", new_len)
          else (remaining - 1, acc ^ star_str ^ "...\n", 0) )
    in
    result_str ^ " }"
