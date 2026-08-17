(* Engines: what they are, and how to run one over a file.

   An engine is anything that turns a source file into stdout.  Three of them
   run Zymbol; the rest run their own language and exist to be an oracle — a
   source of truth that does not depend on any Zymbol implementation being
   right. *)

type engine = {
  id : string;
  cmd : string list;                (* argv; {file} and {exe} are substituted *)
  check_cmd : string list;          (* argv for static checking; [] if none *)
  lang : string;                    (* "zymbol" for engines under test *)
  oracle : bool;
  desc : string;
  (* A stderr line starting with one of these means "this engine cannot run
     this program".  Without it a missing feature reads as a wrong answer,
     which is a different thing and must be reported differently. *)
  unsupported : string list;
  build : string option;            (* compile step for engines that need one *)
}

(* --------------------------------------------------------------- the root *)

(* Everything zyq reads — engines.toml, corpus/, corpus.toml, reject/ — lives
   under one directory, and the engine commands are written relative to it.

   This used to be the process's current directory, which meant zyq only
   worked when run from inside zyquality/.  That is fine for a tool you run by
   hand and fatal for one that other repositories' test scripts delegate to:
   `bash interpreter/tests/scripts/vm_compare.sh` runs from interpreter/, and
   `../web/tests/run_one.mjs` resolved from there points at nothing. *)
let root = ref (Sys.getcwd ())

let set_root d = root := d

let under p = if Filename.is_relative p then Filename.concat !root p else p

(* Where zyq lives, if it can tell.  argv[0] is a path when the binary was
   invoked as ./zyq or by absolute path; when it came off PATH it is a bare
   name and this gives nothing, which is why $ZYQ_ROOT exists. *)
let guess_root () =
  let exe = Sys.executable_name in
  let d = Filename.dirname exe in
  if Sys.file_exists (Filename.concat d "engines.toml") then Some d else None

(* -------------------------------------------------------------------- load *)

(* `${NAME:-default}` in an engine command, expanded from the environment.

   This exists because the release gate has to be able to point the suite at an
   *installed* package rather than at the build tree — `ZYMBOL_BIN=/usr/bin/zymbol`
   is how vm_compare.sh did it, and a wrapper that delegates here has to keep
   that working or the .deb verification stops testing the .deb.

   Only this one form is supported.  A bare `$NAME` with no default would let a
   typo expand to the empty string and silently run the wrong thing. *)
let expand_env (s : string) : string =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if !i + 1 < n && s.[!i] = '$' && s.[!i + 1] = '{' then begin
      match String.index_from_opt s !i '}' with
      | None -> Buffer.add_char b s.[!i]; incr i
      | Some close ->
        let body = String.sub s (!i + 2) (close - !i - 2) in
        let name, dflt =
          match String.index_opt body ':' with
          | Some k when k + 1 < String.length body && body.[k + 1] = '-' ->
            String.sub body 0 k,
            String.sub body (k + 2) (String.length body - k - 2)
          | _ -> body, ""
        in
        let v = match Sys.getenv_opt name with
          | Some v when v <> "" -> v
          | _ -> dflt
        in
        Buffer.add_string b v;
        i := close + 1
    end else begin Buffer.add_char b s.[!i]; incr i end
  done;
  Buffer.contents b

