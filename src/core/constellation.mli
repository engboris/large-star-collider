(** Constellation types and operations.

    This module defines the core data structures for stellar resolution: rays
    (polarized terms), stars (collections of rays), and constellations
    (collections of stars). *)

(** {1 Polarity} *)

(** Ray polarity: positive (provides), negative (requests), or neutral *)
type polarity =
  | Pos  (** Positive polarity - provides/offers *)
  | Neg  (** Negative polarity - requests/demands *)
  | Null  (** Neutral - does not interact *)

val equal_polarity : polarity -> polarity -> bool

(** {1 Signature Modules} *)

(** Signature for stellar rays (polarity-aware compatibility) *)
module StellarSig : sig
  type idvar = string * int option

  type idfunc = polarity * string

  val string_of_idvar : idvar -> string

  val equal_idvar : idvar -> idvar -> bool

  val equal_idfunc : idfunc -> idfunc -> bool

  val compatible : idfunc -> idfunc -> bool
end

(** {1 Unification Modules} *)

(** Stellar rays with polarity-aware unification *)
module StellarRays : module type of Unification.Make (StellarSig)

(** {1 Core Types} *)

(** A ray is a term (from StellarRays) *)
type ray = StellarRays.term

val equal_ray : ray -> ray -> bool

(** Constraints on stars *)
type ban =
  | Ineq of ray * ray  (** Inequality constraint *)
  | Incomp of ray * ray  (** Incompatibility constraint *)

val equal_ban : ban -> ban -> bool

(** {1 Raw Stars and Constellations} *)

(** Unmarked (raw) stars and constellations *)
module Raw : sig
  (** A star is a collection of rays with optional constraints *)
  type star =
    { content : ray list
    ; bans : ban list
    }

  val equal_star : star -> star -> bool

  (** A constellation is a collection of stars *)
  type constellation = star list

  val equal_constellation : constellation -> constellation -> bool
end

(** {1 Marked Stars and Constellations} *)

(** Stars marked as reactive (linear, mutually interacting, part of the result),
    catalyst (duplicated at each use, inert toward other catalysts, dropped from
    the result), or seed (a reactive star tried first when the executor picks a
    starting point). *)
module Marked : sig
  (** A marked star is reactive, a catalyst, or a seed *)
  type star =
    | Reactive of Raw.star
      (** Reactive stars are the solution: consumed by reacting *)
    | Catalyst of Raw.star
      (** Catalysts are solicited by reactive rays and persist *)
    | Seed of Raw.star
      (** A reactive star the executor tries first as a starting point;
          otherwise behaves exactly like a plain reactive star *)

  val equal_star : star -> star -> bool

  (** A marked constellation *)
  type constellation = star list

  val equal_constellation : constellation -> constellation -> bool

  (** Map a function over the rays in a star *)
  val map : f:(ray -> ray) -> star -> star

  (** Mark a raw star reactive *)
  val make_reactive : Raw.star -> star

  (** Mark all raw stars reactive *)
  val make_reactive_all : Raw.constellation -> constellation

  (** Turn a marked star into a catalyst *)
  val make_catalyst : star -> star

  (** Turn every star of a constellation into a catalyst *)
  val make_catalyst_all : constellation -> constellation

  (** Turn a marked star into a seed *)
  val make_seed : star -> star

  (** Turn every star of a constellation into a seed *)
  val make_seed_all : constellation -> constellation

  (** Remove marking from a star *)
  val remove : star -> Raw.star

  (** Remove marking from all stars *)
  val remove_all : constellation -> Raw.constellation
end

(** {1 Utilities} *)

(** Generate a fresh placeholder string (for anonymous variables) *)
val fresh_placeholder : unit -> string

(** {1 Term Constructors} *)

(** Create a variable term with no index *)
val to_var : string -> ray

(** Create a function term from polarity-symbol pair and arguments *)
val to_func : StellarSig.idfunc * ray list -> ray

(** Create a positive polarity symbol *)
val pos : string -> StellarSig.idfunc

(** Create a negative polarity symbol *)
val neg : string -> StellarSig.idfunc

(** Create a neutral polarity symbol *)
val null : string -> StellarSig.idfunc

(** Create a function term with given polarity *)
val gfunc : StellarSig.idfunc -> ray list -> ray

(** Create a positive function term *)
val pfunc : string -> ray list -> ray

(** Create a negative function term *)
val nfunc : string -> ray list -> ray

(** Create a neutral function term *)
val func : string -> ray list -> ray

(** Create a variable *)
val var : StellarSig.idvar -> ray

(** Create a positive constant (0-arity function) *)
val pconst : string -> ray

(** Create a negative constant *)
val nconst : string -> ray

(** Create a neutral constant *)
val const : string -> ray

(** {1 Ray Operations} *)

(** Check if a ray has polarity (Pos or Neg) *)
val is_polarised : ray -> bool

(** Replace variable indices in a ray *)
val replace_indices : int -> ray -> ray

(** Rename each distinct variable of the given rays to a fresh index starting at
    the given base. Injective on variables: same-named variables with different
    indices stay distinct. Returns the renaming and the number of indices
    consumed. *)
val injective_renaming : int -> ray list -> (ray -> ray) * int

(** {1 Ground Guards} *)

(** A [!X] in the source becomes a [%!] wrapper around the variable: a position
    that must be ground before the enclosing ray may interact. Substitution goes
    through the wrapper, so the requirement transfers to whatever fills the
    position. *)

(** Whether a ray contains no variable *)
val is_ground : ray -> bool

(** Erase guard wrappers (guards restrict when a ray may interact, never what it
    unifies with) *)
val strip_guards : ray -> ray

(** Whether every guarded position of the ray is ground *)
val ray_eligible : ray -> bool

(** Drop guards whose position has become ground *)
val simplify_guards : ray -> ray

(** Try to match two polarized rays (ignoring guards), returning substitution if
    successful *)
val raymatcher : ray -> ray -> StellarRays.substitution option

(** Base observation for [~=]: structural unifiability, ignoring polarity and
    guards *)
val terms_unifiable : ray -> ray -> bool

(** Find a fresh variable not in the given list *)
val fresh_var : StellarSig.idvar list -> StellarSig.idvar

(** {1 Constellation Operations} *)

(** Apply a substitution to all rays in a marked constellation *)
val subst_all_vars :
  StellarRays.substitution -> Marked.constellation -> Marked.constellation

(** Collect all variables from a marked constellation *)
val all_vars : Marked.constellation -> StellarSig.idvar list

(** Normalize variable names in a constellation *)
val normalize_vars : Marked.constellation -> Marked.constellation
