(* Reporting.

   A divergence report is read by a person deciding which engine to fix, so it
   has to show *what each engine said*, not just that they differed.  The
   summary line is the part a CI log keeps. *)

let use_colour = ref true

let c code s = if !use_colour then "\027[" ^ code ^ "m" ^ s ^ "\027[0m" else s
let red s = c "0;31" s
let green s = c "0;32" s
let yellow s = c "1;33" s
let cyan s = c "0;36" s
let bold s = c "1" s
let dim s = c "2" s

(* Outputs are shown inline, so they must be short and single-line. *)
let preview ?(width = 58) (s : string) =
  let s = String.concat "\\n" (String.split_on_char '\n' (String.trim s)) in
  if s = "" then dim "<empty>"
  else if String.length s <= width then s
  else String.sub s 0 (width - 1) ^ "…"

let status_note = function
  | Engine.Completed -> ""
  | Engine.Unsupported -> "unsupported"
  | Engine.Timeout -> "timeout"
  | Engine.Unavailable -> "unavailable"

(* An engine that printed nothing usually printed a *reason* on stderr.  Showing
   `<empty>` for it would hide the most informative line in the report — the
   tree-walker's overflow error is the whole finding in pow_overflow. *)
let class_preview (o : Consensus.outcome) (out : string) (ids : string list) =
  if String.trim out <> "" then preview out
  else
    match List.find_opt (fun (r : Engine.result) ->
        List.mem r.eid ids && String.trim r.stderr <> "") o.results with
    | Some r -> dim "stderr: " ^ preview ~width:48 r.stderr
    | None -> preview out

let print_divergence (o : Consensus.outcome) =
  match o.verdict with
  | Consensus.Split classes ->
    Printf.printf "\n%s %s\n" (red "DIVERGE") (bold o.file);
    List.iter (fun (out, ids) ->
        Printf.printf "    %-22s %s\n"
          (String.concat "," ids) (class_preview o out ids)) classes;
    if o.skipped <> [] then
      Printf.printf "    %s\n"
        (dim ("(" ^ String.concat ", "
                (List.map (fun (id, st) -> id ^ ": " ^ status_note st) o.skipped)
              ^ ")"))
  | _ -> ()

let print_verbose (o : Consensus.outcome) =
  match o.verdict with
  | Consensus.Agree _ -> Printf.printf "  %s  %s\n" (green "AGREE") o.file
  | Consensus.TooFew ->
    Printf.printf "  %s   %s  %s\n" (yellow "FEW") o.file
      (dim ("only " ^ string_of_int (List.length (Consensus.voters o.results))
            ^ " engine(s) ran"))
  | Consensus.Split _ -> print_divergence o

(* ------------------------------------------------------------------ summary *)

type tally = {
  mutable agree : int;
  mutable split : int;
  mutable toofew : int;
  mutable per_engine_skips : (string * int ref) list;
}

let new_tally () = { agree = 0; split = 0; toofew = 0; per_engine_skips = [] }

let record t (o : Consensus.outcome) =
  (match o.verdict with
   | Consensus.Agree _ -> t.agree <- t.agree + 1
   | Consensus.Split _ -> t.split <- t.split + 1
   | Consensus.TooFew -> t.toofew <- t.toofew + 1);
  List.iter (fun (id, _) ->
      match List.assoc_opt id t.per_engine_skips with
      | Some n -> incr n
      | None -> t.per_engine_skips <- (id, ref 1) :: t.per_engine_skips)
    o.skipped

let print_summary t total =
  Printf.printf "\n%s\n" (bold "─────────────────────────────────────────────");
  Printf.printf "%s  %d files: %s agree, %s diverge, %d with too few engines\n"
    (bold "consensus")
    total
    (green (string_of_int t.agree))
    ((if t.split > 0 then red else green) (string_of_int t.split))
    t.toofew;
  if t.per_engine_skips <> [] then begin
    let parts =
      List.sort (fun (a, _) (b, _) -> compare a b) t.per_engine_skips
      |> List.map (fun (id, n) -> Printf.sprintf "%s %d" id !n)
    in
    Printf.printf "%s      %s\n" (dim "did not run") (dim (String.concat "  ·  " parts))
  end

(* --------------------------------------------------------------------- JSON *)

let json_escape s =
  let b = Buffer.create (String.length s + 8) in
  String.iter (fun ch ->
      match ch with
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | ch when Char.code ch < 0x20 ->
        Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code ch))
      | ch -> Buffer.add_char b ch) s;
  Buffer.contents b

let json_of_outcome (o : Consensus.outcome) =
  let b = Buffer.create 256 in
  Buffer.add_string b (Printf.sprintf "{\"file\":\"%s\"," (json_escape o.file));
  (match o.verdict with
   | Consensus.Agree _ -> Buffer.add_string b "\"verdict\":\"agree\""
   | Consensus.TooFew -> Buffer.add_string b "\"verdict\":\"too_few\""
   | Consensus.Split classes ->
     Buffer.add_string b "\"verdict\":\"diverge\",\"classes\":[";
     List.iteri (fun i (out, ids) ->
         if i > 0 then Buffer.add_char b ',';
         Buffer.add_string b
           (Printf.sprintf "{\"engines\":[%s],\"output\":\"%s\"}"
              (String.concat "," (List.map (fun s -> "\"" ^ s ^ "\"") ids))
              (json_escape out))) classes;
     Buffer.add_char b ']');
  if o.skipped <> [] then begin
    Buffer.add_string b ",\"skipped\":{";
    List.iteri (fun i (id, st) ->
        if i > 0 then Buffer.add_char b ',';
        Buffer.add_string b
          (Printf.sprintf "\"%s\":\"%s\"" id (Engine.status_name st))) o.skipped;
    Buffer.add_char b '}'
  end;
  Buffer.add_char b '}';
  Buffer.contents b
