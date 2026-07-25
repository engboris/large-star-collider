open Base
open Stdio
open Constellation
open Pretty
open Syntax
open Expression_error

exception EvalError of expr_err * source_location option

let ( let* ) x f = Result.bind x ~f

let unifiable r r' = StellarRays.solution [ (r, r') ] |> Option.is_some

(* Conversion between terms and constellations *)
let group_sym = (Null, "%group")

let cons_sym = (Null, "%cons")

let nil_sym = (Null, "%nil")

let catalyst_sym = (Null, "*")

let seed_sym = (Null, "@")

let params_sym = (Null, "%params")

let galaxy_sym = (Null, "%galaxy")

let nil_term = StellarRays.Func (nil_sym, [])

(* Where show writes its output. The CLI keeps the default stdout;
   the web playground redirects this to its output buffer. *)
let show_printer : (string -> unit) ref =
  ref (fun output ->
    Stdlib.print_endline output;
    Stdlib.flush Stdlib.stdout )

(* Extract individual constellation terms from a galaxy term.
   Non-galaxy terms are treated as singleton galaxies. *)
let constellations_of_galaxy (t : StellarRays.term) : StellarRays.term list =
  match t with Func ((Null, "%galaxy"), terms) -> terms | other -> [ other ]

(* Convert a constellation to a term using %group *)
let term_of_constellation (c : Marked.constellation) : StellarRays.term =
  let open StellarRays in
  let rec star_to_term (s : Marked.star) : term =
    let content_term = star_content_to_term (Marked.remove s) in
    match s with
    | Reactive _ -> content_term
    | Catalyst _ -> Func (catalyst_sym, [ content_term ])
    | Seed _ -> Func (seed_sym, [ content_term ])
  and star_content_to_term (s : Raw.star) : term =
    let rays_term = rays_to_term s.content in
    if List.is_empty s.bans then rays_term
    else
      let bans_term = bans_to_term s.bans in
      Func (params_sym, [ rays_term; bans_term ])
  and rays_to_term (rays : ray list) : term =
    List.fold_right rays
      ~init:(Func (nil_sym, []))
      ~f:(fun r acc -> Func (cons_sym, [ r; acc ]))
  and bans_to_term (bans : ban list) : term =
    let ban_to_term = function
      | Ineq (r1, r2) -> Func ((Null, "!="), [ r1; r2 ])
      | Incomp (r1, r2) -> Func ((Null, "slice"), [ r1; r2 ])
    in
    List.fold_right bans
      ~init:(Func (nil_sym, []))
      ~f:(fun b acc -> Func (cons_sym, [ ban_to_term b; acc ]))
  in
  (* Don't wrap single stars in %group *)
  match c with
  | [ single ] -> star_to_term single
  | multiple -> Func (group_sym, List.map ~f:star_to_term multiple)

(* Convert a term to a constellation - interprets %group and %cons structures *)
let rec constellation_of_term (t : StellarRays.term) : Marked.constellation =
  let open StellarRays in
  match t with
  | Func ((Null, "%galaxy"), consts) ->
    List.concat_map ~f:constellation_of_term consts
  | Func ((Null, "%group"), stars) ->
    List.concat_map ~f:constellation_of_term stars
  | Func ((Null, "%cons"), [ star; rest ]) when is_star_term star ->
    (* %cons at constellation level: list of stars *)
    constellation_of_term star @ constellation_of_term rest
  | Func ((Null, "%nil"), []) -> []
  | Func ((Null, "*"), [ inner ]) ->
    constellation_of_term inner |> Marked.make_catalyst_all
  | Func ((Null, "@"), [ inner ]) ->
    constellation_of_term inner |> Marked.make_seed_all
  | Func ((Null, "%params"), [ rays_term; bans_term ]) ->
    let rays = rays_of_term rays_term in
    let bans = bans_of_term bans_term in
    [ Reactive { content = rays; bans } ]
  | other ->
    (* Check if this looks like a %cons list of rays (star representation) *)
    if is_cons_list other then
      let rays = rays_of_term other in
      (* Special case: if the ONLY ray is a %group, unpack it instead of keeping as a ray *)
      match rays with
      | [ (Func ((Null, "%group"), _) as group) ] ->
        (* Single nested group - unpack it *)
        constellation_of_term group
      | _ ->
        (* Multiple rays or non-group rays - create a star *)
        [ Reactive { content = rays; bans = [] } ]
    else
      (* Single ray treated as a single-ray reactive star *)
      [ Reactive { content = [ other ]; bans = [] } ]

(* Check if a term is a cons list (%cons _ _) or %nil *)
and is_cons_list = function
  | Func ((Null, "%cons"), _) -> true
  | Func ((Null, "%nil"), []) -> true
  | _ -> false

(* Check if a term looks like a star (either a * catalyst, %params, or cons
   list) *)
and is_star_term = function
  | Func ((Null, "*"), _) -> true
  | Func ((Null, "%params"), _) -> true
  | Func ((Null, "%cons"), _) -> true
  | Func ((Null, "%nil"), _) -> true
  | _ -> false

and rays_of_term (t : StellarRays.term) : ray list =
  let open StellarRays in
  match t with
  | Func ((Null, "%cons"), [ ray; rest ]) -> ray :: rays_of_term rest
  | Func ((Null, "%nil"), []) -> []
  | other -> [ other ]

and bans_of_term (t : StellarRays.term) : ban list =
  let open StellarRays in
  match t with
  | Func ((Null, "%cons"), [ ban; rest ]) ->
    ban_of_term ban :: bans_of_term rest
  | Func ((Null, "%nil"), []) -> []
  | _ -> []

and ban_of_term (t : StellarRays.term) : ban =
  let open StellarRays in
  match t with
  | Func ((Null, "!="), [ r1; r2 ]) -> Ineq (r1, r2)
  | Func ((Null, "slice"), [ r1; r2 ]) -> Incomp (r1, r2)
  | _ ->
    raise
      (EvalError
         ( InvalidBanStructure
             (Printf.sprintf "expected '!=' or 'slice' constraint, got: %s"
                (string_of_ray t) )
         , None ) )

let constellations_matchable c1 c2 =
  (* Check if two constellations are matchable for Match (~=) *)
  (* Uses term unification (ignoring polarity, only checking function name equality) *)
  let open Constellation in
  (* Extract all rays from both constellations *)
  let rays_from_constellation c =
    List.concat_map c ~f:(fun (star : Raw.star) -> star.content)
  in
  let rays1 = rays_from_constellation c1 in
  let rays2 = rays_from_constellation c2 in

  (* Check if any ray from c1 can unify with any ray from c2 (ignoring polarity) *)
  List.exists rays1 ~f:(fun r1 ->
    List.exists rays2 ~f:(fun r2 -> terms_unifiable r1 r2) )

let rec find_with_solution env x =
  let rec search_objs = function
    | [] -> None
    | (key, value) :: rest -> (
      let key_normalized = replace_indices 0 key in
      let value_normalized = map_ray env ~f:(replace_indices 0) value in
      let x_normalized = replace_indices 1 x in
      match StellarRays.solution [ (key_normalized, x_normalized) ] with
      | Some substitution ->
        (* Only use renamed value if there's actual parameter substitution *)
        let result_value =
          if List.is_empty substitution then value else value_normalized
        in
        Some (result_value, substitution)
      | None -> search_objs rest )
  in
  search_objs env.objs

and add_obj env key expr = List.Assoc.add ~equal:unifiable env.objs key expr

and get_obj env identifier = find_with_solution env identifier

and map_term_ray ~(f : ray -> ray) (t : StellarRays.term) : StellarRays.term =
  let open StellarRays in
  let rec map_t = function
    | Var x -> f (Var x)
    | Func (pf, ts) ->
      let mapped_args = List.map ~f:map_t ts in
      f (Func (pf, mapped_args))
  in
  map_t t

and map_ray env ~f : sgen_expr -> sgen_expr = function
  | Raw t -> Raw (map_term_ray ~f t)
  | Call (x, loc) -> Call (f x, loc)
  | Exec (e, loc) ->
    let map_e = map_ray env ~f e in
    Exec (map_e, loc)
  | Group es ->
    let map_es = List.map ~f:(map_ray env ~f) es in
    Group map_es
  | Catalyst e ->
    let map_e = map_ray env ~f e in
    Catalyst map_e
  | Seed e ->
    let map_e = map_ray env ~f e in
    Seed map_e
  | Def (id, es) -> Def (f id, List.map ~f:(map_ray env ~f) es)
  | Forall (gid, bind, body, loc) ->
    Forall (f gid, f bind, map_ray env ~f body, loc)
  | Show (exprs, loc) -> Show (List.map ~f:(map_ray env ~f) exprs, loc)
  | Expect (e1, e2, msg, loc) ->
    Expect (map_ray env ~f e1, map_ray env ~f e2, f msg, loc)
  | Match (e1, e2, msg, loc) ->
    Match (map_ray env ~f e1, map_ray env ~f e2, f msg, loc)
  | Use (id, loc) -> Use (f id, loc)

let trace_of_err : err -> frame list = function
  | ExpectError { trace; _ } -> trace
  | MatchError { trace; _ } -> trace
  | UnknownID (_, _, trace) -> trace
  | WrongPhaseID (_, _, _, trace) -> trace
  | ExprError (_, _, trace) -> trace

(* Render the chain of #calls that were unwound to reach where the error
   originated, outermost call first. Empty when the error surfaced without
   passing through any named call (e.g. a bare top-level ==). *)
let format_trace (trace : frame list) : string =
  let to_terminal_loc (loc : source_location) : Terminal.location =
    { Terminal.filename = loc.filename; line = loc.line; column = loc.column }
  in
  List.map trace ~f:(fun { called; location } ->
    Terminal.format_trace_line ~called:(string_of_ray called)
      ~location:(Option.map location ~f:to_terminal_loc) )
  |> String.concat ~sep:""

let pp_err error : (string, err) Result.t =
  (* Convert internal location to Terminal.location *)
  let to_terminal_loc (loc : source_location) : Terminal.location =
    { Terminal.filename = loc.filename; line = loc.line; column = loc.column }
  in

  let open Constellation.StellarRays in
  let message =
    match error with
    | ExpectError { got; expected; message = Func ((Null, f), []); location; _ }
      when String.equal f "default" ->
      let expected_str =
        expected |> Marked.remove_all |> string_of_constellation
      in
      let got_str = got |> Marked.remove_all |> string_of_constellation in
      Terminal.format_comparison_error ~message:"assertion failed"
        ~location:(Option.map location ~f:to_terminal_loc)
        ~label1:"Expected" ~value1:expected_str ~label2:"     Got"
        ~value2:got_str
    | ExpectError { message = Func ((Null, f), [ term ]); location; _ }
      when String.equal f "error" ->
      Terminal.format_error_at_location_opt ~message:(string_of_ray term)
        ~location:(Option.map location ~f:to_terminal_loc)
        ~hint:None
    | ExpectError { message; location; _ } ->
      Terminal.format_error_at_location_opt ~message:(string_of_ray message)
        ~location:(Option.map location ~f:to_terminal_loc)
        ~hint:None
    | MatchError { term1; term2; message = Func ((Null, f), []); location; _ }
      when String.equal f "default" ->
      let term1_str = term1 |> Marked.remove_all |> string_of_constellation in
      let term2_str = term2 |> Marked.remove_all |> string_of_constellation in
      Terminal.format_comparison_error ~message:"unification failed"
        ~location:(Option.map location ~f:to_terminal_loc)
        ~label1:"Term 1" ~value1:term1_str ~label2:"Term 2" ~value2:term2_str
    | MatchError { message; location; _ } ->
      Terminal.format_error_at_location_opt ~message:(string_of_ray message)
        ~location:(Option.map location ~f:to_terminal_loc)
        ~hint:None
    | UnknownID (identifier, location, _) ->
      let hint =
        Some (Printf.sprintf "The identifier '%s' was not defined." identifier)
      in
      Terminal.format_error_at_location_opt ~message:"identifier not found"
        ~location:(Option.map location ~f:to_terminal_loc)
        ~hint
    | WrongPhaseID (identifier, active_phase, location, _) ->
      let this_phase, other_phase =
        match active_phase with
        | Check -> ("check", "run")
        | Run -> ("run", "check")
      in
      let hint =
        Some
          (Printf.sprintf
             "'%s' is defined in the %s phase but referenced from a %s-phase \
              expression."
             identifier other_phase this_phase )
      in
      Terminal.format_error_at_location_opt
        ~message:"identifier not visible in this phase"
        ~location:(Option.map location ~f:to_terminal_loc)
        ~hint
    | ExprError (expr_error, location, _) ->
      let error_msg, hint =
        match expr_error with
        | EmptyRay ->
          ("rays cannot be empty", "Remove the empty ray or add content to it.")
        | NonConstantRayHeader expr ->
          ( Printf.sprintf "ray '%s' must start with a constant function symbol"
              expr
          , "Rays must begin with a function symbol, not a variable." )
        | InvalidBan expr ->
          ( Printf.sprintf "invalid ban expression '%s'" expr
          , "Ban expressions must use != or 'slice'." )
        | InvalidRaylist expr ->
          ( Printf.sprintf "expression '%s' is not a valid star" expr
          , "Check the syntax of your star expression." )
        | InvalidDeclaration expr ->
          ( Printf.sprintf "expression '%s' is not a valid declaration" expr
          , "Declarations must use def, show, ==, or use." )
        | InvalidMacroArgument msg ->
          ( Printf.sprintf "invalid macro argument: %s" msg
          , "Macro arguments must be variables (start with uppercase)." )
        | InvalidBanStructure msg ->
          ( Printf.sprintf "invalid ban structure: %s" msg
          , "Ban expressions must use != or 'slice' with two arguments." )
        | MisplacedStatic expr ->
          ( Printf.sprintf "misplaced '\xc2\xa7' in '%s'" expr
          , "The '\xc2\xa7' marker can only prefix a whole top-level \
             expression." )
        | StaticOnObject ->
          ( "'\xc2\xa7' cannot be applied to an object definition"
          , "Objects are shared between both phases; remove the marker." )
        | StaticOnMacro ->
          ( "'\xc2\xa7' cannot be applied to a macro definition"
          , "Macros are expanded before phases exist; remove the marker." )
        | CircularImport path ->
          ( Printf.sprintf "circular import detected: %s" path
          , "Check your import chain for cycles." )
        | FileLoadError { filename; message } ->
          ( Printf.sprintf "failed to load file '%s': %s" filename message
          , "Check that the file exists and is readable." )
      in
      Terminal.format_error_at_location_opt ~message:error_msg
        ~location:(Option.map location ~f:to_terminal_loc)
        ~hint:(Some hint)
  in
  message ^ format_trace (trace_of_err error) |> Result.return

(* Back-fill a missing error location, e.g. so a failure inside a `forall`
   body (whose own location is lost during macro expansion) is reported at
   the `forall`/`::` call site instead of as <unknown location>. *)
let fill_error_location (loc : source_location) : err -> err = function
  | ExpectError ({ location = None; _ } as r) ->
    ExpectError { r with location = Some loc }
  | MatchError ({ location = None; _ } as r) ->
    MatchError { r with location = Some loc }
  | UnknownID (id, None, trace) -> UnknownID (id, Some loc, trace)
  | WrongPhaseID (id, p, None, trace) -> WrongPhaseID (id, p, Some loc, trace)
  | ExprError (e, None, trace) -> ExprError (e, Some loc, trace)
  | other -> other

(* Prepend the frame for a #call that's about to be unwound, so an error
   originating deeper in the call chain carries the path that reached it. *)
let push_frame (frame : frame) : err -> err = function
  | ExpectError r -> ExpectError { r with trace = frame :: r.trace }
  | MatchError r -> MatchError { r with trace = frame :: r.trace }
  | UnknownID (id, loc, trace) -> UnknownID (id, loc, frame :: trace)
  | WrongPhaseID (id, p, loc, trace) -> WrongPhaseID (id, p, loc, frame :: trace)
  | ExprError (e, loc, trace) -> ExprError (e, loc, frame :: trace)

let phase_active (active : phase) (item : item_phase) : bool =
  match (item, active) with
  | Shared, _ -> true
  | CheckOnly, Check | RunOnly, Run -> true
  | CheckOnly, Run | RunOnly, Check -> false

(* Names bound by a skipped item, recorded for the phase-aware
   unknown-identifier diagnostic. The values are never evaluated. *)
let rec skipped_def_names : sgen_expr -> ident list = function
  | Def (id, _) -> [ id ]
  | Group es -> List.concat_map es ~f:skipped_def_names
  | _ -> []

let rec eval_sgen_expr ?(trace_cfg : Tracer.trace_config option = None)
  ?(phase = Run) (env : env) :
  sgen_expr -> (env * StellarRays.term, err) Result.t = function
  | Raw t -> Ok (env, t)
  | Call (x, location) ->
    begin match get_obj env x with
    | None ->
      if List.exists env.skipped ~f:(fun key -> unifiable key x) then
        Error (WrongPhaseID (string_of_ray x, phase, location, []))
      else Error (UnknownID (string_of_ray x, location, []))
    | Some (g, subst) ->
      let result =
        List.fold_result subst ~init:g ~f:(fun g_acc (xfrom, xto) ->
          map_ray env ~f:(StellarRays.subst [ (xfrom, xto) ]) g_acc
          |> Result.return )
      in
      Result.bind result ~f:(eval_sgen_expr ~trace_cfg ~phase env)
      |> Result.map_error ~f:(push_frame { called = x; location })
    end
  | Group es ->
    (* Evaluate each expression and combine the resulting terms into a %group *)
    let* env', eval_terms =
      List.fold_left es
        ~init:(Ok (env, []))
        ~f:(fun acc e ->
          let* env_acc, results = acc in
          let* env_new, result = eval_sgen_expr ~trace_cfg ~phase env_acc e in
          Ok (env_new, result :: results) )
    in
    Ok (env', func "%group" (List.rev eval_terms))
  | Exec (e, loc) ->
    let* env', eval_e = eval_sgen_expr ~trace_cfg ~phase env e in
    let eval_constellation = constellation_of_term eval_e in
    (* Set location in trace config if available *)
    ( match (trace_cfg, loc) with
    | Some cfg, Some location ->
      let lsc_loc =
        { Tracer.filename = location.filename
        ; line = location.line
        ; column = location.column
        }
      in
      Tracer.set_trace_location cfg (Some lsc_loc)
    | _ -> () );
    let result_constellation =
      Tracer.exec ~trace:trace_cfg eval_constellation
      |> Marked.make_reactive_all
    in
    Ok (env', term_of_constellation result_constellation)
  | Catalyst e ->
    let* env', eval_e = eval_sgen_expr ~trace_cfg ~phase env e in
    let catalyst_constellation =
      constellation_of_term eval_e |> Marked.make_catalyst_all
    in
    Ok (env', term_of_constellation catalyst_constellation)
  | Seed e ->
    let* env', eval_e = eval_sgen_expr ~trace_cfg ~phase env e in
    let seed_constellation =
      constellation_of_term eval_e |> Marked.make_seed_all
    in
    Ok (env', term_of_constellation seed_constellation)
  | Def (identifier, exprs) -> (
    match exprs with
    | [ single ] ->
      Ok ({ env with objs = add_obj env identifier single }, nil_term)
    | multiple ->
      (* Multiple expressions = galaxy: evaluate each, wrap in %galaxy *)
      let* env', eval_terms =
        List.fold_left multiple
          ~init:(Ok (env, []))
          ~f:(fun acc e ->
            let* env_acc, results = acc in
            let* env_new, result = eval_sgen_expr ~trace_cfg ~phase env_acc e in
            Ok (env_new, result :: results) )
      in
      let galaxy_term = StellarRays.Func (galaxy_sym, List.rev eval_terms) in
      Ok
        ( { env' with objs = add_obj env' identifier (Raw galaxy_term) }
        , nil_term ) )
  | Forall (galaxy_id, bind_var, body, location) ->
    let* _, galaxy_term =
      eval_sgen_expr ~trace_cfg ~phase env (Call (galaxy_id, location))
    in
    let constellation_terms = constellations_of_galaxy galaxy_term in
    List.fold_left constellation_terms
      ~init:(Ok (env, nil_term))
      ~f:(fun acc const_term ->
        let* env_acc, _ = acc in
        let local_env =
          { env_acc with objs = add_obj env_acc bind_var (Raw const_term) }
        in
        let* _, _ =
          eval_sgen_expr ~trace_cfg ~phase local_env body
          |> Result.map_error ~f:(fun err ->
            match location with
            | Some loc -> fill_error_location loc err
            | None -> err )
        in
        Ok (env_acc, nil_term) )
  | Show (exprs, show_loc) ->
    (* Evaluate all expressions and collect results *)
    let rec eval_all env_acc results = function
      | [] ->
        (* Print all results separated by spaces *)
        let output =
          List.rev results
          |> List.map ~f:(fun evaluated ->
            constellation_of_term evaluated
            |> List.map ~f:Marked.remove |> string_of_constellation )
          |> String.concat ~sep:" "
        in
        !show_printer output;
        Ok (env_acc, nil_term)
      | expr :: rest ->
        (* Propagate location to inner expr if it doesn't have one *)
        let expr_with_loc =
          match expr with
          | Exec (e, None) -> Exec (e, show_loc)
          | other -> other
        in
        let* env', evaluated =
          eval_sgen_expr ~trace_cfg ~phase env_acc expr_with_loc
        in
        eval_all env' (evaluated :: results) rest
    in
    eval_all env [] exprs
  | Expect (expr1, expr2, message, location) ->
    let* env1, eval1 = eval_sgen_expr ~trace_cfg ~phase env expr1 in
    let* env2, eval2 = eval_sgen_expr ~trace_cfg ~phase env1 expr2 in
    let const1 = constellation_of_term eval1 in
    let const2 = constellation_of_term eval2 in
    (* Compare the raw stars: the reactive/catalyst mark is not part of
       what == observes *)
    let normalized1 = Marked.remove_all const1 in
    let normalized2 = Marked.remove_all const2 in
    if Raw.equal_constellation normalized1 normalized2 then Ok (env2, nil_term)
    else
      Error
        (ExpectError
           { got = const1; expected = const2; message; location; trace = [] } )
  | Match (expr1, expr2, message, location) ->
    let* env1, eval1 = eval_sgen_expr ~trace_cfg ~phase env expr1 in
    let* env2, eval2 = eval_sgen_expr ~trace_cfg ~phase env1 expr2 in
    let const1 = constellation_of_term eval1 |> List.map ~f:Marked.remove in
    let const2 = constellation_of_term eval2 |> List.map ~f:Marked.remove in
    if constellations_matchable const1 const2 then Ok (env2, nil_term)
    else
      let const1_marked = constellation_of_term eval1 in
      let const2_marked = constellation_of_term eval2 in
      Error
        (MatchError
           { term1 = const1_marked
           ; term2 = const2_marked
           ; message
           ; location
           ; trace = []
           } )
  | Use (path, location) -> (
    let open Constellation.StellarRays in
    let filename =
      match path with
      | Func ((Null, f), [ s ]) when String.equal f "%string" -> string_of_ray s
      | _ -> string_of_ray path ^ ".sg"
    in
    (* Resolve relative to the importing file, like macro imports do *)
    let filename =
      match location with
      | Some { filename = importer; _ } ->
        Stellogen_parsing.resolve_path importer filename
      | None -> filename
    in
    let create_start_pos fname =
      { Lexing.pos_fname = fname; pos_lnum = 1; pos_bol = 0; pos_cnum = 0 }
    in
    let expr =
      In_channel.with_file filename ~f:(fun ic ->
        let lexbuf = Sedlexing.Utf8.from_channel ic in
        Sedlexing.set_position lexbuf (create_start_pos filename);
        Stellogen_parsing.parse_with_error filename lexbuf )
    in
    let preprocessed =
      Stellogen_parsing.preprocess_with_imports filename expr
    in
    match Expression.program_of_expr preprocessed with
    | Ok program ->
      (* Imports inherit the phase: the imported file's items
         self-classify under the active phase *)
      let* new_env = eval_program_internal ~trace_cfg ~phase env program in
      Ok (new_env, nil_term)
    | Error (expr_err, loc) -> Error (ExprError (expr_err, loc, [])) )

and eval_program (p : program) =
  match eval_program_internal initial_env p with
  | Ok env -> Ok env
  | Error e ->
    let* pp = pp_err e in
    Out_channel.output_string Out_channel.stderr pp;
    Error e

and eval_program_internal ?(trace_cfg : Tracer.trace_config option = None)
  ?(phase = Run) (env : env) (p : program) =
  List.fold_left
    ~f:(fun acc (item_phase, x) ->
      let* acc_env = acc in
      if phase_active phase item_phase then
        let* new_env, _ = eval_sgen_expr ~trace_cfg ~phase acc_env x in
        Ok new_env
      else Ok { acc_env with skipped = skipped_def_names x @ acc_env.skipped } )
    ~init:(Ok env) p

(* Check-phase evaluation with error collection, per top-level item:
   assertion failures are recorded and evaluation continues; structural
   errors stop it, since later items legitimately depend on definitions. *)
let eval_program_check (p : program) : env * err list =
  let env, rev_errors =
    List.fold_until p ~init:(initial_env, [])
      ~f:(fun (env, errors) (item_phase, x) ->
        if phase_active Check item_phase then
          match eval_sgen_expr ~phase:Check env x with
          | Ok (env', _) -> Continue_or_stop.Continue (env', errors)
          | Error ((ExpectError _ | MatchError _) as e) ->
            Continue_or_stop.Continue (env, e :: errors)
          | Error e -> Continue_or_stop.Stop (env, e :: errors)
        else
          Continue_or_stop.Continue
            ({ env with skipped = skipped_def_names x @ env.skipped }, errors) )
      ~finish:Fn.id
  in
  (env, List.rev rev_errors)
