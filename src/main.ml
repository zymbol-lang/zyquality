(* ZyQuality — differential test bench for the Zymbol engines.

     zyq engines                    what is installed and what is not
     zyq consensus [opts]           run the corpus through every engine
     zyq oracle                     (phase 2)
     zyq bench                      (phase 3) *)

let version = "0.1.0"

let default_corpus = "corpus"
let default_engines_file = "engines.toml"

(* ------------------------------------------------------------- file walking *)

let rec collect dir acc =
  if not (Sys.file_exists dir) then acc
  else if Sys.is_directory dir then
    Array.fold_left (fun acc entry -> collect (Filename.concat dir entry) acc)
      acc (Sys.readdir dir)
  else if Filename.check_suffix dir ".zy" then dir :: acc
  else acc

let corpus_files root = List.sort compare (collect root [])

(* ------------------------------------------------------------------ options *)

type opts = {
  mutable corpus : string;
  mutable engines_file : string;
  mutable only : string list;        (* engine ids; empty means all *)
  mutable filter : string option;
  mutable verbose : bool;
  mutable json : bool;
  mutable timeout : int;
  mutable mode : Compare.mode;
}

let default_opts () = {
  corpus = default_corpus;
  engines_file = default_engines_file;
  only = [];
  filter = None;
  verbose = false;
  json = false;
  timeout = 10;
  mode = Compare.Exact;
}

