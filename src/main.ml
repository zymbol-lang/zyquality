(* ZyQuality — the Zymbol project's point of record for testing.

     zyq engines                    what is installed and what is not
     zyq consensus [opts]           the corpus through every engine
     zyq expect [opts]              the corpus against its .expected goldens
     zyq reject [opts]              forms every engine must refuse
     zyq audit                      the corpus's own hygiene
     zyq selftest                   zyq's matcher, globs and config reader
     zyq suite                      all of the above, one verdict
     zyq show FILE.zy               what each engine says about one file

   Exit status is the contract other repositories' test scripts rely on:

     0  everything that could be checked, passed
     1  a real failure — engines disagree, a golden is stale, a form that
        must be refused was accepted
     2  could not run: no engines, bad config, empty corpus.  Never 0: a gate
        must not read "nothing ran" as "nothing failed"
     3  asked for something not implemented yet *)

let version = "0.2.0"

(* ------------------------------------------------------------- file walking *)

let rec collect dir acc =
  if not (Sys.file_exists dir) then acc
  else if Sys.is_directory dir then
    Array.fold_left (fun acc entry -> collect (Filename.concat dir entry) acc)
      acc (Sys.readdir dir)
  else if Filename.check_suffix dir ".zy" then dir :: acc
  else acc

let zy_files root = List.sort compare (collect root [])

(* Paths are reported and matched corpus-relative: `loops/labels/01.zy`, not
   `/home/…/zyquality/corpus/loops/labels/01.zy`.  Every rule in corpus.toml is
   written that way, and so is every line of a report anybody has to read. *)
let relative_to root path =
  let r = if Filename.check_suffix root "/" then root else root ^ "/" in
  let rl = String.length r in
  if String.length path >= rl && String.sub path 0 rl = r
  then String.sub path rl (String.length path - rl)
  else path

(* ------------------------------------------------------------------ options *)

type opts = {
  mutable corpus : string;
  mutable reject_dir : string;
  mutable engines_file : string;
  mutable corpus_file : string;
  mutable only : string list;        (* engine ids; empty means all *)
  mutable filter : string list;      (* all must match; they narrow *)
  mutable without : string list;     (* tags to drop *)
  mutable verbose : bool;
  mutable json : bool;
  mutable strict : bool;
  mutable timeout : int;
  mutable mode : Compare.mode;
  mutable via : string option;       (* expect: force run | check *)
  mutable regen : bool;
  mutable regen_new : bool;          (* also record files that have no golden *)
  mutable suites_file : string;
  mutable only_suites : string list; (* --only: run just these script suites *)
}

let default_opts () = {
  corpus = "corpus";
  reject_dir = "reject";
  engines_file = "engines.toml";
  corpus_file = "corpus.toml";
  only = [];
  filter = [];
  without = [];
  verbose = false;
  json = false;
  strict = false;
  timeout = 10;
  mode = Compare.Exact;
  via = None;
  regen = false;
  regen_new = false;
  suites_file = "suites.toml";
  only_suites = [];
}

let split_commas s = List.filter (( <> ) "") (String.split_on_char ',' s)

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let die code fmt = Printf.ksprintf (fun s -> prerr_endline ("zyq: " ^ s); exit code) fmt

let usage code =
  let p = prerr_endline in
  p "ZyQuality — the Zymbol project's point of record for testing";
  p "";
  p "  zyq suite [options]          consensus + goldens + rejections, one verdict";
  p "  zyq consensus [options]      run the corpus through every engine";
  p "  zyq expect [options]         check the corpus against its .expected goldens";
  p "  zyq reject [options]         forms every engine must refuse";
  p "  zyq audit                    corpus hygiene: dead rules, orphans, gaps";
  p "  zyq selftest                 zyq's own matcher, globs and config reader";
  p "  zyq suites                   list the script suites and what they need";
  p "  zyq engines                  list engines and availability";
  p "  zyq show FILE.zy             what each engine says about one file";
  p "";
  p "options:";
  p "  --root DIR       where corpus/, engines.toml and corpus.toml live";
  p "                   (default: $ZYQ_ROOT, else zyq's own directory)";
  p "  --corpus DIR     corpus root (default: <root>/corpus)";
  p "  --engines a,b    only these engine ids";
  p "  --filter TEXT    only files whose corpus-relative path contains TEXT";
  p "                   (repeatable: each one narrows further)";
  p "  --without TAG    drop every file tagged TAG in corpus.toml (repeatable)";
  p "  --via run|check  expect: force how goldens are produced";
  p "  --regen          expect: re-record existing goldens from one named engine";
  p "                   (--engines takes exactly one; review the diff)";
  p "  --new            with --regen: also record files that have no golden yet";
  p "  --mode M         exact | lines | numeric   (default: exact)";
  p "  --tol T          numeric tolerance: '2ulp' or '1e-9'";
  p "  --strict         consensus: require the error text to match too";
  p "  --timeout N      seconds per engine (default: 10)";
  p "  -v, --verbose    show agreeing files too";
  p "  --json           machine-readable output";
  p "  --only a,b       suite: run only these script suites (fmt, tui, guide, bench)";
  p "  --no-colour      plain text";
  exit code

