open Js_of_ocaml
open Stellogen

(* Strip ANSI color codes from error messages for web display *)
let strip_ansi_codes str =
  let re = Regexp.regexp "\027\\[[0-9;]*m" in
  Regexp.global_replace re str ""

(* The "ERROR: " prefix is how the page distinguishes failures;
   keep it in sync with index.html *)
let to_js_result = function
  | Ok output -> Js.string (strip_ansi_codes output)
  | Error err -> Js.string ("ERROR: " ^ strip_ansi_codes err)

let run_stellogen code_js =
  try to_js_result (Web_interface.run_from_string (Js.to_string code_js))
  with e -> Js.string ("ERROR: Exception: " ^ Printexc.to_string e)

let check_stellogen code_js =
  try to_js_result (Web_interface.check_from_string (Js.to_string code_js))
  with e -> Js.string ("ERROR: Exception: " ^ Printexc.to_string e)

let eval_stellogen code_js =
  try to_js_result (Web_interface.eval_from_string (Js.to_string code_js))
  with e -> Js.string ("ERROR: Exception: " ^ Printexc.to_string e)

(* Export to JavaScript *)
let () =
  Js.export "Stellogen"
    object%js
      method run code = run_stellogen code

      method check code = check_stellogen code

      method eval code = eval_stellogen code
    end
