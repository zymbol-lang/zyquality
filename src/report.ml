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

let skip_note = function
  | Consensus.Status st -> status_note st
  | Consensus.Excused (r : Corpus.rule) ->
    "excused" ^ (if r.tag = "" then "" else " [" ^ r.tag ^ "]")

(* An engine that printed nothing usually printed a *reason* on stderr.  Showing
   `<empty>` for it would hide the most informative line in the report — the
   tree-walker's overflow error is the whole finding in pow_overflow. *)
let class_preview (v : Consensus.vote) =
  let body =
    if String.trim v.out <> "" then preview v.out
    else if String.trim v.err <> "" then dim "stderr: " ^ preview ~width:46 v.err
    else preview v.out
  in
  match v.verdict with
  | Engine.Ok -> body
  | Engine.Failed -> red "ERROR " ^ body

let print_divergence (o : Consensus.outcome) =
  match o.verdict with
  | Consensus.Split classes ->
    Printf.printf "\n%s %s\n" (red "DIVERGE") (bold o.rel);
    List.iter (fun (v, ids) ->
        Printf.printf "    %-22s %s\n" (String.concat "," ids) (class_preview v))
      classes;
    if o.skipped <> [] then
      Printf.printf "    %s\n"
        (dim ("(" ^ String.concat ", "
                (List.map (fun (id, w) -> id ^ ": " ^ skip_note w) o.skipped)
              ^ ")"))
  | _ -> ()

let print_verbose (o : Consensus.outcome) =
  match o.verdict with
  | Consensus.Agree _ -> Printf.printf "  %s  %s\n" (green "AGREE") o.rel
  | Consensus.TooFew ->
    Printf.printf "  %s   %s  %s\n" (yellow "FEW") o.rel
      (dim (if o.skipped = [] then "no engine ran it"
            else String.concat ", "
                (List.map (fun (id, w) -> id ^ ": " ^ skip_note w) o.skipped)))
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

let rule = bold "─────────────────────────────────────────────"

let print_summary t total =
  Printf.printf "\n%s\n" rule;
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

(* ------------------------------------------------------------------ goldens *)

let print_golden (o : Golden.outcome) ~verbose =
  let bad = List.filter (fun (_, v) -> Golden.is_failure v) o.per_engine in
  if bad <> [] then begin
    Printf.printf "\n%s %s\n" (red "STALE") (bold o.rel);
    List.iter (fun (eid, v) ->
        match v with
        | Golden.Mismatch (Some (ln, g, a)) ->
          Printf.printf "    %-8s %s %d\n" eid (dim "first difference at line") ln;
          Printf.printf "        %s %s\n" (dim "golden|") (preview ~width:64 g);
          Printf.printf "        %s %s\n" (dim "actual|") (preview ~width:64 a)
        | Golden.Mismatch None ->
          Printf.printf "    %-8s %s\n" eid (dim "differs, but no line does")
        | _ -> ())
      bad
  end else if verbose then
    Printf.printf "  %s  %s  %s\n" (green "MATCH") o.rel
      (dim (String.concat "," (List.map fst o.per_engine)))

type gtally = {
  mutable gpass : int;
  mutable gfail : int;
  mutable gskip : int;
  mutable gnone : int;   (* every engine excused or missing: nothing was checked *)
}

let new_gtally () = { gpass = 0; gfail = 0; gskip = 0; gnone = 0 }

let grecord t (o : Golden.outcome) =
  let judged = List.filter (fun (_, v) ->
      match v with Golden.Pass | Golden.Mismatch _ -> true | _ -> false)
      o.per_engine
  in
  if judged = [] then t.gnone <- t.gnone + 1
  else if Golden.failed o then t.gfail <- t.gfail + 1
  else t.gpass <- t.gpass + 1;
  t.gskip <- t.gskip + List.length o.per_engine - List.length judged

let print_gsummary t total how =
  Printf.printf "\n%s\n" rule;
  Printf.printf "%s  %d goldens via `%s`: %s match, %s stale, %d unchecked\n"
    (bold "expect") total how
    (green (string_of_int t.gpass))
    ((if t.gfail > 0 then red else green) (string_of_int t.gfail))
    t.gnone;
  if t.gskip > 0 then
    Printf.printf "%s   %s\n" (dim "engine-file pairs excused or unavailable")
      (dim (string_of_int t.gskip))

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
  Buffer.add_string b (Printf.sprintf "{\"file\":\"%s\"," (json_escape o.rel));
  (match o.verdict with
   | Consensus.Agree _ -> Buffer.add_string b "\"verdict\":\"agree\""
   | Consensus.TooFew -> Buffer.add_string b "\"verdict\":\"too_few\""
   | Consensus.Split classes ->
     Buffer.add_string b "\"verdict\":\"diverge\",\"classes\":[";
     List.iteri (fun i ((v : Consensus.vote), ids) ->
         if i > 0 then Buffer.add_char b ',';
         Buffer.add_string b
           (Printf.sprintf
              "{\"engines\":[%s],\"verdict\":\"%s\",\"stdout\":\"%s\",\"stderr\":\"%s\"}"
              (String.concat "," (List.map (fun s -> "\"" ^ s ^ "\"") ids))
              (Engine.verdict_name v.verdict)
              (json_escape v.out) (json_escape v.err))) classes;
     Buffer.add_char b ']');
  if o.skipped <> [] then begin
    Buffer.add_string b ",\"skipped\":{";
    List.iteri (fun i (id, w) ->
        if i > 0 then Buffer.add_char b ',';
        Buffer.add_string b
          (Printf.sprintf "\"%s\":\"%s\"" id (json_escape (skip_note w)))) o.skipped;
    Buffer.add_char b '}'
  end;
  Buffer.add_char b '}';
  Buffer.contents b
