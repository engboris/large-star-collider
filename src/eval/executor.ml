(*
 * executor.ml - Queue-based execution engine for star fusion
 *
 * One fusion rule: a reactive ray may fuse with any dual, unifiable,
 * eligible ray - in its own star (internal cut), in another reactive
 * star, or in a catalyst. Reactive stars are linear: consumed by
 * reacting, and whatever remains at saturation is the result.
 * Catalysts are duplicated at each use, inert toward other catalysts,
 * and dropped from the result. A ray holding a non-ground guard (%!)
 * is not a candidate until the guarded position becomes ground.
 *)

open Base
open Constellation
open Constellation.StellarRays
open Constellation.Raw

(* ============================================================
   Type Definitions
   ============================================================ *)

(** The partner side of a fusion event *)
type partner_kind =
  | WithCatalyst of int
  | WithReactive of int
  | InternalCut

(** A fusion between a reactive ray and a dual eligible ray *)
type fusion_candidate =
  { source_idx : int
  ; source_ray_idx : int
  ; partner : partner_kind
  ; partner_ray_idx : int
  ; theta : substitution
  }

(** Configuration for execution *)
type exec_config = { mutable var_counter : int }

(** Observable events during execution (for tracing) *)
type exec_event =
  | StepStart of
      { step : int
      ; catalysts : constellation
      ; reactives : constellation
      }
  | FusionFound of fusion_candidate
  | StepComplete of
      { step : int
      ; result : constellation
      }
  | ExecutionDone of constellation

(** Event handler type *)
type event_handler = exec_event -> unit

(* ============================================================
   Core Fusion Logic
   ============================================================ *)

let fmap_ban ~f = function
  | Ineq (b1, b2) -> Ineq (f b1, f b2)
  | Incomp (b1, b2) -> Incomp (f b1, f b2)

let rays_of_ban = function Ineq (b1, b2) | Incomp (b1, b2) -> [ b1; b2 ]

(** Check if bans are coherent (no contradictions) *)
let coherent_bans bans =
  let inequalities, incompatibles =
    List.fold bans ~init:([], []) ~f:(fun (ineqs, incomps) ban ->
      match ban with
      | Ineq (b1, b2) -> ((b1, b2) :: ineqs, incomps)
      | Incomp (b1, b2) -> (ineqs, (b1, b2) :: incomps) )
  in
  let ineqs_ok =
    List.for_all inequalities ~f:(fun (b1, b2) -> not (equal_ray b1 b2))
  in
  let incomps_ok =
    let rec check = function
      | [] -> true
      | (box, slice) :: rest ->
        let conflict =
          List.exists rest ~f:(fun (b, s) ->
            equal_ray box b && not (equal_ray slice s) )
        in
        (not conflict) && check rest
    in
    check incompatibles
  in
  ineqs_ok && incomps_ok

(** Merge the remaining halves of two stars along a matched ray pair *)
let perform_fusion ~repl1 ~repl2 ~other_rays1 ~other_rays2 ~bans1 ~bans2 ~theta
  : star =
  let rays1 = List.map other_rays1 ~f:repl1 in
  let rays2 = List.map other_rays2 ~f:repl2 in
  let nbans1 = List.map bans1 ~f:(fmap_ban ~f:repl1) in
  let nbans2 = List.map bans2 ~f:(fmap_ban ~f:repl2) in
  { content =
      List.map (rays1 @ rays2) ~f:(fun r -> simplify_guards (subst theta r))
  ; bans = List.map (nbans1 @ nbans2) ~f:(fmap_ban ~f:(subst theta))
  }

(* A ray can enter a fusion only if it is polarised and every guarded
   position in it is ground *)
let candidate_ray r = is_polarised r && ray_eligible r

(* ============================================================
   Internal Cuts
   ============================================================ *)

(** Two dual rays of one star cancel. The rays share the star's scope, so no
    renaming happens. Returns the branches for the first ray that has at least
    one internal partner (one branch per partner), or None if the star has no
    internal cut. *)
let try_internal_cut ~emit_event ~source_idx (s : star) : star list option =
  let rays = Array.of_list s.content in
  let n = Array.length rays in
  let branch i j theta =
    let rest =
      Array.filter_mapi rays ~f:(fun k r ->
        if k = i || k = j then None else Some r )
      |> Array.to_list
    in
    let fused =
      { content = List.map rest ~f:(fun r -> simplify_guards (subst theta r))
      ; bans = List.map s.bans ~f:(fmap_ban ~f:(subst theta))
      }
    in
    if coherent_bans fused.bans then begin
      emit_event
        (FusionFound
           { source_idx
           ; source_ray_idx = i
           ; partner = InternalCut
           ; partner_ray_idx = j
           ; theta
           } );
      Some fused
    end
    else None
  in
  let rec try_ray i =
    if i >= n then None
    else if not (candidate_ray rays.(i)) then try_ray (i + 1)
    else
      let branches =
        List.range 0 n
        |> List.filter_map ~f:(fun j ->
          if j = i || not (candidate_ray rays.(j)) then None
          else
            match raymatcher rays.(i) rays.(j) with
            | None -> None
            | Some theta -> branch i j theta )
      in
      if List.is_empty branches then try_ray (i + 1) else Some branches
  in
  try_ray 0

(* ============================================================
   External Fusions
   ============================================================ *)

(** All matches of one renamed source ray against the rays of one partner star
    (a catalyst or another reactive star). Returns (partner_ray_idx,
    other_partner_rays, theta) per match. *)
