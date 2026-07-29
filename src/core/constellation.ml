open Base

type polarity =
  | Pos
  | Neg
  | Null
[@@deriving eq]

module StellarSig = struct
  type idvar = string * int option

  type idfunc = polarity * string

  let string_of_idvar (s, index_opt) =
    match index_opt with None -> s | Some j -> s ^ Int.to_string j

  (* Compare the pair, not its printed form: name ^ index would make
     ("X1", Some 0) and ("X", Some 10) the same variable. *)
  let equal_idvar (s1, i1) (s2, i2) =
    String.equal s1 s2 && Option.equal Int.equal i1 i2

  let equal_idfunc (p1, f1) (p2, f2) =
    equal_polarity p1 p2 && String.equal f1 f2

  let compatible (p1, f1) (p2, f2) =
    String.equal f1 f2
    &&
    match (p1, p2) with
    | Pos, Neg | Neg, Pos | Null, Null -> true
    | _ -> false
end

module StellarRays = Unification.Make (StellarSig)
open StellarRays

(* ---------------------------------------
   Stars and Constellations
   --------------------------------------- *)

let counter_placeholder = ref 0

let fresh_placeholder () =
  let r = !counter_placeholder in
  counter_placeholder := !counter_placeholder + 1;
  Int.to_string r

type ray = term [@@deriving eq]

type ban =
  | Ineq of ray * ray
  | Incomp of ray * ray
[@@deriving eq]

module Raw = struct
  type star =
    { content : ray list
    ; bans : ban list
    }
  [@@deriving eq]

  type constellation = star list [@@deriving eq]
end

let to_var x = Var (x, None)

let to_func (pf, ts) = Func (pf, ts)

let pos f = (Pos, f)

let neg f = (Neg, f)

let null f = (Null, f)

let gfunc c ts = Func (c, ts)

let pfunc f ts = gfunc (pos f) ts

let nfunc f ts = gfunc (neg f) ts

let func f ts = gfunc (null f) ts

let var x = Var x

let pconst f = pfunc f []

let nconst f = nfunc f []

let const f = func f []

let is_polarised r : bool =
  let aux = function Pos, _ | Neg, _ -> true | _ -> false in
  exists_func aux r

let replace_indices (i : int) : ray -> ray =
  map Fn.id (fun (x, _) -> Var (x, Some i))

(* Rename each distinct variable of [rays] to a fresh index starting at
   [base]. Injective on variables: same-named variables with different
   indices stay distinct. Returns the renaming and the number of
   indices consumed. *)
let injective_renaming (base : int) (rays : ray list) : (ray -> ray) * int =
  let distinct =
    List.concat_map rays ~f:vars
    |> List.fold ~init:[] ~f:(fun acc v ->
      if List.mem acc v ~equal:StellarSig.equal_idvar then acc else v :: acc )
    |> List.rev
  in
  let renamed =
    List.mapi distinct ~f:(fun k (x, _) -> Var (x, Some (base + k)))
  in
  let assoc = List.zip_exn distinct renamed in
  let rename v =
    match List.Assoc.find assoc ~equal:StellarSig.equal_idvar v with
    | Some t -> t
    | None -> Var v
  in
  (map Fn.id rename, List.length distinct)

(* ---------------------------------------
   Ground guards
   --------------------------------------- *)

(* A `!X` in the source becomes a %! wrapper around the variable. The
   wrapper marks a position that must be ground before the enclosing
   ray may interact. Substitution goes through the wrapper, so the
   requirement transfers to whatever fills the position: !X under
   X := (s Y) becomes (s !Y). *)
let guard_name = "%!"

let is_guard_sym (p, f) = equal_polarity p Null && String.equal f guard_name

let is_ground (r : ray) : bool = List.is_empty (vars r)

(* Erase guard wrappers: guards restrict when a ray may interact,
   never what it unifies with. *)
let rec strip_guards : ray -> ray = function
  | Var x -> Var x
  | Func (f, [ t ]) when is_guard_sym f -> strip_guards t
  | Func (f, ts) -> Func (f, List.map ~f:strip_guards ts)

