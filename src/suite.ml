(* Suites that are scripts rather than questions zyq asks itself.

   Some things the corpus needs checking for are not differential — only one
   engine has a formatter — and some cannot be asked through a pipe at all,
   because `<<|` needs a real terminal. Those are shell and Python scripts, and
   the point of registering them here is that `zyq suite` becomes the one
   command that means "run the tests".

   Before this they were spread across three repositories with no common entry
   point: the formatter audit and the benchmark gate beside the interpreter, the
   pty harness beside zyml with a README saying "the two outputs must be
   byte-identical" and nothing checking that they were. Each was documented.
   None was in a gate. *)

type spec = {
  id : string;
  cmd : string list;                (* argv, relative to the root *)
  desc : string;
  needs : string list;
  gate : bool;                      (* does a failure make the whole run red *)
}

type outcome =
  | Passed
  | Failed of int
  | Skipped of string               (* what was missing *)

let load (path : string) : spec list =
  let where = Filename.basename path in
  if not (Sys.file_exists path) then []
  else begin
    let specs =
      List.map (fun (t : Toml.table) ->
          if t.name <> "suite" then
            Toml.err "%s line %d: unknown table [[%s]]" where t.line t.name;
          Toml.reject_unknown ~where t [ "id"; "cmd"; "desc"; "needs"; "gate" ];
          let cmd = Toml.list ~where t "cmd" in
          if cmd = [] then
            Toml.err "%s line %d: [[suite]] has an empty `cmd`" where t.line;
          { id = Toml.str_exn ~where t "id";
            cmd;
            desc = (match Toml.str ~where t "desc" with Some s -> s | None -> "");
            needs = Toml.list ~where t "needs";
            gate = Toml.bool ~where t "gate" ~default:true })
        (Toml.parse path)
    in
    List.iter (fun s ->
        if List.length (List.filter (fun x -> x.id = s.id) specs) > 1 then
          Toml.err "%s: two suites share the id `%s`" where s.id)
      specs;
    specs
  end

(* Is [need] satisfied?  Returns None when it is, or what is missing.

   A suite whose needs are absent is skipped and said so, never counted as a
   pass: a gate must not read "nothing ran" as "nothing failed". *)
let missing ~(root : string) (need : string) : string option =
  let on_path prog =
    let p = Filename.temp_file "zyq_which" "" in
    let ok = Sys.command (Printf.sprintf "command -v %s > %s 2>/dev/null"
                            (Filename.quote prog) (Filename.quote p)) = 0 in
    (try Sys.remove p with _ -> ());
    ok
  in
  let env_or name dflt =
    match Sys.getenv_opt name with Some v when v <> "" -> v | _ -> dflt in
  match need with
  | "zymbol" ->
    let b = env_or "ZYMBOL_BIN" "zymbol" in
    if on_path b || Sys.file_exists b then None else Some ("zymbol (" ^ b ^ ")")
  | "python3" -> if on_path "python3" then None else Some "python3"
  | "tty" ->
    (* The pty is allocated by the script; what has to exist here is the
       ability to allocate one at all, which on this platform means python3
       with its pty module — checked by the script itself.  Nothing to test
       from here, so this need never blocks. *)
    None
  | "interpreter" ->
    let d = Filename.concat root "../interpreter" in
    if Sys.file_exists d then None else Some "the interpreter/ checkout"
  | other -> Some ("unknown requirement `" ^ other ^ "`")

let unmet ~root (s : spec) = List.filter_map (missing ~root) s.needs

(* Run one suite, with its output going straight to the terminal: these scripts
   have reports of their own, and swallowing them to reprint a summary would
   lose the part that says which file failed. *)
let run ~(root : string) (s : spec) : outcome =
  match unmet ~root s with
  | _ :: _ as gone -> Skipped (String.concat ", " gone)
  | [] ->
    (* The child writes straight to the inherited descriptor while zyq's own
       output sits in an OCaml buffer until exit, so without this the suite's
       report appears *before* the header announcing it. *)
    flush stdout;
    flush stderr;
    let quoted = List.map Filename.quote s.cmd in
    let code =
      Sys.command (Printf.sprintf "cd %s && %s"
                     (Filename.quote root) (String.concat " " quoted))
    in
    if code = 0 then Passed else Failed code