(* The root has to be settled before anything else is read, and it is not an
   ordinary option: engines.toml, corpus.toml and corpus/ are all relative to
   it.  Precedence is explicit flag, then environment, then where the binary
   sits, then the current directory. *)
let resolve_root argv =
  let rec find = function
    | "--root" :: v :: _ -> Some v
    | _ :: t -> find t
    | [] -> None
  in
  match find argv with
  | Some d -> d
  | None ->
    match Sys.getenv_opt "ZYQ_ROOT" with
    | Some d when d <> "" -> d
    | _ -> (match Engine.guess_root () with Some d -> d | None -> Sys.getcwd ())

(* --root is global, so it has to be accepted before the subcommand as well as
   after it: a wrapper naturally writes `zyq --root DIR consensus …`, and the
   dispatch below reads the first word as the command. *)
let rec strip_root = function
  | "--root" :: _ :: t -> strip_root t
  | a :: t -> a :: strip_root t
  | [] -> []

let parse_args argv =
  let o = default_opts () in
  let tol = ref (Compare.Ulp 1) in
  let mode_name = ref "exact" in
  let rec go = function
    | [] -> ()
    | "--corpus" :: v :: t -> o.corpus <- v; go t
    | "--reject" :: v :: t -> o.reject_dir <- v; go t
    | "--engines-file" :: v :: t -> o.engines_file <- v; go t
    | "--corpus-file" :: v :: t -> o.corpus_file <- v; go t
    | "--engines" :: v :: t -> o.only <- split_commas v; go t
    | "--filter" :: v :: t -> o.filter <- o.filter @ [ v ]; go t
    | "--without" :: v :: t -> o.without <- o.without @ split_commas v; go t
    | "--via" :: v :: t ->
      if v <> "run" && v <> "check" then die 2 "--via takes run or check, not %s" v;
      o.via <- Some v; go t
    | "--mode" :: v :: t -> mode_name := v; go t
    | "--tol" :: v :: t ->
      (match Compare.parse_tol v with
       | Some x -> tol := x
       | None -> die 2 "bad tolerance: %s" v);
      go t
    | "--timeout" :: v :: t ->
      (match int_of_string_opt v with
       | Some n when n > 0 -> o.timeout <- n
       | _ -> die 2 "bad timeout: %s" v);
      go t
    | "--regen" :: t -> o.regen <- true; go t
    | "--new" :: t -> o.regen_new <- true; go t
    | "--suites-file" :: v :: t -> o.suites_file <- v; go t
    | "--only" :: v :: t -> o.only_suites <- o.only_suites @ split_commas v; go t
    | ("-v" | "--verbose") :: t -> o.verbose <- true; go t
    | "--strict" :: t -> o.strict <- true; go t
    | "--json" :: t -> o.json <- true; Report.use_colour := false; go t
    | "--no-colour" :: t -> Report.use_colour := false; go t
    | ("-h" | "--help") :: _ -> usage 0
    | a :: _ -> prerr_endline ("zyq: unknown option: " ^ a); usage 2
  in
  go argv;
  (match Compare.parse_mode ~tol:!tol !mode_name with
   | Some m -> o.mode <- m
   | None -> die 2 "bad mode: %s" !mode_name);
  o

(* ------------------------------------------------------------------ loading *)

let load_corpus_cfg o =
  try Corpus.load (Engine.under o.corpus_file)
  with Toml.Error m -> die 2 "%s" m | Rx.Error m -> die 2 "bad pattern: %s" m

let load_engines ?only o =
  let only = match only with Some l -> l | None -> o.only in
  let all =
    try Engine.load_engines (Engine.under o.engines_file)
    with Toml.Error m -> die 2 "%s" m
  in
  List.iter (fun id ->
      if not (List.exists (fun (e : Engine.engine) -> e.id = id) all) then
        die 2 "no engine with id '%s' in %s" id o.engines_file)
    only;
  let wanted =
    if only = [] then
      (* Consensus is about the engines under test.  An oracle runs a different
         language and has no opinion on what a .zy file prints. *)
      List.filter (fun (e : Engine.engine) -> e.lang = "zymbol") all
    else
      List.filter (fun (e : Engine.engine) -> List.mem e.id only) all
  in
  if wanted = [] then die 2 "no engines selected";
  wanted

(* An engine listed but not installed must be said out loud.  Silently
   comparing three engines when the caller asked for four is how a suite
   reports "all green" for something it never ran. *)
let announce_missing engines =
  let missing = List.filter (fun e -> not (Engine.available e)) engines in
  if missing <> [] then begin
    Printf.eprintf "%s %s\n"
      (Report.yellow "not installed:")
      (String.concat ", " (List.map (fun (e : Engine.engine) -> e.id) missing));
    List.iter (fun (e : Engine.engine) ->
        Printf.eprintf "  %-6s %s\n" e.id (Report.dim (String.concat " " e.cmd)))
      missing
  end;
  List.filter (fun e -> not (List.memq e missing)) engines

let corpus_root o = Engine.under o.corpus

