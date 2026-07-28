open Base

(* Global output buffer *)
let output_buffer : string list ref = ref []

let add_output s = output_buffer := s :: !output_buffer

let get_output () = String.concat ~sep:"\n" (List.rev !output_buffer)

let clear_output () = output_buffer := []

(* Parse and preprocess a program from a string. The browser has no
   filesystem, so imports are not resolved; playground examples inline
   the prelude instead. *)
let parse_program (code : string) =
  let raw_exprs = Stellogen_parsing.parse_from_string code in
  let preprocessed = Stellogen_parsing.preprocess_without_imports raw_exprs in
  Expression.program_of_expr preprocessed

let format_err err =
  match Evaluator.pp_err err with
  | Ok msg -> msg
  | Error _ -> "Evaluation error"

(* Prepend buffered show output to a message so it is not lost when
   evaluation stops on an error. *)
let with_shows msg =
  let output = get_output () in
  if String.is_empty output then msg else output ^ "\n" ^ msg

(* Glue output sections together, dropping the empty ones so a phase that
   printed nothing leaves no blank line behind *)
let join_sections sections =
  List.filter sections ~f:(fun s -> not (String.is_empty s))
  |> String.concat ~sep:"\n"

let count_check_items program =
  List.count program ~f:(fun (item_phase, _) ->
    match item_phase with Syntax.CheckOnly -> true | _ -> false )

let check_items_count n =
  if n = 1 then "1 check-phase item"
  else Printf.sprintf "%d check-phase items" n

let eval_with_buffer (code : string)
  (eval : Syntax.program -> (string, string) Result.t) =
  try
    match parse_program code with
    | Error (expr_error, loc) ->
      Error (format_err (Syntax.ExprError (expr_error, loc, [])))
    | Ok program ->
      clear_output ();
      Evaluator.show_printer := add_output;
      eval program
  with
  | Stellogen_parsing.ParseError report -> Error report
  | Failure msg -> Error ("Error: " ^ msg)
  | exn -> Error ("Exception: " ^ Exn.to_string exn)

(* Run the run phase of a program, like 'sgen run' *)
let run_from_string (code : string) : (string, string) Result.t =
  eval_with_buffer code (fun program ->
    match Evaluator.eval_program_internal Syntax.initial_env program with
    | Ok _ ->
      let output = get_output () in
      let checked = count_check_items program in
      if String.is_empty output && checked > 0 then
        Ok
          (Printf.sprintf
             "No run-phase output, %s skipped. Use Eval or Check to evaluate \
              them."
             (check_items_count checked) )
      else Ok output
    | Error err -> Error (with_shows (format_err err)) )

(* Run the check phase of a program, like 'sgen check', with a summary
   line since the playground has no exit code to inspect *)
let check_from_string (code : string) : (string, string) Result.t =
  eval_with_buffer code (fun program ->
    let checked = count_check_items program in
    let _env, errors = Evaluator.eval_program_check program in
    match errors with
    | [] ->
      let summary =
        if checked = 0 then
          "Nothing to check: no check-phase items (marked with \xc2\xa7)."
        else Printf.sprintf "Check passed (%s)." (check_items_count checked)
      in
      Ok (with_shows summary)
    | _ ->
      let messages = List.map errors ~f:format_err |> String.concat ~sep:"\n" in
      Error (with_shows messages) )

(* Both phases of a program, like 'sgen eval': the check phase first, then
   the run phase only if it passed. The two phases print in order, with the
   check summary between them since the playground has no exit code. *)
let eval_from_string (code : string) : (string, string) Result.t =
  eval_with_buffer code (fun program ->
    let checked = count_check_items program in
    let _env, check_errors = Evaluator.eval_program_check program in
    let check_output = get_output () in
    clear_output ();
    match check_errors with
    | _ :: _ ->
      let messages =
        List.map check_errors ~f:format_err |> String.concat ~sep:"\n"
      in
      Error (join_sections [ check_output; messages ])
    | [] -> (
      let summary =
        if checked = 0 then ""
        else Printf.sprintf "Check passed (%s)." (check_items_count checked)
      in
      match Evaluator.eval_program_internal Syntax.initial_env program with
      | Ok _ -> Ok (join_sections [ check_output; summary; get_output () ])
      | Error err ->
        Error
          (join_sections
             [ check_output; summary; get_output (); format_err err ] ) ) )
