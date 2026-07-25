open Base
open Constellation
open Syntax
open Expression_error

exception MacroError of expr_err * source_location option

let ( let* ) x f = Result.bind x ~f

type ident = string

(* Generic type for attaching source locations *)
type 'a loc =
  { content : 'a
  ; loc : source_location option
  }

module Raw = struct
  type t =
    | Symbol of string
    | Var of ident
    | GuardedVar of ident
    | String of string
    | Catalyst of t
    | Seed of t
    | Call of t
    | Static of t
    | List of t list
    | Group of t list
    | Cons of t list
    | ConsWithParams of t list * t list
    | ConsWithBase of t list * t
    | Positioned of t * Lexing.position * Lexing.position
end

type expr =
  | Symbol of string
  | Var of ident
  | List of expr loc list

let rec equal_expr e1 e2 =
  match (e1, e2) with
  | Symbol s1, Symbol s2 -> String.equal s1 s2
  | Var v1, Var v2 -> String.equal v1 v2
  | List l1, List l2 ->
    List.equal (fun a b -> equal_expr a.content b.content) l1 l2
  | _ -> false

let primitive = String.append "%"

let nil_op = primitive "nil"

let cons_op = primitive "cons"

let call_op = "#"

let catalyst_op = "*"

let seed_op = "@"

let guard_op = primitive "!"

let string_op = primitive "string"

let static_op = "\xc2\xa7" (* the section sign, written as U+00A7 *)

let def_op = "def"

let spec_op = "spec"

let object_op = "object"

let forall_op = "forall"

let expect_op = "=="

let match_op = "~="

let params_op = primitive "params"

let ineq_op = "!="

let incomp_op = "slice"

let group_op = "%group"

let rec to_string : expr -> string = function
  | Symbol s -> s
  | Var x -> x
  | List es ->
    Printf.sprintf "(%s)"
      (List.map ~f:(fun e -> to_string e.content) es |> String.concat ~sep:" ")

let rec expand_macro : Raw.t -> expr loc = function
  | Raw.Symbol s -> { content = Symbol s; loc = None }
  | Raw.Var x -> { content = Var x; loc = None }
  | Raw.GuardedVar x ->
    (* !X: a guarded variable occurrence, encoded as (%! X). Macro
       substitution reaches the variable inside, so a guard written on
       a macro parameter transfers to the argument. *)
    { content =
        List
          [ { content = Symbol guard_op; loc = None }
          ; { content = Var x; loc = None }
          ]
    ; loc = None
    }
  | Raw.String s ->
    { content =
        List
          [ { content = Symbol string_op; loc = None }
          ; { content = Symbol s; loc = None }
          ]
    ; loc = None
    }
  | Raw.Call e' ->
    let e = expand_macro e' in
    { content = List [ { content = Symbol call_op; loc = None }; e ]
    ; loc = None
    }
  | Raw.Catalyst e' ->
    let e = expand_macro e' in
    { content = List [ { content = Symbol catalyst_op; loc = None }; e ]
    ; loc = None
    }
  | Raw.Seed e' ->
    let e = expand_macro e' in
    { content = List [ { content = Symbol seed_op; loc = None }; e ]
    ; loc = None
    }
  | Raw.Static e' ->
    (* Safe encoding: the lexer owns the section sign, so users cannot
       forge a symbol with this name *)
    let e = expand_macro e' in
    { content = List [ { content = Symbol static_op; loc = None }; e ]
    ; loc = None
    }
  | Raw.Group es ->
    { content =
        List
          ( { content = Symbol group_op; loc = None }
          :: List.map ~f:expand_macro (List.rev es) )
    ; loc = None
    }
  | Raw.List es -> { content = List (List.map ~f:expand_macro es); loc = None }
  | Raw.Cons es -> expand_macro (Raw.ConsWithBase (es, Symbol nil_op))
  | Raw.ConsWithBase (es, base) ->
    List.fold_left es ~init:(expand_macro base) ~f:(fun acc e ->
      { content =
          List [ { content = Symbol cons_op; loc = None }; expand_macro e; acc ]
      ; loc = None
      } )
  | Raw.ConsWithParams (es, ps) ->
    { content =
        List
          [ { content = Symbol params_op; loc = None }
          ; expand_macro (Cons es)
          ; expand_macro (List ps)
          ]
    ; loc = None
    }
  | Raw.Positioned (e, start_pos, _) ->
    let source_loc =
      { filename = start_pos.Lexing.pos_fname
      ; line = start_pos.Lexing.pos_lnum
      ; column = start_pos.Lexing.pos_cnum - start_pos.Lexing.pos_bol + 1
      }
    in
    let expanded = expand_macro e in
    { expanded with loc = Some source_loc }