(* A ray may interact only when every guarded position in it is
   ground. *)
let ray_eligible (r : ray) : bool =
  let rec check under_guard = function
    | Var _ -> not under_guard
    | Func (f, [ t ]) when is_guard_sym f -> check true t
    | Func (_, ts) -> List.for_all ts ~f:(check under_guard)
  in
  check false r

(* Drop guards whose position has become ground, so discharged guards
   do not linger in residues. *)
let rec simplify_guards : ray -> ray = function
  | Var x -> Var x
  | Func (f, [ t ]) when is_guard_sym f ->
    let t' = simplify_guards t in
    if is_ground t' then t' else Func (f, [ t' ])
  | Func (f, ts) -> Func (f, List.map ~f:simplify_guards ts)

let raymatcher r r' : substitution option =
  if is_polarised r && is_polarised r' then
    solution [ (strip_guards r, strip_guards r') ]
  else None

(* Base observation for ~= : structural unifiability, ignoring polarity.
   Polarities are normalized to Null so that the regular unification
   decides matchability (Null/Null symbols are compatible). *)
let strip_polarities : ray -> ray =
  map (fun (_, f) -> (Null, f)) (fun v -> Var v)

let terms_unifiable r r' =
  let clean r = strip_polarities (strip_guards r) in
  solution [ (clean r, clean r') ] |> Option.is_some

let fresh_var vars =
  let rec find_fresh_index i =
    if List.mem vars ("X", Some i) ~equal:StellarSig.equal_idvar then
      find_fresh_index (i + 1)
    else ("X", Some i)
  in
  find_fresh_index 0

(* ---------------------------------------
   Operation on marked stars
   --------------------------------------- *)

module Marked = struct
  (* Reactive stars are the solution: linear (each exists once,
     consumed by reacting), mutually interacting, part of the result.
     Catalysts (marked with a star prefix in the source) are solicited
     by reactive rays, duplicated at each use, inert toward other
     catalysts, and dropped from the result. A seed (marked with `@`) is
     a reactive star with the same linear behavior as any other, except
     the executor tries it as a starting point before unmarked reactive
     stars; it is otherwise an ordinary reactive star (kept when
     unreached, consumed when it reacts). *)
  type star =
    | Reactive of Raw.star
    | Catalyst of Raw.star
    | Seed of Raw.star
  [@@deriving eq]

  type constellation = star list [@@deriving eq]

  let map ~f : star -> star = function
    | Reactive s -> Reactive { content = List.map ~f s.content; bans = s.bans }
    | Catalyst s -> Catalyst { content = List.map ~f s.content; bans = s.bans }
    | Seed s -> Seed { content = List.map ~f s.content; bans = s.bans }

  let make_reactive s = Reactive s

  let make_reactive_all = List.map ~f:make_reactive

  let make_catalyst : star -> star = function
    | Reactive s | Catalyst s | Seed s -> Catalyst s

  let make_catalyst_all = List.map ~f:make_catalyst

  let make_seed : star -> star = function
    | Reactive s | Catalyst s | Seed s -> Seed s

  let make_seed_all = List.map ~f:make_seed

  let remove : star -> Raw.star = function
    | Reactive s | Catalyst s | Seed s -> s

  let remove_all = List.map ~f:remove
end

let subst_all_vars sub = List.map ~f:(Marked.map ~f:(subst sub))

let all_vars mcs : StellarSig.idvar list =
  mcs
  |> List.concat_map ~f:(function
    | Marked.Reactive s | Marked.Catalyst s | Marked.Seed s ->
    List.concat_map s.content ~f:StellarRays.vars )

let normalize_vars (mcs : Marked.constellation) =
  let vars = all_vars mcs in
  let new_var_name, new_start_index = fresh_var vars in
  let start_index = Option.value new_start_index ~default:0 in
  let new_vars =
    List.mapi vars ~f:(fun offset _ ->
      Var (new_var_name, Some (start_index + offset)) )
  in
  let substitution = List.zip_exn vars new_vars in
  subst_all_vars substitution mcs