let select o (corpus : Corpus.t) root =
  let files = zy_files root in
  if files = [] then
    die 2 "no .zy files under %s\n  point --corpus at the corpus root" root;
  let keep f =
    let rel = relative_to root f in
    List.for_all (fun pat -> contains rel pat) o.filter
    && (o.without = []
        || (match Corpus.excused corpus ~engine:"*" ~rel with
            | Some r -> not (List.mem r.tag o.without)
            | None ->
              (* --without must also drop files whose tag applies per engine.
                 Check every rule, not only the ones excusing everybody. *)
              not (List.exists (fun (r : Corpus.rule) ->
                  List.mem r.tag o.without && Corpus.glob_match r.pat rel)
                  corpus.rules)))
  in
  List.filter keep files

(* -------------------------------------------------------------- subcommands *)

let cmd_engines o =
  let all =
    try Engine.load_engines (Engine.under o.engines_file)
    with Toml.Error m -> die 2 "%s" m
  in
  Printf.printf "%-8s %-8s %-9s %-7s %s\n" "id" "lang" "state" "check" "description";
  List.iter (fun (e : Engine.engine) ->
      let r = Engine.probe e in
      let ok = r.status = Engine.Completed && r.code = 0 in
      (* Pad before colouring: printf counts the escape bytes as width. *)
      let plain, paint =
        if ok then "ready", Report.green
        else if r.status = Engine.Unavailable then "missing", Report.red
        else "broken", Report.red
      in
      let state = paint (Printf.sprintf "%-8s" plain) in
      let chk = if Engine.can e `Check then "yes" else Report.dim "no " in
      Printf.printf "%-8s %-8s %s %-7s %s\n" e.id e.lang state chk e.desc;
      (* An engine that starts and then fails on an empty program is configured
         wrongly, and saying only "missing" would send someone looking for a
         binary that is right there.  Show what it said. *)
      if not ok then begin
        Printf.printf "         %s %s\n" (Report.dim "cmd|") (String.concat " " e.cmd);
        List.iter (fun l ->
            if String.trim l <> "" then
              Printf.printf "         %s %s\n" (Report.dim "err|") l)
          (List.filteri (fun i _ -> i < 3)
             (String.split_on_char '\n' (String.trim (r.stderr ^ r.stdout))))
      end) all

(* What each engine actually said about one file — the tool you reach for once
   consensus has told you something diverges. *)
let cmd_show o file =
  let engines = load_engines o in
  let stdin_file = Filename.remove_extension file ^ ".input" in
  let stdin_file = if Sys.file_exists stdin_file then Some stdin_file else None in
  List.iter (fun (e : Engine.engine) ->
      let r = Engine.run ~timeout:o.timeout ?stdin_file e ~file in
      Printf.printf "%s  %s  %s  %s  %.0f ms\n"
        (Report.bold (Printf.sprintf "%-6s" e.id))
        (Report.dim (Printf.sprintf "exit=%-3d" r.code))
        (Report.dim (Engine.status_name r.status))
        (match Engine.verdict_of r with
         | Engine.Ok -> Report.green "OK" | Engine.Failed -> Report.red "ERROR")
        r.wall_ms;
      let dump label s =
        if String.trim s <> "" then
          List.iter (fun l -> Printf.printf "    %s %s\n" (Report.dim label) l)
            (List.filter (fun l -> l <> "")
               (String.split_on_char '\n' (String.trim s)))
      in
      dump "out|" r.stdout;
      dump "err|" r.stderr)
    engines

let cmd_consensus o =
  let corpus = load_corpus_cfg o in
  let engines = announce_missing (load_engines o) in
  if List.length engines < 2 then
    die 2 "consensus needs at least two installed engines; %d available"
      (List.length engines);
  let root = corpus_root o in
  let files = select o corpus root in
  if not o.json then
    Printf.printf "%s %d files × %d engines (%s)%s\n"
      (Report.bold "consensus") (List.length files) (List.length engines)
      (String.concat ", " (List.map (fun (e : Engine.engine) -> e.id) engines))
      (if o.strict then Report.dim "  [strict: error text must match]" else "");
  let tally = Report.new_tally () in
  let first = ref true in
  if o.json then print_string "{\"outcomes\":[";
  List.iter (fun file ->
      let rel = relative_to root file in
      let out =
        Consensus.run ~timeout:o.timeout ~strict:o.strict ~mode:o.mode ~corpus
          ~root engines ~file ~rel
      in
      Report.record tally out;
      if o.json then begin
        if not !first then print_string ",";
        first := false;
        print_string (Report.json_of_outcome out)
      end else if o.verbose then Report.print_verbose out
      else Report.print_divergence out)
    files;
  if o.json then
    Printf.printf "],\"summary\":{\"total\":%d,\"agree\":%d,\"diverge\":%d,\"too_few\":%d}}\n"
      (List.length files) tally.agree tally.split tally.toofew
  else Report.print_summary tally (List.length files);
  (* A divergence is a failure; an engine that could not run is not. *)
  if tally.split > 0 then 1 else 0

(* Re-record the goldens.  Separate from checking them on purpose: this is the
   one operation in zyq that writes to the corpus, and it must be impossible to
   reach by accident or without naming the engine whose answer is being
   frozen. *)
let cmd_regen o corpus engines root files want_via =
  (match engines with
   | [ _ ] -> ()
   | es ->
     die 2 "--regen records one engine's answer, so name exactly one: --engines <id>\n  selected: %s"
       (String.concat "," (List.map (fun (e : Engine.engine) -> e.id) es)));
  let e = List.hd engines in
  Printf.printf "%s %d goldens from %s\n"
    (Report.bold "regen") (List.length files) (Report.bold e.id);
  let wrote = ref 0 and same = ref 0 and cannot = ref 0 and made = ref 0 in
  List.iter (fun file ->
      let rel = relative_to root file in
      let via = want_via rel in
      let how = if via = "check" then Golden.Check else Golden.Run in
      let fresh = not (Golden.has_golden file) in
      (* A file no engine is judged on gets no golden: recording one would
         create something that is never compared and never noticed when it
         goes wrong. *)
      if Corpus.excused_everywhere ~path:file corpus ~rel <> None then begin
        if o.verbose then
          Printf.printf "  %s %s %s\n" (Report.dim "skip ") rel
            (Report.dim "excused for every engine")
      end
      else if not (Engine.can e (if via = "check" then `Check else `Run)) then begin
        incr cannot;
        Printf.printf "  %s %s %s\n" (Report.yellow "SKIP ") rel
          (Report.dim ("no " ^ via ^ " command for " ^ e.id))
      end else
        match Golden.record ~timeout:o.timeout ~corpus ~root ~how e ~file with
        | Golden.Wrote when fresh ->
          incr made; Printf.printf "  %s %s\n" (Report.cyan "NEW  ") rel
        | Golden.Wrote ->
          incr wrote; Printf.printf "  %s %s\n" (Report.cyan "WROTE") rel
        | Golden.Unchanged ->
          incr same; if o.verbose then Printf.printf "  %s  %s\n" (Report.dim "same") rel
        | Golden.Cannot st ->
          incr cannot;
          Printf.printf "  %s %s %s\n" (Report.yellow "SKIP ") rel
            (Report.dim (Engine.status_name st)))
    files;
  Printf.printf "\n%s\n" Report.rule;
  Printf.printf "%s      %d rewritten, %d newly recorded, %d already current, %d could not be recorded\n"
    (Report.bold "regen") !wrote !made !same !cannot;
  Printf.printf "%s\n"
    (Report.yellow "review the diff before committing: a golden is the corpus's memory");
  0

let cmd_expect o =
  let corpus = load_corpus_cfg o in
  (* A golden is one engine's answer, so unless the caller named engines, the
     ones to run are the ones that recorded them.  Comparing a second engine
     against another's golden is the consensus question wearing a disguise.

     Computed locally and passed down: writing it back into [o] would leak into
     whatever runs next, and `zyq suite` shares one options record across every
     step — which is exactly how consensus once found itself with one engine. *)
  let only =
    if o.only <> [] then o.only
    else begin
      let root = Engine.under o.corpus in
      List.sort_uniq compare
        (List.filter_map (fun f -> Corpus.golden_by corpus ~rel:(relative_to root f))
           (zy_files root))
    end
  in
  let engines = announce_missing (load_engines ~only o) in
  if engines = [] then die 2 "no installed engine to check goldens against";
  let root = corpus_root o in
  let files =
    let all = select o corpus root in
    if o.regen && o.regen_new then all
    else List.filter Golden.has_golden all in
  if files = [] then die 2 "no .zy file under %s has a .expected beside it" root;
  (* How the golden was recorded: `zymbol run` for most of the corpus,
     `zymbol check` for errors/semantic/.  An engine with no check_cmd is not
     judged on the second group rather than failing all of it. *)
  let want_via rel =
    match o.via with Some v -> v | None -> Corpus.golden_via corpus ~rel in
  if o.regen then cmd_regen o corpus engines root files want_via
  else begin
    let fail = ref 0 in
    List.iter (fun via ->
        let group = List.filter (fun f -> want_via (relative_to root f) = via) files in
        if group <> [] then begin
          let how = if via = "check" then Golden.Check else Golden.Run in
          let able = List.filter (fun e ->
              Engine.can e (if via = "check" then `Check else `Run)) engines in
          if able = [] then
            Printf.printf "\n%s  %d goldens recorded via `%s`, and no selected engine can %s\n"
              (Report.yellow "SKIP") (List.length group) via via
          else begin
            Printf.printf "\n%s %d goldens via `%s` × %d engines (%s)\n"
              (Report.bold "expect") (List.length group) via (List.length able)
              (String.concat ", " (List.map (fun (e : Engine.engine) -> e.id) able));
            let t = Report.new_gtally () in
            List.iter (fun file ->
                let rel = relative_to root file in
                let out =
                  Golden.run_one ~timeout:o.timeout ~corpus ~root ~how able ~file ~rel in
                Report.grecord t out;
                Report.print_golden out ~verbose:o.verbose)
              group;
            Report.print_gsummary t (List.length group) via;
            fail := !fail + t.gfail
          end
        end)
      [ "run"; "check" ];
    if !fail > 0 then 1 else 0
  end

(* Forms every engine must refuse.

   Consensus cannot see these: it compares what programs *print*, and a
   refused program prints nothing.  An engine that quietly accepts
   `m[1][2] = 77` gives the language two ways to write the same change, one of
   which hides the intent — and every stdout-comparing suite passes it. *)
let cmd_reject o =
  let engines = announce_missing (load_engines o) in
  if engines = [] then die 2 "no installed engine to check rejections against";
  let root = Engine.under o.reject_dir in
  let files = zy_files root in
  if files = [] then die 2 "no .zy files under %s" root;
  Printf.printf "%s %d forms × %d engines (%s)\n"
    (Report.bold "reject") (List.length files) (List.length engines)
    (String.concat ", " (List.map (fun (e : Engine.engine) -> e.id) engines));
  let bad = ref 0 and checked = ref 0 in
  List.iter (fun file ->
      let rel = relative_to root file in
      let results = Engine.run_all ~timeout:o.timeout engines ~file in
      let accepted =
        List.filter (fun (r : Engine.result) ->
            match r.status with
            (* `Unsupported` means the engine refused the program, which is
               the correct answer here.  Only a clean run is a failure.

               No engine declares `unsupported` prefixes since zyml was
               retired — it was the only one that did.  The branch stays
               because the field is the declared way for a new engine to say
               "I cannot run this", and a reject suite that mistook that for
               a pass would be worse than one that never saw it. *)
            | Engine.Completed -> Engine.verdict_of r = Engine.Ok
            | Engine.Unsupported -> false
            | Engine.Timeout | Engine.Unavailable -> false)
          results
      in
      let ran = List.filter (fun (r : Engine.result) ->
          r.status <> Engine.Unavailable) results in
      if ran <> [] then incr checked;
      if accepted <> [] then begin
        incr bad;
        Printf.printf "\n%s %s\n" (Report.red "ACCEPTED") (Report.bold rel);
        List.iter (fun (r : Engine.result) ->
            Printf.printf "    %-8s %s\n" r.eid
              (Report.dim "ran it and exited 0; it must be refused")) accepted;
        (* The reason is in the file, so the report can quote it rather than
           keeping a second copy that drifts. *)
        List.iter (fun l ->
            let l = String.trim l in
            let p = "// @reject:" in
            if String.length l > String.length p
            && String.sub l 0 (String.length p) = p then
              Printf.printf "    %s %s\n" (Report.dim "why|")
                (String.trim (String.sub l (String.length p)
                                (String.length l - String.length p))))
          (String.split_on_char '\n' (Toml.read_file file))
      end else if o.verbose then
        Printf.printf "  %s %s\n" (Report.green "refused ") rel)
    files;
  Printf.printf "\n%s\n" Report.rule;
  Printf.printf "%s     %d forms: %s refused everywhere, %s accepted somewhere\n"
    (Report.bold "reject")
    (List.length files)
    (Report.green (string_of_int (!checked - !bad)))
    ((if !bad > 0 then Report.red else Report.green) (string_of_int !bad));
  if !bad > 0 then 1 else 0

(* ------------------------------------------------------------ script suites *)

let load_suites o =
  try Suite.load (Engine.under o.suites_file)
  with Toml.Error m -> die 2 "%s" m

let wanted_suites o =
  let all = load_suites o in
  List.iter (fun id ->
      if not (List.exists (fun (s : Suite.spec) -> s.id = id) all) then
        die 2 "no suite with id '%s' in %s" id o.suites_file)
    o.only_suites;
  if o.only_suites = [] then all
  else List.filter (fun (s : Suite.spec) -> List.mem s.id o.only_suites) all

let cmd_suites o =
  let all = load_suites o in
  if all = [] then begin
    Printf.printf "%s\n" (Report.dim "no script suites registered"); 0
  end else begin
    Printf.printf "%-8s %-8s %-10s %s\n" "id" "gate" "state" "description";
    List.iter (fun (s : Suite.spec) ->
        let gone = Suite.unmet ~root:(Engine.under ".") s in
        let plain, paint =
          if gone = [] then "ready", Report.green else "skipped", Report.yellow in
        Printf.printf "%-8s %-8s %s %s\n" s.id
          (if s.gate then "yes" else Report.dim "no ")
          (paint (Printf.sprintf "%-10s" plain)) s.desc;
        if gone <> [] then
          Printf.printf "         %s %s\n" (Report.dim "needs|")
            (Report.dim (String.concat ", " gone)))
      all;
    0
  end

(* Run the registered script suites.  Their own output goes straight through:
   each has a report that names the file that failed, and swallowing it to
   reprint a tally would lose the only part anybody acts on. *)
let cmd_script_suites o =
  let root = Engine.under "." in
  let specs = wanted_suites o in
  let worst = ref 0 in
  List.iter (fun (s : Suite.spec) ->
      Printf.printf "\n%s %s %s\n" (Report.cyan "══") (Report.bold s.id)
        (Report.dim s.desc);
      flush stdout;
      match Suite.run ~root s with
      | Suite.Passed -> ()
      | Suite.Skipped why ->
        Printf.printf "  %s %s\n" (Report.yellow "SKIPPED") (Report.dim ("needs " ^ why))
      | Suite.Failed code ->
        Printf.printf "  %s %s\n" (Report.red "FAILED")
          (Report.dim (Printf.sprintf "exit %d%s" code
                         (if s.gate then "" else " (not a gate)")));
        if s.gate then worst := 1)
    specs;
  !worst

(* ---------------------------------------------------------------- the audit *)

(* The corpus grades 588 files, so the corpus itself has to be graded.  Each
   finding here is something that looks fine and silently reduces coverage. *)
let cmd_audit o =
  let corpus = load_corpus_cfg o in
  let root = corpus_root o in
  let files = zy_files root in
  let rels = List.map (relative_to root) files in
  let problems = ref 0 in
  let note kind msg =
    incr problems;
    Printf.printf "  %s %s\n" (Report.yellow kind) msg
  in
  Printf.printf "%s %s\n" (Report.bold "audit") (Report.dim root);

  (* A rule matching nothing describes a file somebody renamed.  Left
     unreported it becomes a rule nobody dares delete — which is how a 40-entry
     SKIP_SET accumulates. *)
  List.iter (fun (r : Corpus.rule) ->
      note "dead rule    " (Printf.sprintf "`%s` matches no file in the corpus" r.pat))
    (Corpus.dead_rules corpus ~files:rels);

  (* A .expected with no .zy is a golden for a program that no longer exists. *)
  let rec walk dir =
    if Sys.is_directory dir then
      Array.iter (fun e -> walk (Filename.concat dir e)) (Sys.readdir dir)
    else if Filename.check_suffix dir ".expected" then begin
      let zy = Filename.remove_extension dir ^ ".zy" in
      if not (Sys.file_exists zy) then
        note "orphan golden" (relative_to root dir)
    end
  in
  walk root;

  (* A .zy with no golden is only checked by consensus, which is blind to all
     engines drifting together.  Informational, not a failure — some files are
     deliberately consensus-only. *)
  let no_golden = List.filter (fun f -> not (Golden.has_golden f)) files in

  (* A golden recorded via `check` that no engine can produce is a golden
     nobody compares. *)
  let engines =
    try Engine.load_engines (Engine.under o.engines_file) with Toml.Error _ -> [] in
  let can_check = List.exists (fun e -> Engine.can e `Check) engines in
  if not can_check then
    List.iter (fun rel ->
        if Corpus.golden_via corpus ~rel = "check" then
          note "unchecked    " (rel ^ " — no engine declares a check_cmd"))
      rels;

  (* Every file the corpus excuses for *every* engine is a file nothing tests.
     That may be right, but it should be a short list somebody has read. *)
  let dead_files =
    List.filter_map (fun f ->
        let rel = relative_to root f in
        if Corpus.excused_everywhere ~path:f corpus ~rel <> None then Some rel else None)
      files in

  Printf.printf "\n%s\n" Report.rule;
  Printf.printf "%s        %d .zy · %d with goldens · %d consensus-only · %d excused for every engine\n"
    (Report.bold "corpus")
    (List.length files)
    (List.length files - List.length no_golden)
    (List.length no_golden)
    (List.length dead_files);
  if o.verbose then begin
    List.iter (fun f -> Printf.printf "    %s %s\n" (Report.dim "consensus-only|")
                  (relative_to root f)) no_golden;
    List.iter (fun rel -> Printf.printf "    %s %s\n" (Report.dim "excused|") rel)
      dead_files
  end;
  Printf.printf "%s      %s\n" (Report.dim "tags")
    (Report.dim (String.concat ", " (Corpus.tags corpus)));
  if !problems = 0 then begin
    Printf.printf "%s\n" (Report.green "no hygiene problems"); 0
  end else begin
    Printf.printf "%s %d\n" (Report.red "hygiene problems:") !problems; 1
  end

