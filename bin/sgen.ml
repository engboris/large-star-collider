open Base
open Cmdliner
open Stellogen

let create_start_pos filename =
  { Lexing.pos_fname = filename; pos_lnum = 1; pos_bol = 0; pos_cnum = 0 }

let parse input_file =
  let lexbuf = Sedlexing.Utf8.from_channel (Stdlib.open_in input_file) in
  Sedlexing.set_position lexbuf (create_start_pos input_file);
  Stellogen_parsing.parse_with_error input_file lexbuf

let print_err error =
  match Evaluator.pp_err error with
  | Ok error_msg -> Stdlib.Printf.eprintf "%s" error_msg
  | Error _ -> ()

let with_program input_file f =
  let expr = parse input_file in
  let preprocessed =
    Stellogen_parsing.preprocess_with_imports input_file expr
  in
  match Expression.program_of_expr preprocessed with
  | Ok program -> f program
  | Error (expr_error, loc) ->
    print_err (ExprError (expr_error, loc, []));
    Stdlib.exit 1

let run_phase program =
  match Evaluator.eval_program program with
  | Ok _ -> ()
  | Error _ -> Stdlib.exit 1

let check_phase program =
  let _env, errors = Evaluator.eval_program_check program in
  List.iter errors ~f:print_err;
  if not (List.is_empty errors) then Stdlib.exit 1

let run input_file = with_program input_file run_phase

let check input_file = with_program input_file check_phase

(* Both phases of the same file, check first: a failed check means the run
   phase is never attempted. *)
let eval input_file =
  with_program input_file (fun program ->
    check_phase program;
    run_phase program )

let trace input_file =
  with_program input_file (fun program ->
    let trace_cfg = Some (Tracer.make_trace_config true) in
    match
      Evaluator.eval_program_internal ~trace_cfg Syntax.initial_env program
    with
    | Ok _ -> ()
    | Error e ->
      print_err e;
      Stdlib.exit 1 )

let preprocess_only input_file =
  let expr = parse input_file in
  let preprocessed =
    Stellogen_parsing.preprocess_with_imports input_file expr
  in
  preprocessed
  |> List.map ~f:(fun e -> Expression.to_string e.Expression.content)
  |> String.concat ~sep:"\n" |> Stdlib.print_endline

let input_file_arg =
  let doc = "Input file to process." in
  Arg.(required & pos 0 (some string) None & info [] ~docv:"FILENAME" ~doc)

let wrap f input_file =
  try Ok (f input_file) with e -> Error (`Msg (Exn.to_string e))

let run_cmd =
  let doc = "Run the Stellogen program (run phase)" in
  let term = Term.(const (wrap run) $ input_file_arg |> term_result) in
  Cmd.v (Cmd.info "run" ~doc) term

let check_cmd =
  let doc = "Evaluate the check phase of the Stellogen program" in
  let term = Term.(const (wrap check) $ input_file_arg |> term_result) in
  Cmd.v (Cmd.info "check" ~doc) term

let eval_cmd =
  let doc = "Evaluate both phases of the Stellogen program (check, then run)" in
  let term = Term.(const (wrap eval) $ input_file_arg |> term_result) in
  Cmd.v (Cmd.info "eval" ~doc) term

let trace_cmd =
  let doc = "Run the Stellogen program with interactive execution trace" in
  let term = Term.(const (wrap trace) $ input_file_arg |> term_result) in
  Cmd.v (Cmd.info "trace" ~doc) term

let preprocess_cmd =
  let doc = "Show the preprocessed code" in
  let term =
    Term.(const (wrap preprocess_only) $ input_file_arg |> term_result)
  in
  Cmd.v (Cmd.info "preprocess" ~doc) term

let default_cmd =
  let doc = "Stellogen: code generator and evaluator" in
  Cmd.group (Cmd.info "sgen" ~doc)
    [ run_cmd; check_cmd; eval_cmd; trace_cmd; preprocess_cmd ]

let () = Stdlib.exit (Cmd.eval default_cmd)