let load_engines path : engine list =
  let where = Filename.basename path in
  let tables = Toml.parse path in
  let engines =
    List.map (fun (t : Toml.table) ->
        if t.name <> "engine" then
          Toml.err "%s line %d: unknown table [[%s]]" where t.line t.name;
        Toml.reject_unknown ~where t
          [ "id"; "cmd"; "check_cmd"; "lang"; "desc"; "oracle"; "build"; "unsupported" ];
        let cmd = Toml.list ~where t "cmd" in
        if cmd = [] then Toml.err "%s line %d: [[engine]] has an empty `cmd`" where t.line;
        { id = Toml.str_exn ~where t "id";
          cmd;
          check_cmd = Toml.list ~where t "check_cmd";
          lang = (match Toml.str ~where t "lang" with Some s -> s | None -> "zymbol");
          desc = (match Toml.str ~where t "desc" with Some s -> s | None -> "");
          oracle = Toml.bool ~where t "oracle" ~default:false;
          build = Toml.str ~where t "build";
          unsupported = Toml.list ~where t "unsupported" })
      tables
  in
  List.iter (fun e ->
      if List.length (List.filter (fun x -> x.id = e.id) engines) > 1 then
        Toml.err "%s: two engines share the id `%s`" where e.id)
    engines;
  (* Commands are written relative to the root, and engines run with their cwd
     in a scratch directory (see [sandbox_of]).  Resolve those paths once,
     here, and against the root rather than against the caller's cwd. *)
  let engines = List.map (fun e ->
      { e with cmd = List.map expand_env e.cmd;
               check_cmd = List.map expand_env e.check_cmd }) engines
  in
  let absolutise e =
    let fix a =
      if String.length a > 0 && a.[0] <> '/' && String.contains a '/'
      then
        let p = Filename.concat !root a in
        (* Only rewrite what actually resolves: `{file}` and friends contain no
           slash, and a genuine PATH lookup should stay a PATH lookup. *)
        if Sys.file_exists p then p else a
      else a
    in
    { e with cmd = List.map fix e.cmd; check_cmd = List.map fix e.check_cmd }
  in
  List.map absolutise engines

(* ------------------------------------------------------------------ running *)

type status =
  | Completed                       (* ran to completion, whatever it printed *)
  | Unsupported                     (* the engine refused the program *)
  | Timeout
  | Unavailable                     (* the engine itself is not installed *)

type result = {
  eid : string;
  stdout : string;
  stderr : string;
  code : int;
  wall_ms : float;
  status : status;
}

let status_name = function
  | Completed -> "ok" | Unsupported -> "unsupported"
  | Timeout -> "timeout" | Unavailable -> "unavailable"

(* Did the engine reject the program, as opposed to running it and printing an
   error message?  Comparing stdout alone cannot tell those apart, and the two
   are the whole difference between "the engines agree" and "one of them
   refuses to compile what the others run" — the shape of the `@:label!` bug.

   A non-zero exit is the primary signal.  The secondary one exists because
   some engines print a diagnostic and still exit 0. *)
let error_prefixes = [
  "error"; "error["; "Runtime error"; "Parse error"; "Lex error";
  "Compile error"; "VM compile error"; "Semantic error";
]

type verdict = Ok | Failed

let verdict_name = function Ok -> "OK" | Failed -> "ERROR"

(* ---------------------------------------------------------------- plumbing *)

let subst ~file ~exe s =
  let replace hay needle rep =
    let nl = String.length needle in
    let b = Buffer.create (String.length hay) in
    let i = ref 0 in
    while !i < String.length hay do
      if !i + nl <= String.length hay && String.sub hay !i nl = needle then begin
        Buffer.add_string b rep; i := !i + nl
      end else begin Buffer.add_char b hay.[!i]; incr i end
    done;
    Buffer.contents b
  in
  replace (replace s "{file}" file) "{exe}" exe

(* Every engine runs in a scratch directory of its own.

   Without this, a program that writes a file — the std/io and std/db tests do —
   has the engines racing over the same paths, and the loser reports a
   divergence that says nothing about the language.  Isolation makes the
   comparison about the program, not about who got there first. *)
let sandbox_of () =
  let d = Filename.concat (Filename.get_temp_dir_name ())
      (Printf.sprintf "zyq_%d_%d" (Unix.getpid ()) (Random.bits ())) in
  (try Unix.mkdir d 0o700 with Unix.Unix_error (Unix.EEXIST, _, _) -> ());
  d

let rec rm_rf path =
  match Sys.is_directory path with
  | true ->
    Array.iter (fun e -> rm_rf (Filename.concat path e)) (Sys.readdir path);
    (try Unix.rmdir path with _ -> ())
  | false -> (try Sys.remove path with _ -> ())
  | exception _ -> ()

let starts_with p s =
  String.length s >= String.length p && String.sub s 0 (String.length p) = p

let read_file = Toml.read_file

let is_unsupported e stderr =
  e.unsupported <> []
  && List.exists (fun line ->
      List.exists (fun p -> starts_with p (String.trim line)) e.unsupported)
    (String.split_on_char '\n' stderr)

let looks_like_error stderr =
  List.exists (fun line ->
      let l = String.trim line in
      List.exists (fun p -> starts_with p l) error_prefixes)
    (String.split_on_char '\n' stderr)

let verdict_of (r : result) =
  if r.code <> 0 then Failed
  else if looks_like_error r.stderr then Failed
  else Ok

let status_of e code stderr =
  if code = 124 then Timeout
  else if code = 126 || code = 127 then Unavailable
  else if is_unsupported e stderr then Unsupported
  else Completed

(* Which argv to use.  [`Run] executes the program; [`Check] asks the engine to
   analyse it without running it, which is a different question and not every
   engine can answer it. *)
type how = [ `Run | `Check ]

let argv_for (e : engine) (how : how) =
  match how with `Run -> e.cmd | `Check -> e.check_cmd

let can (e : engine) (how : how) = argv_for e how <> []

(* Run one engine over one file.  [timeout] is seconds; the coreutils `timeout`
   does the enforcing, which keeps signal handling out of this process.

   Sequential, and therefore the honest timer: [run_all] below starts every
   engine at once, which is far faster but makes the engines compete for CPU.
   Consensus does not care about wall time, benchmarking cares about nothing
   else, so the two modes use different functions on purpose. *)
(* [merge] sends stderr to the same descriptor as stdout, which is what a shell
   `2>&1` does.  Golden files need it and consensus must not have it.

   The difference is not cosmetic.  Concatenating the two streams afterwards
   puts everything stdout said before anything stderr said, and that is not the
   order the program produced: stderr is unbuffered, stdout is block-buffered
   when it is a pipe, so a diagnostic normally lands *before* output the
   program printed earlier.  One golden in the corpus records exactly that
   ordering, and reconstructing it after the fact is impossible — the two
   pipes no longer know who wrote first. *)
let run ?(timeout = 10) ?stdin_file ?(how : how = `Run) ?(merge = false)
    (e : engine) ~(file : string) : result =
  let file = if Filename.is_relative file then Filename.concat (Sys.getcwd ()) file else file in
  let exe = Filename.remove_extension file ^ ".exe" in
  let argv = List.map (subst ~file ~exe) (argv_for e how) in
  match argv with
  | [] -> { eid = e.id; stdout = ""; stderr = "no command for this mode"; code = 127;
            wall_ms = 0.0; status = Unavailable }
  | prog :: _ ->
    let out_f = Filename.temp_file "zyq" ".out" in
    let err_f = Filename.temp_file "zyq" ".err" in
    let box = sandbox_of () in
    let cleanup () =
      (try Sys.remove out_f with _ -> ());
      (try Sys.remove err_f with _ -> ());
      rm_rf box
    in
    let full = "timeout" :: string_of_int timeout :: "env" :: "-C" :: box :: argv in
    let argv_a = Array.of_list full in
    let t0 = Unix.gettimeofday () in
    let code =
      try
        let fd_out = Unix.openfile out_f [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
        (* Sharing the descriptor is what makes the interleaving real: both
           streams append to one file, in the order the process wrote them. *)
        let fd_err =
          if merge then fd_out
          else Unix.openfile err_f [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
        let fd_in = match stdin_file with
          | Some f when Sys.file_exists f -> Unix.openfile f [ Unix.O_RDONLY ] 0
          | _ -> Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0
        in
        let pid = Unix.create_process argv_a.(0) argv_a fd_in fd_out fd_err in
        let (_, st) = Unix.waitpid [] pid in
        List.iter (fun fd -> try Unix.close fd with _ -> ())
          (if merge then [ fd_in; fd_out ] else [ fd_in; fd_out; fd_err ]);
        (match st with
         | Unix.WEXITED c -> c
         | Unix.WSIGNALED s | Unix.WSTOPPED s -> 128 + s)
      with Unix.Unix_error (Unix.ENOENT, _, _) -> -1
    in
    let wall_ms = (Unix.gettimeofday () -. t0) *. 1000.0 in
    if code = -1 then begin
      cleanup ();
      { eid = e.id; stdout = ""; stderr = Printf.sprintf "%s: not found" prog;
        code = 127; wall_ms; status = Unavailable }
    end else begin
      let so = read_file out_f in
      let se = if merge then "" else read_file err_f in
      cleanup ();
      (* With the streams merged there is no separate stderr to inspect, so the
         diagnostics that classify the result are looked for in the one stream
         there is. *)
      { eid = e.id; stdout = so; stderr = se; code; wall_ms;
        status = status_of e code (if merge then so else se) }
    end

(* Start every engine on the same file at once, then collect.  Four engines in
   the time of the slowest, which is what makes sweeping a 588-file corpus
   bearable.  The wall time recorded here is not a benchmark figure — the
   processes are competing — and nothing in consensus mode reads it. *)
let run_all ?(timeout = 10) ?stdin_file ?(how : how = `Run) ?(merge = false)
    (engines : engine list) ~(file : string) : result list =
  let file = if Filename.is_relative file then Filename.concat (Sys.getcwd ()) file else file in
  let started =
    List.map (fun e ->
        let exe = Filename.remove_extension file ^ ".exe" in
        let argv = List.map (subst ~file ~exe) (argv_for e how) in
        match argv with
        | [] -> (e, None)
        | _ ->
          let out_f = Filename.temp_file "zyq" ".out" in
          let err_f = Filename.temp_file "zyq" ".err" in
          let box = sandbox_of () in
          let argv_a =
            Array.of_list ("timeout" :: string_of_int timeout
                           :: "env" :: "-C" :: box :: argv) in
          (try
             let fd_out = Unix.openfile out_f [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
             let fd_err =
               if merge then fd_out
               else Unix.openfile err_f [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
             let fd_in = match stdin_file with
               | Some f when Sys.file_exists f -> Unix.openfile f [ Unix.O_RDONLY ] 0
               | _ -> Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0
             in
             let pid = Unix.create_process argv_a.(0) argv_a fd_in fd_out fd_err in
             List.iter (fun fd -> try Unix.close fd with _ -> ())
               (if merge then [ fd_in; fd_out ] else [ fd_in; fd_out; fd_err ]);
             (e, Some (pid, out_f, err_f, box))
           with Unix.Unix_error _ ->
             (try Sys.remove out_f with _ -> ());
             (try Sys.remove err_f with _ -> ());
             rm_rf box;
             (e, None)))
      engines
  in
  List.map (fun (e, st) ->
      match st with
      | None ->
        { eid = e.id; stdout = ""; stderr = "could not start"; code = 127;
          wall_ms = 0.0; status = Unavailable }
      | Some (pid, out_f, err_f, box) ->
        let code =
          match snd (Unix.waitpid [] pid) with
          | Unix.WEXITED c -> c
          | Unix.WSIGNALED s | Unix.WSTOPPED s -> 128 + s
        in
        let so = read_file out_f in
        let se = if merge then "" else read_file err_f in
        (try Sys.remove out_f with _ -> ());
        (try Sys.remove err_f with _ -> ());
        rm_rf box;
        { eid = e.id; stdout = so; stderr = se; code; wall_ms = 0.0;
          status = status_of e code (if merge then so else se) })
    started

(* Is this engine usable?  Probed by running it on an empty file, and the bar is
   that it *succeeds*: an empty program prints nothing and exits 0 in every
   engine, so anything else means the command is wrong, not that the program is.

   Exit code alone is not enough.  A driver script whose own dependency is
   missing exits 1 with a message on stderr — which looks exactly like an engine
   that ran and rejected the program.  That is not hypothetical: pointing the
   JavaScript engine at a driver that had been deleted made it "run" every file,
   print nothing and fail, and consensus dutifully reported 589 divergences
   against an engine that had never started.  A gate that can be misconfigured
   into confident wrongness is worse than one that admits it cannot run. *)
let probe ?(timeout = 5) (e : engine) : result =
  let probe = Filename.temp_file "zyq_probe" (if e.lang = "zymbol" then ".zy" else "") in
  let r = run ~timeout e ~file:probe in
  (try Sys.remove probe with _ -> ());
  r

let available ?(timeout = 5) (e : engine) =
  let r = probe ~timeout e in
  r.status = Completed && r.code = 0