(* ------------------------------------------------------------------ selftest *)

(* zyq decides whether 588 files pass, so zyq has to be checked too — against
   cases whose answer is known by reading them.  This is not ceremony: the two
   harness defects found while producing the first consensus numbers, an argv
   list reversed by a double List.rev and a missing module resolver, both
   inflated the divergence count and neither was visible in the output. *)
let cmd_selftest () =
  let fails = ref 0 and total = ref 0 in
  let ok name cond =
    incr total;
    if not cond then begin
      incr fails;
      Printf.printf "  %s %s\n" (Report.red "FAIL") name
    end
  in
  let rx p s = try Rx.is_match (Rx.parse p) s with Rx.Error _ -> false in

  (* Rx: the shapes the wildcard table and the redactions depend on. *)
  ok "int matches"        (rx "-?[0-9]+" "-42");
  ok "int rejects float"  (not (rx "-?[0-9]+" "4.2"));
  ok "int rejects empty"  (not (rx "-?[0-9]+" ""));
  ok "float exponent"     (rx "-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?" "1.5e-9");
  ok "float bare int"     (rx "-?[0-9]+(\\.[0-9]+)?([eE][+-]?[0-9]+)?" "7");
  ok "num has no exp"     (not (rx "-?[0-9]+(\\.[0-9]+)?" "1e9"));
  ok "time ms"            (rx "[0-9]+(\\.[0-9]+)?(ms|µs|us|ns|s)" "12ms");
  ok "time s"             (rx "[0-9]+(\\.[0-9]+)?(ms|µs|us|ns|s)" "0.167s");
  ok "time µs utf8"       (rx "[0-9]+(\\.[0-9]+)?(ms|µs|us|ns|s)" "3µs");
  ok "time rejects word"  (not (rx "[0-9]+(\\.[0-9]+)?(ms|µs|us|ns|s)" "fast"));
  ok "date"               (rx "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "2026-08-11");
  ok "date rejects short" (not (rx "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" "26-08-11"));
  ok "negated class"      (rx "[^ \t\r]+" "a/b.zy");
  ok "negated excludes"   (not (rx "[^ \t\r]+" "a b"));
  ok "alternation"        (rx "(cat|dog)s" "dogs");
  ok "optional group"     (rx "ab?c" "ac");
  ok "greedy backtracks"  (rx "[0-9]+2" "1232");
  (* A pattern that could loop for ever if `*` accepted empty repetitions. *)
  ok "empty rep is safe"  (rx "(a*)*b" "aaab");

  (* Rx: replacement, which is what redaction is built on. *)
  let repl p w s = Rx.replace_all (Rx.parse p) ~with_:w s in
  ok "redact one"
    (repl "\"id\": \"[0-9a-f-]*\"" "\"id\": \"<UUID>\""
       "{\"id\": \"9f2c-11\"}" = "{\"id\": \"<UUID>\"}");
  ok "redact many"
    (repl "[0-9]+" "N" "a1b22c333" = "aNbNcN");
  ok "redact none"
    (repl "[0-9]+" "N" "abc" = "abc");

  (* Globs: `*` must not cross a separator, or an exclusion silently widens. *)
  ok "glob star"          (Corpus.glob_match "stdlib/*.zy" "stdlib/a.zy");
  ok "glob star stops"    (not (Corpus.glob_match "stdlib/*.zy" "stdlib/n/a.zy"));
  ok "glob doublestar"    (Corpus.glob_match "stress_v2/**" "stress_v2/a/b.zy");
  ok "glob exact"         (Corpus.glob_match "a/b.zy" "a/b.zy");
  ok "glob no partial"    (not (Corpus.glob_match "a/b.zy" "a/b.zyx"));
  ok "glob prefix star"   (Corpus.glob_match "stdlib/stdlib_db_*.zy" "stdlib/stdlib_db_tx.zy");

  (* Golden matching: literals stay literal.  A golden line full of brackets is
     text, and compiling it as a pattern would change what it means. *)
  let c = Corpus.{
      empty with
      wildcards = [
        { marker = "***int***"; rxw = Rx.parse "-?[0-9]+" };
        { marker = "***time***"; rxw = Rx.parse "[0-9]+(\\.[0-9]+)?(ms|µs|us|ns|s)" };
      ] }
  in
  let lm g a = Corpus.line_matches c ~golden:g ~actual:a in
  ok "golden literal"     (lm "hello" "hello");
  ok "golden literal no"  (not (lm "hello" "hallo"));
  ok "golden brackets"    (lm "[1, 2, 3]" "[1, 2, 3]");
  ok "golden pipe"        (lm "a|b" "a|b");
  ok "golden star-any"    (lm "took ****ms" "took 1234ms");
  ok "golden typed int"   (lm "n = ***int***" "n = -7");
  ok "golden typed no"    (not (lm "n = ***int***" "n = seven"));
  ok "golden two markers" (lm "***int*** in ***time***" "42 in 0.5s");
  ok "golden anchored"    (not (lm "n = ***int***" "n = 42 and more"));
  ok "golden greedy give" (lm "***int***9" "1239");
  ok "golden whole out"
    (Corpus.golden_matches c ~golden:"a\n***int***" ~actual:"a\n5");
  ok "golden line count"
    (not (Corpus.golden_matches c ~golden:"a\nb" ~actual:"a"));

  (* The in-file marker.  It replaced two markers that one runner each could
     see, so getting its parse wrong silently un-skips or over-skips a corpus
     that lives in another repository. *)
  let tmp = Filename.temp_file "zyq_marker" ".zy" in
  let write s = let oc = open_out tmp in output_string oc s; close_out oc in
  write "// @zyq-skip: because\n>> 1 ¶\n";
  ok "marker all"        (Corpus.marker_in tmp = Some ([], "because"));
  write "// @zyq-skip zyjs,zyvm: browser only\n";
  ok "marker engines"    (Corpus.marker_in tmp = Some ([ "zyjs"; "zyvm" ], "browser only"));
  (* A legacy marker excuses the engine it was about, not every engine: each
     lived in a two-engine runner where those two readings look identical. *)
  write "// @skip-parity: legacy spelling\n";
  ok "marker legacy js"  (Corpus.marker_in tmp = Some ([ "zyjs" ], "legacy spelling"));
  write "// @vm-skip\n";
  ok "marker legacy vm"  (Corpus.marker_in tmp = Some ([ "zyvm" ], ""));
  write "// @zyq-skip: everybody\n";
  ok "marker zyq is all" (Corpus.marker_in tmp = Some ([], "everybody"));
  write ">> \"@zyq-skip: not a comment\" ¶\n";
  ok "marker needs //"   (Corpus.marker_in tmp = None);
  write ">> 1 ¶\n";
  ok "marker absent"     (Corpus.marker_in tmp = None);
  (* A long header must still work: the window is the leading comment block,
     not a line count.  The first file to carry a marker had a 14-line header
     explaining why, which put the marker past the old 10-line limit. *)
  write ("// a\n// b\n// c\n// d\n// e\n// f\n// g\n// h\n// i\n// j\n"
         ^ "// k\n// l\n// m\n// @zyq-skip: deep in a long header\n>> 1 ¶\n");
  ok "marker long header" (Corpus.marker_in tmp = Some ([], "deep in a long header"));
  (* ... and a comment *after* code must not: that is prose about the marker,
     not a declaration of one. *)
  write ">> 1 ¶\n// @zyq-skip: this is discussion, not a rule\n";
  ok "marker after code" (Corpus.marker_in tmp = None);
  (try Sys.remove tmp with _ -> ());

  (* The output filters, reproduced from two shell scripts: get these wrong and
     every golden fails at once. *)
  ok "strip warnings"
    (Golden.strip_warnings "out\nwarning: x\n  --> f.zy:1\n   note\n  = help\n\nmore"
     = "out\nmore");
  ok "strip ansi"
    (Golden.strip_ansi "\027[0;31merror\027[0m: x" = "error: x");
  ok "chomp"             (Golden.chomp "a\n\n\n" = "a");

  Printf.printf "%s   %d checks, %s\n"
    (Report.bold "selftest") !total
    (if !fails = 0 then Report.green "all passed"
     else Report.red (string_of_int !fails ^ " failed"));
  if !fails > 0 then 1 else 0

(* ------------------------------------------------------------------- suite *)

(* One command, one verdict.  This is what every other repository's test script
   delegates to, so it must never report success for something it skipped. *)
let cmd_suite o =
  (* `--only` names script suites, so asking for one means asking for that and
     nothing else: a CI runner that owns the benchmark baseline wants
     `zyq suite --only bench`, not the whole corpus swept again first. *)
  if o.only_suites <> [] then cmd_script_suites o
  else
  let step name f =
    Printf.printf "\n%s %s\n" (Report.cyan "══") (Report.bold name);
    flush stdout;
    let code = f () in
    (name, code)
  in
  (* Bound one at a time on purpose: OCaml does not promise left-to-right
     evaluation of the elements of a list literal, and it ran these backwards —
     which put the report in reverse order and, worse, made the failure of a
     later step look like it came from an earlier one. *)
  let a = step "selftest"  (fun () -> cmd_selftest ()) in
  let b = step "audit"     (fun () -> cmd_audit o) in
  let c = step "reject"    (fun () -> cmd_reject o) in
  let d = step "expect"    (fun () -> cmd_expect o) in
  let e = step "consensus" (fun () -> cmd_consensus o) in
  (* The script suites last: they are the slowest, and by the time they run the
     differential answers are already on screen. *)
  let f = ("suites", cmd_script_suites o) in
  let results = [ a; b; c; d; e; f ] in
  Printf.printf "\n%s\n" Report.rule;
  Printf.printf "%s\n" (Report.bold "zyq suite");
  List.iter (fun (name, code) ->
      Printf.printf "  %-10s %s\n" name
        (match code with
         | 0 -> Report.green "pass"
         | 1 -> Report.red "FAIL"
         | _ -> Report.yellow "could not run"))
    results;
  let worst = List.fold_left (fun a (_, c) -> max a c) 0 results in
  if worst = 0 then Printf.printf "%s\n" (Report.green "all gates pass")
  else Printf.printf "%s\n" (Report.red "the gate is red");
  worst

(* --------------------------------------------------------------------- main *)

let () =
  let raw = List.tl (Array.to_list Sys.argv) in
  Engine.set_root (resolve_root raw);
  let argv = strip_root raw in
  let run rest f =
    let o = parse_args rest in
    exit (f o)
  in
  match argv with
  | ("-v" | "--version") :: _ -> Printf.printf "zyq %s\n" version
  | "engines" :: rest -> cmd_engines (parse_args rest)
  | "suites" :: rest -> run rest cmd_suites
  | "consensus" :: rest -> run rest cmd_consensus
  | "expect" :: rest -> run rest cmd_expect
  | "reject" :: rest -> run rest cmd_reject
  | "audit" :: rest -> run rest cmd_audit
  | "suite" :: rest -> run rest cmd_suite
  | "selftest" :: _ -> exit (cmd_selftest ())
  | "show" :: file :: rest -> cmd_show (parse_args rest) file
  | "show" :: [] -> die 2 "show needs a file"
  | "oracle" :: _ ->
    prerr_endline "zyq: `oracle` is not implemented yet (phase 2)";
    prerr_endline "  it will run cases/ against their .py / .js / .ml equivalents";
    exit 3
  | "bench" :: _ ->
    prerr_endline "zyq: `bench` is not implemented yet (phase 3)";
    exit 3
  | [] -> usage 2
  | a :: _ -> prerr_endline ("zyq: unknown command: " ^ a); usage 2