let find_partner_matches ~repl1 ~repl2 (source_ray : ray) (partner : star) :
  (int * ray list * substitution) list =
  let rec scan idx before = function
    | [] -> []
    | r :: rest when not (candidate_ray r) -> scan (idx + 1) (r :: before) rest
    | r :: rest -> (
      match raymatcher (repl1 source_ray) (repl2 r) with
      | None -> scan (idx + 1) (r :: before) rest
      | Some theta ->
        let remaining = scan (idx + 1) (r :: before) rest in
        (idx, List.rev before @ rest, theta) :: remaining )
  in
  scan 0 [] partner.content

type external_result =
  { branches : star list
  ; consumed_reactives : int list
      (* queue indices of matched reactive partners *)
  }

(** Find all fusions for one reactive ray, against the other reactive stars
    (which a match consumes) and the catalysts (which persist). Each match
    yields one branch. *)
let find_ray_fusions ~config ~emit_event ~source_idx ~source_ray_idx ~source_ray
  ~other_source_rays ~source_bans ~(reactives : star array)
  ~(catalysts : star list) : external_result =
  let repl1, used1 =
    injective_renaming config.var_counter
      ( (source_ray :: other_source_rays)
      @ List.concat_map source_bans ~f:rays_of_ban )
  in
  let branches = ref [] in
  let consumed = ref [] in
  let try_partner ~partner_tag partner_idx (partner : star) : bool =
    let repl2, used2 =
      injective_renaming
        (config.var_counter + used1)
        (partner.content @ List.concat_map partner.bans ~f:rays_of_ban)
    in
    let matches = find_partner_matches ~repl1 ~repl2 source_ray partner in
    let fused_any = ref false in
    List.iter matches ~f:(fun (partner_ray_idx, other_partner_rays, theta) ->
      let fused =
        perform_fusion ~repl1 ~repl2 ~other_rays1:other_source_rays
          ~other_rays2:other_partner_rays ~bans1:source_bans ~bans2:partner.bans
          ~theta
      in
      if coherent_bans fused.bans then begin
        emit_event
          (FusionFound
             { source_idx
             ; source_ray_idx
             ; partner = partner_tag partner_idx
             ; partner_ray_idx
             ; theta
             } );
        branches := fused :: !branches;
        fused_any := true;
        config.var_counter <- config.var_counter + used1 + used2
      end );
    !fused_any
  in
  Array.iteri reactives ~f:(fun i partner ->
    if i <> source_idx then
      if try_partner ~partner_tag:(fun k -> WithReactive k) i partner then
        consumed := i :: !consumed );
  List.iteri catalysts ~f:(fun i partner ->
    ignore (try_partner ~partner_tag:(fun k -> WithCatalyst k) i partner : bool) );
  { branches = List.rev !branches; consumed_reactives = !consumed }

(* ============================================================
   Main Execution Loop
   ============================================================ *)

let exec ?(on_event = fun _ -> ()) mcs : constellation =
  let config = { var_counter = 0 } in

  (* @-marked (seed) stars are tried as a starting point before plain
     reactive stars: every scan below (internal cuts, external fusions)
     walks the reactive list front-to-back, so moving seeds to the
     front is enough to bias where execution starts, without touching
     what fires, what's kept, or what's linear. Seeds fall back to plain
     list order among themselves and relative to non-seeds. *)
  let catalysts, seeded, plain =
    List.fold mcs ~init:([], [], []) ~f:(fun (cs, sds, pls) -> function
      | Marked.Catalyst s -> (s :: cs, sds, pls)
      | Marked.Seed s -> (cs, s :: sds, pls)
      | Marked.Reactive s -> (cs, sds, s :: pls) )
  in
  let catalysts = List.rev catalysts in
  let reactives = List.rev seeded @ List.rev plain in

  (* Internal cuts: first star holding one is replaced by its branches *)
  let try_internal reactives =
    let rec scan idx before = function
      | [] -> None
      | s :: rest -> (
        match try_internal_cut ~emit_event:on_event ~source_idx:idx s with
        | Some branches -> Some (List.rev_append before (branches @ rest))
        | None -> scan (idx + 1) (s :: before) rest )
    in
    scan 0 [] reactives
  in

  (* Fusions across stars: first reactive ray with matches takes all of
     them as branches; the source star and every matched reactive
     partner are consumed, catalysts persist *)
  let try_external reactives =
    let arr = Array.of_list reactives in
    let n = Array.length arr in
    let rec per_star source_idx =
      if source_idx >= n then None
      else
        let s = arr.(source_idx) in
        let rec per_ray ray_idx before = function
          | [] -> None
          | r :: rest when not (candidate_ray r) ->
            per_ray (ray_idx + 1) (r :: before) rest
          | r :: rest ->
            let other = List.rev_append before rest in
            let { branches; consumed_reactives } =
              find_ray_fusions ~config ~emit_event:on_event ~source_idx
                ~source_ray_idx:ray_idx ~source_ray:r ~other_source_rays:other
                ~source_bans:s.bans ~reactives:arr ~catalysts
            in
            if List.is_empty branches then
              per_ray (ray_idx + 1) (r :: before) rest
            else
              let kept =
                Array.filter_mapi arr ~f:(fun i s' ->
                  if
                    i = source_idx
                    || List.mem consumed_reactives i ~equal:Int.equal
                  then None
                  else Some s' )
                |> Array.to_list
              in
              Some (kept @ branches)
        in
        match per_ray 0 [] s.content with
        | Some result -> Some result
        | None -> per_star (source_idx + 1)
    in
    per_star 0
  in

  let rec loop step reactives =
    on_event (StepStart { step; catalysts; reactives });
    let next =
      match try_internal reactives with
      | Some result -> Some result
      | None -> try_external reactives
    in
    match next with
    | None ->
      on_event (ExecutionDone reactives);
      reactives
    | Some result ->
      on_event (StepComplete { step; result });
      loop (step + 1) result
  in

  loop 1 reactives |> List.filter ~f:(fun s -> not @@ List.is_empty s.content)
