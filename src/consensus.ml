(* Consensus: run one program through every Zymbol engine and ask whether they
   agree.

   The model is equivalence classes rather than pairwise comparison.  With four
   engines, pairwise gives six comparisons and no clear story; grouping by
   output gives the answer directly — one class means agreement, and the shape
   of the classes says who is the odd one out.

   `10 ^ 20` produces four classes of one engine each, which is exactly the
   result that motivated this tool. *)

type verdict =
  | Agree of string                     (* one class: the shared output *)
  | Split of (string * string list) list (* output -> engines, largest first *)
  | TooFew                              (* fewer than two engines could run it *)

type outcome = {
  file : string;
  verdict : verdict;
  results : Engine.result list;
  skipped : (string * Engine.status) list;   (* engine -> why it did not count *)
}

(* Only engines that actually ran can vote.  An engine that is not installed,
   timed out, or refused the program says nothing about correctness, and
   counting it as a dissenting voice would manufacture divergences. *)
let voters (rs : Engine.result list) =
  List.filter (fun (r : Engine.result) -> r.status = Engine.Completed) rs

let classify mode (rs : Engine.result list) : verdict =
  let vs = voters rs in
  if List.length vs < 2 then TooFew
  else begin
    let classes : (string * string list ref) list ref = ref [] in
    List.iter (fun (r : Engine.result) ->
        match List.find_opt (fun (rep, _) -> Compare.equal mode rep r.stdout) !classes with
        | Some (_, ids) -> ids := r.eid :: !ids
        | None -> classes := !classes @ [ (r.stdout, ref [ r.eid ]) ])
      vs;
    match !classes with
    | [ (out, _) ] -> Agree out
    | cs ->
      let cs = List.map (fun (out, ids) -> (out, List.rev !ids)) cs in
      (* Largest class first: the majority reading is the interesting baseline,
         and what dissents from it is the finding. *)
      Split (List.stable_sort
               (fun (_, a) (_, b) -> compare (List.length b) (List.length a)) cs)
  end

let run ?(timeout = 10) ~(mode : Compare.mode) (engines : Engine.engine list)
    ~(file : string) : outcome =
  let stdin_file = Filename.remove_extension file ^ ".input" in
  let stdin_file = if Sys.file_exists stdin_file then Some stdin_file else None in
  let results = Engine.run_all ~timeout ?stdin_file engines ~file in
  let skipped =
    List.filter_map (fun (r : Engine.result) ->
        if r.status = Engine.Completed then None else Some (r.eid, r.status))
      results
  in
  { file; verdict = classify mode results; results; skipped }
