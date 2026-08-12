(* Golden files: does this engine still print what it printed the day the
   `.expected` was recorded?

   This is a different question from consensus, and the corpus needs both.
   Consensus asks whether the engines agree, which catches a divergence but is
   blind to all four drifting together.  A golden catches the drift and is
   blind to nothing else — it only knows what one engine printed once.  553 of
   the corpus's 588 files carry one.

   Two ways to produce the output, because the corpus holds two kinds of
   golden:

     Run     `zymbol run FILE`, streams merged, warnings stripped.
             What expected_compare.sh did, over everything except
             errors/semantic/.
     Check   `zymbol check FILE`, streams merged, ANSI stripped.
             What semantic_compare.sh did, over errors/semantic/ only —
             those files are *supposed* to fail, so running them proves
             nothing and analysing them proves everything.

   The output filters below are reproduced exactly, not improved.  553 files
   were recorded through them; a better filter here is a mass regeneration of
   the corpus, which is a decision, not a tidy-up. *)

type how = Run | Check

let how_name = function Run -> "run" | Check -> "check"

type res =
  | Pass
  | Mismatch of (int * string * string) option   (* line, golden, actual *)
  | Excused of Corpus.rule                       (* corpus.toml says not this engine *)
  | Cant of Engine.status                        (* engine missing, timed out, refused *)

type outcome = { rel : string; per_engine : (string * res) list }

(* ------------------------------------------------------------- filtering *)

let starts_with p s =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

(* expected_compare.sh's `strip_warnings`, line for line.

   It drops every blank line and every line starting with three spaces, which
   means a golden cannot represent indented or blank output at all.  That is a
   real limitation of the corpus and it is preserved deliberately: the 553
   recorded files were written through this filter, so relaxing it would fail
   them in bulk without a single engine having changed. *)
let strip_warnings (s : string) =
  String.split_on_char '\n' s
  |> List.filter (fun l ->
      not (starts_with "warning:" l
           || starts_with "  -->" l
           || starts_with "   " l
           || starts_with "  =" l
           || l = ""))
  |> String.concat "\n"

(* semantic_compare.sh's `strip_ansi`: sed 's/\x1b\[[0-9;]*m//g'. *)
let strip_ansi (s : string) =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '\027' && !i + 1 < n && s.[!i + 1] = '[' then begin
      let j = ref (!i + 2) in
      while !j < n && (s.[!j] = ';' || (s.[!j] >= '0' && s.[!j] <= '9')) do incr j done;
      if !j < n && s.[!j] = 'm' then i := !j + 1
      else begin Buffer.add_char b s.[!i]; incr i end
    end else begin Buffer.add_char b s.[!i]; incr i end
  done;
  Buffer.contents b

(* Both scripts captured with `$(...)`, which drops trailing newlines from the
   command's output and from `cat`ting the golden.  Reproduce it on both sides
   or every single file fails on a newline. *)
let chomp s =
  let n = ref (String.length s) in
  while !n > 0 && s.[!n - 1] = '\n' do decr n done;
  String.sub s 0 !n

(* The engine is run with the two streams sharing one descriptor, exactly as
   `2>&1` does, so [stdout] already holds both in the order the process wrote
   them; [stderr] is empty.  Concatenating two separately captured pipes would
   not be the same thing — see [Engine.run]'s `merge`. *)
let normalise how (r : Engine.result) =
  chomp (match how with
      | Run -> strip_warnings r.stdout
      | Check -> strip_ansi r.stdout)

(* ------------------------------------------------------------------ running *)

let golden_path file = Filename.remove_extension file ^ ".expected"
let has_golden file = Sys.file_exists (golden_path file)

(* What an engine printed, reduced to the part the program is responsible for:
   the recorded filter, then the redactions, then the corpus root removed from
   any path it mentions. *)
let observed ~(corpus : Corpus.t) ~(root : string) ~(how : how) (r : Engine.result) =
  Corpus.strip_root ~root (Corpus.redact corpus (normalise how r))

let run_one ?(timeout = 10) ~(corpus : Corpus.t) ~(root : string) ~(how : how)
    (engines : Engine.engine list) ~(file : string) ~(rel : string) : outcome =
  let stdin_file = Filename.remove_extension file ^ ".input" in
  let stdin_file = if Sys.file_exists stdin_file then Some stdin_file else None in
  let golden = chomp (Toml.read_file (golden_path file)) in
  let eng_how = match how with Run -> `Run | Check -> `Check in
  (* Only pay for the engines that are actually going to be judged. *)
  let judged, excused =
    List.partition (fun (e : Engine.engine) ->
        Corpus.excused ~path:file corpus ~engine:e.id ~rel = None)
      engines
  in
  let results =
    if judged = [] then []
    else Engine.run_all ~timeout ?stdin_file ~how:eng_how ~merge:true judged ~file
  in
  let per_engine =
    List.map (fun (r : Engine.result) ->
        match r.status with
        | Engine.Completed ->
          let actual = observed ~corpus ~root ~how r in
          if Corpus.golden_matches corpus ~golden ~actual then (r.eid, Pass)
          else (r.eid, Mismatch (Corpus.first_mismatch corpus ~golden ~actual))
        | st -> (r.eid, Cant st))
      results
    @ List.map (fun (e : Engine.engine) ->
        match Corpus.excused ~path:file corpus ~engine:e.id ~rel with
        | Some rule -> (e.id, Excused rule)
        | None -> (e.id, Cant Engine.Unavailable))
      excused
  in
  (* Keep the caller's engine order; partitioning above scrambled it. *)
  let per_engine =
    List.filter_map (fun (e : Engine.engine) ->
        Option.map (fun v -> (e.id, v)) (List.assoc_opt e.id per_engine))
      engines
  in
  { rel; per_engine }

let is_failure = function Mismatch _ -> true | _ -> false

let failed (o : outcome) = List.exists (fun (_, v) -> is_failure v) o.per_engine

(* ------------------------------------------------------------ regeneration *)

(* Recording a golden is how the corpus is maintained, so it belongs here
   rather than in a script beside the interpreter — otherwise the point of
   record can check goldens but not produce them, and the corpus goes on being
   maintained from somewhere else.

   Deliberately one engine at a time and never a default: a golden is one
   engine's answer, and which engine recorded it is the whole meaning of the
   file. *)
type regen = Wrote | Unchanged | Cannot of Engine.status

let record ?(timeout = 10) ~(corpus : Corpus.t) ~(root : string) ~(how : how)
    (e : Engine.engine) ~(file : string) : regen =
  let stdin_file = Filename.remove_extension file ^ ".input" in
  let stdin_file = if Sys.file_exists stdin_file then Some stdin_file else None in
  let eng_how = match how with Run -> `Run | Check -> `Check in
  let r = Engine.run ~timeout ?stdin_file ~how:eng_how ~merge:true e ~file in
  match r.status with
  | Engine.Completed ->
    let out = observed ~corpus ~root ~how r in
    let path = golden_path file in
    let old = if Sys.file_exists path then chomp (Toml.read_file path) else "\000" in
    if String.equal old out then Unchanged
    else begin
      let oc = open_out_bin path in
      output_string oc out;
      output_char oc '\n';
      close_out oc;
      Wrote
    end
  | st -> Cannot st