let rec replace_id (var_from : ident) replacement (expr : expr loc) : expr loc =
  match expr.content with
  | Var x when String.equal x var_from -> { replacement with loc = expr.loc }
  | Symbol _ | Var _ -> expr
  | List exprs ->
    { content = List (List.map exprs ~f:(replace_id var_from replacement))
    ; loc = expr.loc
    }

(* ---------------------------------------
   Macro Expansion Helpers
   --------------------------------------- *)

(* Find the pattern whose arity matches the call exactly *)
let find_matching_pattern
  (all_patterns : (string * (string list * expr loc list)) list)
  (arg_count : int) : (string list * expr loc list) option =
  List.find_map all_patterns ~f:(fun (_, ((params, _) as pattern)) ->
    if List.length params = arg_count then Some pattern else None )

(* Apply parameter -> argument substitution to an expression *)
let rec apply_substitution (subst_pairs : (string * expr loc) list)
  (e : expr loc) : expr loc =
  match e.content with
  | List subexprs ->
    { content = List (List.map subexprs ~f:(apply_substitution subst_pairs))
    ; loc = e.loc
    }
  | Var v -> (
    match List.Assoc.find subst_pairs v ~equal:String.equal with
    | Some replacement -> { replacement with loc = e.loc }
    | None -> e )
  | _ -> e

(* Macros are pure text substitution: the expanded code has no existence of
   its own, so it is attributed entirely to the call site, not to wherever
   the macro happens to be defined. Without this, tracing a call like
   `(:: e binary)` from a user's file would jump into the library file that
   defines `::`, since nodes deep inside the macro body still carry the
   locations they were parsed with there. *)
let rec set_loc_deep (loc : source_location option) (e : expr loc) : expr loc =
  match e.content with
  | List subexprs ->
    { content = List (List.map subexprs ~f:(set_loc_deep loc)); loc }
  | Symbol _ | Var _ -> { e with loc }

(* Expand a single matched macro: substitute params and recursively expand *)
let expand_matched_macro
  (macro_env : (string * (string list * expr loc list)) list)
  (expand_fn :
    (string * (string list * expr loc list)) list -> expr loc -> expr loc list
    ) (formal_params : string list) (body : expr loc list)
  (call_args : expr loc list) (call_loc : source_location option) :
  expr loc list =
  (* First, recursively expand macros in the arguments *)
  let expanded_args =
    List.map call_args ~f:(fun arg ->
      match expand_fn macro_env arg with
      | [ single ] -> single
      | multiple -> { content = List multiple; loc = arg.loc } )
  in
  (* Arity equality is guaranteed by find_matching_pattern *)
  let subst_pairs = List.zip_exn formal_params expanded_args in
  (* Apply substitution to body *)
  let substituted = List.map body ~f:(apply_substitution subst_pairs) in
  (* Recursively expand macros in the substituted body *)
  let expanded = List.concat_map substituted ~f:(expand_fn macro_env) in
  (* Attach the call site location to every node of the expansion *)
  List.map expanded ~f:(set_loc_deep call_loc)