let split_commas s = List.filter (( <> ) "") (String.split_on_char ',' s)

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec go i = i + nl <= hl && (String.sub hay i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let usage code =
  prerr_endline "ZyQuality — differential test bench for the Zymbol engines";
  prerr_endline "";
  prerr_endline "  zyq engines                    list engines and availability";
  prerr_endline "  zyq consensus [options]        run the corpus through every engine";
  prerr_endline "  zyq show FILE.zy               what each engine says about one file";
  prerr_endline "";
  prerr_endline "options:";
  prerr_endline "  --corpus DIR     corpus root (default: corpus)";
  prerr_endline "  --engines a,b    only these engine ids";
  prerr_endline "  --filter TEXT    only files whose path contains TEXT";
  prerr_endline "  --mode M         exact | lines | numeric   (default: exact)";
  prerr_endline "  --tol T          numeric tolerance: '2ulp' or '1e-9'";
  prerr_endline "  --timeout N      seconds per engine (default: 10)";
  prerr_endline "  -v, --verbose    show agreeing files too";
  prerr_endline "  --json           machine-readable output";
  prerr_endline "  --no-colour      plain text";
  exit code

let parse_args argv =
  let o = default_opts () in
  let tol = ref (Compare.Ulp 1) in
  let mode_name = ref "exact" in
  let rec go = function
    | [] -> ()
    | "--corpus" :: v :: t -> o.corpus <- v; go t
    | "--engines-file" :: v :: t -> o.engines_file <- v; go t
    | "--engines" :: v :: t -> o.only <- split_commas v; go t
    | "--filter" :: v :: t -> o.filter <- Some v; go t
    | "--mode" :: v :: t -> mode_name := v; go t
    | "--tol" :: v :: t ->
      (match Compare.parse_tol v with
       | Some x -> tol := x
       | None -> prerr_endline ("zyq: bad tolerance: " ^ v); exit 2);
      go t
    | "--timeout" :: v :: t ->
      (match int_of_string_opt v with
       | Some n -> o.timeout <- n
       | None -> prerr_endline ("zyq: bad timeout: " ^ v); exit 2);
      go t
    | ("-v" | "--verbose") :: t -> o.verbose <- true; go t
    | "--json" :: t -> o.json <- true; Report.use_colour := false; go t
    | "--no-colour" :: t -> Report.use_colour := false; go t
    | ("-h" | "--help") :: _ -> usage 0
    | a :: _ -> prerr_endline ("zyq: unknown option: " ^ a); usage 2
  in
  go argv;
  (match Compare.parse_mode ~tol:!tol !mode_name with
   | Some m -> o.mode <- m
   | None -> prerr_endline ("zyq: bad mode: " ^ !mode_name); exit 2);
  o

(* ------------------------------------------------------------------ loading *)

let load_engines o =
  let all = Engine.load_engines o.engines_file in
  let wanted =
    if o.only = [] then
      (* Consensus is about the engines under test.  An oracle runs a different
         language and has no opinion on what a .zy file prints. *)
      List.filter (fun (e : Engine.engine) -> e.lang = "zymbol") all
    else
      List.filter (fun (e : Engine.engine) -> List.mem e.id o.only) all
  in
  List.iter (fun id ->
      if not (List.exists (fun (e : Engine.engine) -> e.id = id) all) then begin
        prerr_endline ("zyq: no engine with id '" ^ id ^ "' in " ^ o.engines_file);
        exit 2
      end) o.only;
  if wanted = [] then begin
    prerr_endline "zyq: no engines selected"; exit 2
  end;
  wanted

(* -------------------------------------------------------------- subcommands *)

let cmd_engines o =
  let all = Engine.load_engines o.engines_file in
  Printf.printf "%-8s %-8s %-9s %s\n" "id" "lang" "state" "description";
  List.iter (fun (e : Engine.engine) ->
      (* Availability is probed by running the engine on an empty file: a
         binary that exists but cannot start is not available either. *)
      let probe = Filename.temp_file "zyq_probe" (if e.lang = "zymbol" then ".zy" else "") in
      let r = Engine.run ~timeout:5 e ~file:probe in
      (try Sys.remove probe with _ -> ());
      (* Pad before colouring: printf counts the escape bytes as width. *)
      let plain, paint = match r.status with
        | Engine.Unavailable -> "missing", Report.red
        | _ -> "ready", Report.green
      in
      let state = paint (Printf.sprintf "%-8s" plain) in
      Printf.printf "%-8s %-8s %s %s\n" e.id e.lang state e.desc) all

(* What each engine actually said about one file — the tool you reach for once
   consensus has told you something diverges. *)
let cmd_show o file =
  let engines = load_engines o in
  let stdin_file = Filename.remove_extension file ^ ".input" in
  let stdin_file = if Sys.file_exists stdin_file then Some stdin_file else None in
  List.iter (fun (e : Engine.engine) ->
      let r = Engine.run ~timeout:o.timeout ?stdin_file e ~file in
      Printf.printf "%s  %s  %s  %.0f ms\n"
        (Report.bold (Printf.sprintf "%-6s" e.id))
        (Report.dim (Printf.sprintf "exit=%-3d" r.code))
        (Report.dim (Engine.status_name r.status))
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
  let engines = load_engines o in
  let files =
    corpus_files o.corpus
    |> List.filter (fun f -> match o.filter with
        | None -> true
        | Some pat -> contains f pat)
  in
  if files = [] then begin
    Printf.eprintf "zyq: no .zy files under %s\n" o.corpus;
    Printf.eprintf "  point --corpus at the corpus root\n";
    exit 2
  end;
  if not o.json then
    Printf.printf "%s %d files × %d engines (%s)\n"
      (Report.bold "consensus") (List.length files) (List.length engines)
      (String.concat ", " (List.map (fun (e : Engine.engine) -> e.id) engines));
  let tally = Report.new_tally () in
  let first = ref true in
  if o.json then print_string "{\"outcomes\":[";
  List.iter (fun file ->
      let o' = Consensus.run ~timeout:o.timeout ~mode:o.mode engines ~file in
      Report.record tally o';
      if o.json then begin
        if not !first then print_string ",";
        first := false;
        print_string (Report.json_of_outcome o')
      end else if o.verbose then Report.print_verbose o'
      else Report.print_divergence o')
    files;
  if o.json then begin
    Printf.printf "],\"summary\":{\"total\":%d,\"agree\":%d,\"diverge\":%d,\"too_few\":%d}}\n"
      (List.length files) tally.agree tally.split tally.toofew
  end else
    Report.print_summary tally (List.length files);
  (* A divergence is a failure; an engine that could not run is not. *)
  if tally.split > 0 then exit 1

let () =
  match Array.to_list Sys.argv with
  | _ :: ("-v" | "--version") :: _ -> Printf.printf "zyq %s\n" version
  | _ :: "engines" :: rest -> cmd_engines (parse_args rest)
  | _ :: "consensus" :: rest -> cmd_consensus (parse_args rest)
  | _ :: "show" :: file :: rest -> cmd_show (parse_args rest) file
  | _ :: "oracle" :: _ ->
    prerr_endline "zyq: `oracle` is not implemented yet (phase 2)";
    prerr_endline "  it will run cases/ against their .py / .js / .ml equivalents";
    exit 3
  | _ :: "bench" :: _ ->
    prerr_endline "zyq: `bench` is not implemented yet (phase 3)";
    exit 3
  | [ _ ] -> usage 2
  | _ -> usage 2
