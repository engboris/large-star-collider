(*
 * lsc_trace.ml - Trace visualization for execution
 *
 * This module provides tracing capabilities that plug into the
 * event-based execution engine.
 *)

open Base
open Stdio
open Constellation.Raw
open Pretty
open Terminal

(* ============================================================
   Source Location Tracking
   ============================================================ *)

type source_location =
  { filename : string
  ; line : int
  ; column : int
  }

let get_source_line filename line_num =
  try
    In_channel.with_file filename ~f:(fun ic ->
      let rec skip n =
        if n <= 1 then ()
        else (
          ignore (In_channel.input_line_exn ic);
          skip (n - 1) )
      in
      skip line_num;
      In_channel.input_line ic )
  with _ -> None

(* ============================================================
   Trace State
   ============================================================ *)

type trace_mode =
  | Interactive (* Wait for keypress between steps *)
  | Batch (* Print all steps without waiting *)
  | Silent (* Don't print, just collect *)
  | WebMode (* Collect for HTML output *)

type trace_state =
  { mode : trace_mode
  ; mutable location : source_location option
  ; mutable collected_steps : collected_step list
  ; mutable fusion_shown_this_step : bool
  }

and collected_step =
  { step_num : int
  ; catalysts : constellation
  ; reactives : constellation
  ; is_final : bool
  }

let create ?(mode = Interactive) () =
  { mode
  ; location = None
  ; collected_steps = []
  ; fusion_shown_this_step = false
  }

let set_location state loc = state.location <- loc

(* ============================================================
   Terminal Output
   ============================================================ *)

let wait_for_keypress () = ignore (Stdlib.input_line Stdlib.stdin)

(* Always show the current source line (marked, normal color), so a trace
   reads like a cursor moving through the file instead of only occasionally
   pointing at a line. *)
let print_source_lines loc =
  Stdlib.Printf.printf "\n%s %s:%d:%d" (dim "at") loc.filename loc.line
    loc.column;
  match get_source_line loc.filename loc.line with
  | Some line ->
    let trimmed = String.strip line in
    if not (String.is_empty trimmed) then
      Stdlib.Printf.printf "\n  %s %s" (cyan "\xe2\x96\xb8") trimmed
  | None -> ()

let print_header step_num location status =
  Stdlib.Printf.printf "\n%s\n" (String.make 80 '=');
  Stdlib.Printf.printf "%s %s"
    (bold (cyan "Step"))
    (bold (yellow (Int.to_string step_num)));
  Option.iter status ~f:(fun msg -> Stdlib.Printf.printf " - %s" (bold msg));
  Option.iter location ~f:print_source_lines;
  Stdlib.Printf.printf "\n%s\n" (String.make 80 '=')

let print_constellation label stars =
  if List.is_empty stars then
    Stdlib.Printf.printf "%s %s\n" (bold label) (dim "{}")
  else begin
    Stdlib.Printf.printf "%s\n" (bold label);
    List.iteri stars ~f:(fun i star ->
      Stdlib.Printf.printf "  %s %s\n"
        (dim (Printf.sprintf "[%d]" i))
        (string_of_star star) )
  end

let print_footer () =
  Stdlib.Printf.printf "\n%s\n" (dim "Press Enter to continue...");
  Stdlib.flush Stdlib.stdout;
  wait_for_keypress ()

(* ============================================================
   Event Handler Factory
   ============================================================ *)

let make_handler state : Executor.event_handler =
  let open Executor in
  function
  | StepStart { step; catalysts; reactives } -> (
    state.fusion_shown_this_step <- false;
    match state.mode with
    | Silent | WebMode ->
      state.collected_steps <-
        { step_num = step; catalysts; reactives; is_final = false }
        :: state.collected_steps
    | Interactive | Batch -> () (* We'll print on fusion or completion *) )
  | FusionFound candidate -> (
    match state.mode with
    | Silent | WebMode -> ()
    | (Interactive | Batch) when not state.fusion_shown_this_step ->
      state.fusion_shown_this_step <- true;
      print_header candidate.source_idx state.location
        (Some (magenta "Fusion detected!"));
      Stdlib.Printf.printf "\n";
      Stdlib.Printf.printf "  Reactive star [%d], ray %d\n" candidate.source_idx
        candidate.source_ray_idx;
      ( match candidate.partner with
      | Executor.InternalCut ->
        Stdlib.Printf.printf "  Internal cut with ray %d\n"
          candidate.partner_ray_idx
      | Executor.WithReactive i ->
        Stdlib.Printf.printf "  Reactive star [%d], ray %d\n" i
          candidate.partner_ray_idx
      | Executor.WithCatalyst i ->
        Stdlib.Printf.printf "  Catalyst star [%d], ray %d\n" i
          candidate.partner_ray_idx );
      if not (List.is_empty candidate.theta) then
        Stdlib.Printf.printf "  %s %s\n" (dim "θ =")
          (yellow (string_of_subst candidate.theta))
    | _ -> () )
  | StepComplete { step = _; result = _ } -> (
    match state.mode with
    | Interactive -> print_footer ()
    | Batch -> Stdlib.Printf.printf "\n"
    | Silent | WebMode -> () )
  | ExecutionDone result -> (
    match state.mode with
    | Silent | WebMode ->
      state.collected_steps <-
        { step_num = List.length state.collected_steps + 1
        ; catalysts = []
        ; reactives = result
        ; is_final = true
        }
        :: state.collected_steps
    | Interactive | Batch ->
      print_header
        (List.length state.collected_steps + 1)
        state.location
        (Some (green "Execution complete"));
      Stdlib.Printf.printf "\n";
      print_constellation (cyan "Final result:") result;
      if phys_equal state.mode Interactive then print_footer () )

(* ============================================================
   HTML Output for Web Mode
   ============================================================ *)

let escape_html s =
  String.substr_replace_all s ~pattern:"&" ~with_:"&amp;"
  |> String.substr_replace_all ~pattern:"<" ~with_:"&lt;"
  |> String.substr_replace_all ~pattern:">" ~with_:"&gt;"
  |> String.substr_replace_all ~pattern:"\"" ~with_:"&quot;"

let format_html state =
  let buffer = Buffer.create 1024 in
  let add str = Buffer.add_string buffer str in
  let add_line str =
    add str;
    add "\n"
  in

  let steps = List.rev state.collected_steps in
  List.iter steps ~f:(fun step ->
    add_line "<div class='trace-step'>";
    if step.is_final then begin
      add_line
        (Printf.sprintf
           "<div class='step-header final'>Execution Complete (Step %d)</div>"
           step.step_num );
      add_line "<div class='step-content'>";
      add_line "<div class='result-label'>Final Result:</div>";
      add_line "<div class='constellation'>";
      List.iteri step.reactives ~f:(fun idx star ->
        add_line
          (Printf.sprintf "<div class='star'>[%d] %s</div>" idx
             (escape_html (string_of_star star)) ) );
      add_line "</div>";
      add_line "</div>"
    end
    else begin
      add_line
        (Printf.sprintf "<div class='step-header'>Step %d</div>" step.step_num);
      add_line "<div class='step-content'>";
      add_line "<div class='section'>";
      add_line "<div class='label'>Catalysts:</div>";
      if List.is_empty step.catalysts then
        add_line "<div class='empty'>{ }</div>"
      else begin
        add_line "<div class='constellation'>";
        List.iteri step.catalysts ~f:(fun idx star ->
          add_line
            (Printf.sprintf "<div class='star action-star'>[%d] %s</div>" idx
               (escape_html (string_of_star star)) ) );
        add_line "</div>"
      end;
      add_line "</div>";
      add_line "<div class='section'>";
      add_line "<div class='label'>Reactive stars:</div>";
      if List.is_empty step.reactives then
        add_line "<div class='empty'>{ }</div>"
      else begin
        add_line "<div class='constellation'>";
        List.iteri step.reactives ~f:(fun idx star ->
          add_line
            (Printf.sprintf "<div class='star state-star'>[%d] %s</div>" idx
               (escape_html (string_of_star star)) ) );
        add_line "</div>"
      end;
      add_line "</div>";
      add_line "</div>"
    end;
    add_line "</div>" );

  Buffer.contents buffer

(* ============================================================
   Trace Configuration (evaluator-facing entry point)
   ============================================================ *)

type trace_config =
  { enabled : bool
  ; mutable trace_state : trace_state option
  ; mutable current_location : source_location option
  }

let make_trace_config ?(web_mode = false) enabled =
  let mode =
    if web_mode then WebMode else if enabled then Interactive else Silent
  in
  { enabled; trace_state = Some (create ~mode ()); current_location = None }

let set_trace_location cfg loc =
  cfg.current_location <- loc;
  match cfg.trace_state with Some state -> set_location state loc | None -> ()

let get_trace_steps cfg =
  match cfg.trace_state with Some state -> state.collected_steps | None -> []

let format_trace_steps_html steps =
  let state = create ~mode:WebMode () in
  state.collected_steps <- steps;
  format_html state

(* Run a constellation, routing fusion events to [trace]'s handler when one
   is given and enabled. *)
let exec ?(trace = None) mcs : constellation =
  match trace with
  | None -> Executor.exec mcs
  | Some cfg when cfg.enabled -> (
    match cfg.trace_state with
    | Some state ->
      Option.iter cfg.current_location ~f:(fun loc ->
        set_location state (Some loc) );
      let handler = make_handler state in
      Executor.exec ~on_event:handler mcs
    | None -> Executor.exec mcs )
  | Some _ -> Executor.exec mcs