(* Expand macros in a list of arguments, coalescing results *)
let expand_args_in_list
  (macro_env : (string * (string list * expr loc list)) list)
  (expand_fn :
    (string * (string list * expr loc list)) list -> expr loc -> expr loc list
    ) (args : expr loc list) : expr loc list =
  List.map args ~f:(fun arg ->
    match expand_fn macro_env arg with
    | [ single ] -> single
    | multiple -> { content = List multiple; loc = arg.loc } )

(* ---------------------------------------
   Main Macro Expansion
   --------------------------------------- *)

(* Recursively expand macros in an expression *)
let rec expand_macros_in_expr
  (macro_env : (string * (string list * expr loc list)) list) (expr : expr loc)
  : expr loc list =
  match expr.content with
  (* Macro definition - add to environment but don't emit *)
  | List
      ( { content = Symbol "macro"; _ }
      :: { content = List ({ content = Symbol _; _ } :: _); _ }
      :: _ ) ->
    []
  (* A §-marked macro definition must not be erased like a plain one:
     keep it intact so program conversion reports the error with its
     location *)
  | List
      [ { content = Symbol s; _ }
      ; { content = List ({ content = Symbol "macro"; _ } :: _); _ }
      ]
    when String.equal s static_op ->
    [ expr ]
  (* Macro call - expand and recursively process *)
  | List ({ content = Symbol macro_name; _ } :: call_args) -> (
    (* Find all patterns for this macro name *)
    let all_patterns =
      List.filter macro_env ~f:(fun (name, _) -> String.equal name macro_name)
    in
    let arg_count = List.length call_args in
    match find_matching_pattern all_patterns arg_count with
    | Some (formal_params, body) ->
      expand_matched_macro macro_env expand_macros_in_expr formal_params body
        call_args expr.loc
    | None ->
      (* Not a macro - recursively expand in sub-expressions *)
      let expanded_subexprs =
        expand_args_in_list macro_env expand_macros_in_expr call_args
      in
      [ { expr with
          content =
            List
              ( { content = Symbol macro_name; loc = expr.loc }
              :: expanded_subexprs )
        }
      ] )
  (* Regular list - recursively expand in sub-expressions *)
  | List subexprs ->
    let expanded_subexprs =
      expand_args_in_list macro_env expand_macros_in_expr subexprs
    in
    [ { expr with content = List expanded_subexprs } ]
  (* Atoms - no expansion needed *)
  | Symbol _ | Var _ -> [ expr ]

let unfold_decl_def (macro_env : (string * (string list * expr loc list)) list)
  exprs =
  (* First pass: collect macro definitions *)
  let env =
    List.fold_left exprs ~init:macro_env ~f:(fun acc (expr : expr loc) ->
      match expr.content with
      | List
          ( { content = Symbol "macro"; _ }
          :: { content = List ({ content = Symbol macro_name; _ } :: args); _ }
          :: body ) ->
        let var_args =
          List.map args ~f:(fun arg ->
            match arg.content with
            | Var x -> x
            | Symbol s ->
              raise
                (MacroError
                   ( InvalidMacroArgument
                       (Printf.sprintf
                          "macro argument '%s' must be a variable (start with \
                           uppercase)"
                          s )
                   , arg.loc ) )
            | List _ ->
              raise
                (MacroError
                   ( InvalidMacroArgument
                       "macro argument must be a variable, not a list"
                   , arg.loc ) ) )
        in
        (macro_name, (var_args, body)) :: acc
      | _ -> acc )
  in
  (* Second pass: expand macros recursively *)
  List.concat_map exprs ~f:(expand_macros_in_expr env)

(* ---------------------------------------
   Macro Import Mechanism
   --------------------------------------- *)

(* Type for macro environment *)
type macro_env = (string * (string list * expr loc list)) list

(* Collect the paths of all use directives from raw expressions.
   Imports are resolved twice: here, during preprocessing, to bring the
   imported file's macros into scope, and later at evaluation time where
   the same directive imports the file's definitions. *)
let collect_macro_imports (raw_exprs : Raw.t list) : string list =
  (* Static is stripped too: macro imports happen at preprocessing, before
     phases exist, so §(use ...) still brings macros into scope *)
  let rec strip = function
    | Raw.Positioned (inner, _, _) -> strip inner
    | Raw.Static inner -> strip inner
    | other -> other
  in
  List.concat_map raw_exprs ~f:(fun raw_expr ->
    match strip raw_expr with
    | Raw.List [ head; path ] -> (
      match (strip head, strip path) with
      | Raw.Symbol "use", Raw.String path | Raw.Symbol "use", Raw.Symbol path ->
        [ path ]
      | _ -> [] )
    | _ -> [] )

(* Extract macro definitions from a list of raw expressions *)
let extract_macros (raw_exprs : Raw.t list) : macro_env =
  let expanded = List.map raw_exprs ~f:expand_macro in
  (* We need to extract just the macro environment, not the expanded expressions *)
  let process_expr (env, acc) (expr : expr loc) =
    match expr.content with
    | List
        ( { content = Symbol "macro"; _ }
        :: { content = List ({ content = Symbol macro_name; _ } :: args); _ }
        :: body ) ->
      let var_args =
        List.map args ~f:(fun arg ->
          match arg.content with
          | Var x -> x
          | Symbol s ->
            raise
              (MacroError
                 ( InvalidMacroArgument
                     (Printf.sprintf
                        "macro argument '%s' must be a variable (start with \
                         uppercase)"
                        s )
                 , arg.loc ) )
          | List _ ->
            raise
              (MacroError
                 ( InvalidMacroArgument
                     "macro argument must be a variable, not a list"
                 , arg.loc ) ) )
      in
      ((macro_name, (var_args, body)) :: env, acc)
    | _ -> (env, acc)
  in
  List.fold_left expanded ~init:([], []) ~f:(fun (env, acc) e ->
    process_expr (env, acc) e )
  |> fst

(* Preprocess with a given macro environment. Use directives are kept:
   the evaluator needs them to import definitions. *)
let preprocess_with_macro_env (macro_env : macro_env) (raw_exprs : Raw.t list) :
  expr loc list =
  raw_exprs |> List.map ~f:expand_macro |> unfold_decl_def macro_env

(* ---------------------------------------
   Constellation of Expr
   --------------------------------------- *)

let symbol_of_str (symbol : string) : idfunc =
  match String.get symbol 0 with
  | '+' -> (Pos, String.subo symbol ~pos:1)
  | '-' -> (Neg, String.subo symbol ~pos:1)
  | _ -> (Null, symbol)

let rec ray_of_expr : expr -> (ray, expr_err) Result.t = function
  | Symbol s -> to_func (symbol_of_str s, []) |> Result.return
  | Var "_" -> to_var ("_" ^ fresh_placeholder ()) |> Result.return
  | Var s -> to_var s |> Result.return
  | List [] -> Error EmptyRay
  | List ({ content = Symbol h; _ } :: _) as e when String.equal h static_op ->
    (* Without this case a nested § would be silently absorbed into a
       function term *)
    Error (MisplacedStatic (to_string e))
  | List ({ content = Symbol h; _ } :: t) ->
    let* args = List.map ~f:(fun e -> ray_of_expr e.content) t |> Result.all in
    to_func (symbol_of_str h, args) |> Result.return
  | List (_ :: _) as e -> Error (NonConstantRayHeader (to_string e))

let bans_of_expr ban_exprs : (ban list, expr_err) Result.t =
  let ban_of_expr = function
    | List [ { content = Symbol op; _ }; expr1; expr2 ]
      when String.equal op ineq_op ->
      let* ray1 = ray_of_expr expr1.content in
      let* ray2 = ray_of_expr expr2.content in
      Ineq (ray1, ray2) |> Result.return
    | List [ { content = Symbol op; _ }; expr1; expr2 ]
      when String.equal op incomp_op ->
      let* ray1 = ray_of_expr expr1.content in
      let* ray2 = ray_of_expr expr2.content in
      Incomp (ray1, ray2) |> Result.return
    | invalid_expr -> Error (InvalidBan (to_string invalid_expr))
  in
  List.map ban_exprs ~f:(fun e -> ban_of_expr e.content) |> Result.all

(* Helper to parse bans from a single expr containing a list *)
let bans_of_expr_list (bans_list_expr : expr) : (ban list, expr_err) Result.t =
  match bans_list_expr with
  | List ban_exprs -> bans_of_expr ban_exprs
  | _ -> Error (InvalidBan (to_string bans_list_expr))

(* Convert a ban list to a term structure for %params *)
let bans_list_to_term (bans : ban list) : ray =
  let ban_to_term = function
    | Ineq (r1, r2) -> func "!=" [ r1; r2 ]
    | Incomp (r1, r2) -> func "slice" [ r1; r2 ]
  in
  List.fold_right bans ~init:(func "%nil" []) ~f:(fun b acc ->
    func "%cons" [ ban_to_term b; acc ] )

let rec raylist_of_expr expr : (ray list, expr_err) Result.t =
  match expr with
  | Symbol k when String.equal k nil_op -> Ok []
  | Symbol _ | Var _ ->
    let* ray = ray_of_expr expr in
    Ok [ ray ]
  | List [ { content = Symbol op; _ }; head; tail ] when String.equal op cons_op
    ->
    let* head_ray = ray_of_expr head.content in
    let* tail_rays = raylist_of_expr tail.content in
    Ok (head_ray :: tail_rays)
  | invalid -> Error (InvalidRaylist (to_string invalid))

let rec star_of_expr : expr -> (Marked.star, expr_err) Result.t = function
  | List [ { content = Symbol k; _ }; s ] when equal_string k catalyst_op ->
    let* ss = star_of_expr s.content in
    ss |> Marked.make_catalyst |> Result.return
  | List [ { content = Symbol k; _ }; s ] when equal_string k seed_op ->
    let* ss = star_of_expr s.content in
    ss |> Marked.make_seed |> Result.return
  | List [ { content = Symbol k; _ }; s; { content = List ps; _ } ]
    when equal_string k params_op ->
    let* content = raylist_of_expr s.content in
    let* bans = bans_of_expr ps in
    Marked.Reactive { content; bans } |> Result.return
  | e ->
    let* content = raylist_of_expr e in
    Marked.Reactive { content; bans = [] } |> Result.return

let rec constellation_of_expr :
  expr -> (Marked.constellation, expr_err) Result.t = function
  | Symbol s ->
    [ Marked.Reactive { content = [ var (s, None) ]; bans = [] } ]
    |> Result.return
  | Var x ->
    [ Marked.Reactive { content = [ var (x, None) ]; bans = [] } ]
    |> Result.return
  | List [ { content = Symbol s; _ }; h; t ] when equal_string s cons_op ->
    let* sh = star_of_expr h.content in
    let* ct = constellation_of_expr t.content in
    Ok (sh :: ct)
  | List g ->
    let* rg = ray_of_expr (List g) in
    [ Marked.Reactive { content = [ rg ]; bans = [] } ] |> Result.return

(* ---------------------------------------
   Stellogen expr of Expr
   --------------------------------------- *)

(* The parser attaches a real source position to every parsed expr node,
   not just top-level declarations (see the `expr` rule in parser.mly), so
   [expr.loc] is normally already the right line - e.g. a `then` pipeline
   (each stage its own nested `exec`) or an inline `exec` reports
   the line it is actually running, not the location of the whole
   enclosing form. Synthetic nodes (introduced by macro expansion) can
   still be born with loc = None, so each node falls back to the nearest
   enclosing location this recursion has already resolved. *)
let rec sgen_expr_of_expr ?(enclosing_loc : source_location option = None)
  (expr : expr loc) : (sgen_expr, expr_err * source_location option) Result.t =
  let loc = match expr.loc with Some _ -> expr.loc | None -> enclosing_loc in
  let wrap_error result = Result.map_error result ~f:(fun err -> (err, loc)) in
  let recur e = sgen_expr_of_expr ~enclosing_loc:loc e in
  match expr.content with
  (* § below top level: program_of_expr strips the marker of top-level
     items before conversion, so reaching one here is an error *)
  | List ({ content = Symbol op; _ } :: _) when String.equal op static_op ->
    Error (MisplacedStatic (to_string expr.content), loc)
  | List [ { content = Symbol op; _ }; arg ] when String.equal op call_op ->
    let* ray = ray_of_expr arg.content |> wrap_error in
    Call (ray, loc) |> Result.return
  | List [ { content = Symbol op; _ }; arg ] when String.equal op catalyst_op ->
    let* sgen_expr = recur arg in
    Catalyst sgen_expr |> Result.return
  | List [ { content = Symbol op; _ }; arg ] when String.equal op seed_op ->
    let* sgen_expr = recur arg in
    Seed sgen_expr |> Result.return
  | List [ { content = Symbol op; _ }; rays_expr; bans_expr ]
    when String.equal op params_op ->
    (* (params rays_list bans_list) → create %params term structure *)
    let* rays_term = ray_of_expr rays_expr.content |> wrap_error in
    let* bans_list = bans_of_expr_list bans_expr.content |> wrap_error in
    let bans_term = bans_list_to_term bans_list in
    Raw (func "%params" [ rays_term; bans_term ]) |> Result.return
  | List ({ content = Symbol op; _ } :: args) when String.equal op group_op ->
    (* {a b c} → Group [a; b; c] *)
    let* sgen_exprs = List.map args ~f:recur |> Result.all in
    Group sgen_exprs |> Result.return
  | List ({ content = Symbol "exec"; _ } :: args) ->
    let* sgen_exprs = List.map args ~f:recur |> Result.all in
    let combined =
      match sgen_exprs with [ single ] -> single | multiple -> Group multiple
    in
    Exec (combined, loc) |> Result.return
  | List ({ content = Symbol "then"; _ } :: first :: rest) ->
    (* (then c1 c2 ... cn): staged execution. Left fold where each step
       executes against the previous result: (then a b) = (exec b a).
       An exec result is reactive, so it feeds the next stage without
       any refocusing. Each stage keeps its own location (the line of
       that stage's expression), not the location of the whole `then`
       form, so tracing a pipeline shows progress line by line. *)
    let* first_expr = recur first in
    let* step_exprs =
      List.map rest ~f:(fun step ->
        let* step_expr = recur step in
        let step_loc = match step.loc with Some _ -> step.loc | None -> loc in
        Result.return (step_loc, step_expr) )
      |> Result.all
    in
    List.fold_left step_exprs ~init:first_expr ~f:(fun acc (step_loc, step) ->
      Exec (Group [ step; acc ], step_loc) )
    |> Result.return
  | List [ { content = Symbol op; _ }; expr1; expr2 ]
    when String.equal op expect_op ->
    let* sgen_expr1 = recur expr1 in
    let* sgen_expr2 = recur expr2 in
    Expect (sgen_expr1, sgen_expr2, const "default", loc) |> Result.return
  | List [ { content = Symbol op; _ }; expr1; expr2; message ]
    when String.equal op expect_op ->
    let* sgen_expr1 = recur expr1 in
    let* sgen_expr2 = recur expr2 in
    let* message_ray = ray_of_expr message.content |> wrap_error in
    Expect (sgen_expr1, sgen_expr2, message_ray, loc) |> Result.return
  | List [ { content = Symbol op; _ }; expr1; expr2 ]
    when String.equal op match_op ->
    let* sgen_expr1 = recur expr1 in
    let* sgen_expr2 = recur expr2 in
    Match (sgen_expr1, sgen_expr2, const "default", loc) |> Result.return
  | List [ { content = Symbol op; _ }; expr1; expr2; message ]
    when String.equal op match_op ->
    let* sgen_expr1 = recur expr1 in
    let* sgen_expr2 = recur expr2 in
    let* message_ray = ray_of_expr message.content |> wrap_error in
    Match (sgen_expr1, sgen_expr2, message_ray, loc) |> Result.return
  | List ({ content = Symbol op; _ } :: identifier :: values)
    when ( String.equal op def_op || String.equal op spec_op
         || String.equal op object_op )
         && not (List.is_empty values) ->
    let* id_ray = ray_of_expr identifier.content |> wrap_error in
    let* value_exprs =
      match values with
      | [ single ] ->
        let* v = recur single in
        Ok [ v ]
      | multiple ->
        let* sgen_exprs = List.map multiple ~f:recur |> Result.all in
        let all_groups =
          List.for_all sgen_exprs ~f:(fun e ->
            match e with Group _ -> true | _ -> false )
        in
        if all_groups then Ok sgen_exprs else Ok [ Group sgen_exprs ]
    in
    Def (id_ray, value_exprs) |> Result.return
  | List
      [ { content = Symbol op; _ }
      ; galaxy_expr
      ; { content = Var bind_var; _ }
      ; body
      ]
    when String.equal op forall_op ->
    let* galaxy_id = ray_of_expr galaxy_expr.content |> wrap_error in
    let bind_id = const bind_var in
    let* body_expr = recur body in
    Forall (galaxy_id, bind_id, body_expr, loc) |> Result.return
  | List ({ content = Symbol "show"; _ } :: args) when List.length args > 0 ->
    let* sgen_exprs = List.map args ~f:recur |> Result.all in
    Show (sgen_exprs, loc) |> Result.return
  | List [ { content = Symbol "use"; _ }; path ] ->
    let* path_ray = ray_of_expr path.content |> wrap_error in
    Use (path_ray, loc) |> Result.return
  | _ ->
    (* Everything else is a raw term *)
    let* ray = ray_of_expr expr.content |> wrap_error in
    Raw ray |> Result.return

(* ---------------------------------------
   Stellogen program of Expr
   --------------------------------------- *)

(* Assign each top-level item to a phase. The § marker is stripped here,
   after macro expansion, so a macro whose expansion is §(...) satisfies
   the top-level rule while a nested § stays an error. *)
let classify_item (expr : expr loc) :
  (item_phase * sgen_expr, expr_err * source_location option) Result.t =
  let is_head_list keyword (e : expr loc) =
    match e.content with
    | List ({ content = Symbol h; _ } :: _) -> String.equal h keyword
    | _ -> false
  in
  match expr.content with
  | List [ { content = Symbol op; _ }; payload ] when String.equal op static_op
    ->
    if is_head_list object_op payload then Error (StaticOnObject, expr.loc)
    else if is_head_list "macro" payload then Error (StaticOnMacro, expr.loc)
    else
      let payload =
        match payload.loc with
        | Some _ -> payload
        | None -> { payload with loc = expr.loc }
      in
      let* sgen = sgen_expr_of_expr payload in
      Ok (CheckOnly, sgen)
  | List ({ content = Symbol h; _ } :: _) when String.equal h object_op ->
    let* sgen = sgen_expr_of_expr expr in
    Ok (Shared, sgen)
  | List ({ content = Symbol h; _ } :: _) when String.equal h spec_op ->
    (* spec marks a test suite / type: it belongs to the check phase by
       nature, so it is CheckOnly without needing a § marker. *)
    let* sgen = sgen_expr_of_expr expr in
    Ok (CheckOnly, sgen)
  | List [ { content = Symbol h; _ }; _ ] when String.equal h "use" ->
    (* Imports run in both phases; the imported file's items
       self-classify under the active phase *)
    let* sgen = sgen_expr_of_expr expr in
    Ok (Shared, sgen)
  | _ ->
    let* sgen = sgen_expr_of_expr expr in
    Ok (RunOnly, sgen)

let program_of_expr e = List.map ~f:classify_item e |> Result.all

let preprocess e = e |> List.map ~f:expand_macro |> unfold_decl_def []
