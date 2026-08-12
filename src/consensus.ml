(* Consensus: run one program through every Zymbol engine and ask whether they
   agree.

   The model is equivalence classes rather than pairwise comparison.  With four
   engines, pairwise gives six comparisons and no clear story; grouping by
   output gives the answer directly — one class means agreement, and the shape
   of the classes says who is the odd one out.

   `10 ^ 20` produces four classes of one engine each, which is exactly the
   result that motivated this tool. *)

(* What an engine's answer consists of.

   Originally this was stdout alone, which cannot tell "printed nothing and
   ran" apart from "printed nothing and refused to compile".  That is not a
   corner case: it is the exact shape of the `@:label!` bug — a label that was
   never declared, which one engine rejected, one ignored and two treated as a
   third thing, all of them printing the same empty stdout.  Every pairwise
   suite passed it.

   So a vote is stdout *and* a verdict.  Not the error text: engines word
   diagnostics differently and always will, and requiring that to match would
   report a divergence on every rejected program in the corpus.  `--strict`
   asks for it anyway, for the day that becomes the work. *)
type vote = { out : string; verdict : Engine.verdict; err : string }

type verdict =
  | Agree of vote                        (* one class: the shared answer *)
  | Split of (vote * string list) list   (* answer -> engines, largest first *)
  | TooFew                               (* fewer than two engines could run it *)

type why_out =
  | Status of Engine.status              (* missing, timed out, refused *)
  | Excused of Corpus.rule               (* corpus.toml says not this engine *)

type outcome = {
  file : string;
  rel : string;
  verdict : verdict;
  results : Engine.result list;
  skipped : (string * why_out) list;
}

(* Only engines that actually ran can vote.  An engine that is not installed,
   timed out, or refused the program says nothing about correctness, and
   counting it as a dissenting voice would manufacture divergences. *)
let voters (rs : Engine.result list) =
  List.filter (fun (r : Engine.result) -> r.status = Engine.Completed) rs

let same_vote ~mode ~strict (a : vote) (b : vote) =
  a.verdict = b.verdict
  && Compare.equal mode a.out b.out
  && (not strict || Compare.equal mode a.err b.err)

let classify ~mode ~strict (votes : (string * vote) list) : verdict =
  if List.length votes < 2 then TooFew
  else begin
    let classes : (vote * string list ref) list ref = ref [] in
    List.iter (fun (eid, v) ->
        match List.find_opt (fun (rep, _) -> same_vote ~mode ~strict rep v) !classes with
        | Some (_, ids) -> ids := eid :: !ids
        | None -> classes := !classes @ [ (v, ref [ eid ]) ])
      votes;
    match !classes with
    | [ (v, _) ] -> Agree v
    | cs ->
      let cs = List.map (fun (v, ids) -> (v, List.rev !ids)) cs in
      (* Largest class first: the majority reading is the interesting baseline,
         and what dissents from it is the finding. *)
      Split (List.stable_sort
               (fun (_, a) (_, b) -> compare (List.length b) (List.length a)) cs)
  end

let run ?(timeout = 10) ?(strict = false) ~(mode : Compare.mode)
    ~(corpus : Corpus.t) ~(root : string) (engines : Engine.engine list)
    ~(file : string) ~(rel : string) : outcome =
  let stdin_file = Filename.remove_extension file ^ ".input" in
  let stdin_file = if Sys.file_exists stdin_file then Some stdin_file else None in
  (* An engine the corpus excuses for this file is never started.  Running it
     and discarding the answer would be the same verdict at four times the
     cost, over 588 files. *)
  let judged, excused =
    List.partition (fun (e : Engine.engine) ->
        Corpus.excused ~path:file corpus ~engine:e.id ~rel = None)
      engines
  in
  let results =
    if judged = [] then [] else Engine.run_all ~timeout ?stdin_file judged ~file
  in
  (* Where the corpus sits is not something the program decided, and under
     --strict a diagnostic quoting an absolute path would otherwise make every
     engine its own equivalence class on this machine and a different set on
     the next one. *)
  let clean s = Corpus.strip_root ~root (Corpus.redact corpus s) in
  let votes =
    List.map (fun (r : Engine.result) ->
        (r.eid, { out = clean r.stdout; err = clean r.stderr;
                  verdict = Engine.verdict_of r }))
      (voters results)
  in
  let skipped =
    List.filter_map (fun (r : Engine.result) ->
        if r.status = Engine.Completed then None else Some (r.eid, Status r.status))
      results
    @ List.filter_map (fun (e : Engine.engine) ->
        match Corpus.excused ~path:file corpus ~engine:e.id ~rel with
        | Some rule -> Some (e.id, Excused rule)
        | None -> None)
      excused
  in
  { file; rel; verdict = classify ~mode ~strict votes; results; skipped }
