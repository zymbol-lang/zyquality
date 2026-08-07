(* Engines: what they are, and how to run one over a file.

   An engine is anything that turns a source file into stdout.  Four of them
   run Zymbol; the rest run their own language and exist to be an oracle — a
   source of truth that does not depend on any Zymbol implementation being
   right. *)

type engine = {
  id : string;
  cmd : string list;                (* argv; {file} and {exe} are substituted *)
  lang : string;                    (* "zymbol" for engines under test *)
  oracle : bool;
  desc : string;
  (* A stderr line starting with one of these means "this engine cannot run
     this program".  Without it a missing feature reads as a wrong answer,
     which is a different thing and must be reported differently. *)
  unsupported : string list;
  build : string option;            (* compile step for engines that need one *)
}

let default_engine = {
  id = ""; cmd = []; lang = "zymbol"; oracle = false; desc = "";
  unsupported = []; build = None;
}

(* ------------------------------------------------------- a tiny TOML reader *)

(* Only the shape `engines.toml` uses: `[[engine]]` tables holding string,
   boolean and string-array values.  A full TOML parser would be a dependency
   for no gain — but a hand-rolled one must say clearly when it does not
   understand a line, rather than skipping it. *)

exception Config_error of string

let cerr fmt = Printf.ksprintf (fun s -> raise (Config_error s)) fmt

let trim = String.trim

let strip_quotes s =
  let n = String.length s in
  if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then String.sub s 1 (n - 2) else s

let parse_array s =
  let n = String.length s in
  if n < 2 || s.[0] <> '[' || s.[n - 1] <> ']' then cerr "expected a [array], got: %s" s;
  let inner = String.sub s 1 (n - 2) in
  if trim inner = "" then []
  else
    (* Split on commas that are not inside quotes. *)
    let parts = ref [] and buf = Buffer.create 32 and inq = ref false in
    String.iter (fun c ->
        if c = '"' then begin inq := not !inq; Buffer.add_char buf c end
        else if c = ',' && not !inq then begin
          parts := Buffer.contents buf :: !parts; Buffer.clear buf
        end else Buffer.add_char buf c) inner;
    parts := Buffer.contents buf :: !parts;
    (* [parts] accumulated in reverse, and rev_map reverses again: one rev, not
       two.  Getting this wrong silently reverses every argv. *)
    List.rev_map (fun p -> strip_quotes (trim p)) !parts

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let load_engines path : engine list =
  if not (Sys.file_exists path) then cerr "engine list not found: %s" path;
  let lines = String.split_on_char '\n' (read_file path) in
  let acc = ref [] and cur = ref None in
  let flush () = match !cur with
    | Some e when e.id <> "" -> acc := e :: !acc; cur := None
    | Some _ -> cerr "an [[engine]] entry has no id"
    | None -> ()
  in
  List.iteri (fun i line ->
      let l = trim line in
      let ln = i + 1 in
      if l = "" || l.[0] = '#' then ()
      else if l = "[[engine]]" then begin flush (); cur := Some default_engine end
      else
        match String.index_opt l '=' with
        | None -> cerr "line %d: expected `key = value`, got: %s" ln l
        | Some eq ->
          let key = trim (String.sub l 0 eq) in
          let raw = trim (String.sub l (eq + 1) (String.length l - eq - 1)) in
          (* Strip a trailing comment outside quotes. *)
          let raw =
            let b = Buffer.create (String.length raw) and inq = ref false in
            (try String.iter (fun c ->
                 if c = '"' then (inq := not !inq; Buffer.add_char b c)
                 else if c = '#' && not !inq then raise Exit
                 else Buffer.add_char b c) raw
             with Exit -> ());
            trim (Buffer.contents b)
          in
          let e = match !cur with
            | Some e -> e
            | None -> cerr "line %d: `%s` appears before any [[engine]]" ln key
          in
          cur := Some (match key with
              | "id" -> { e with id = strip_quotes raw }
              | "cmd" -> { e with cmd = parse_array raw }
              | "lang" -> { e with lang = strip_quotes raw }
              | "desc" -> { e with desc = strip_quotes raw }
              | "oracle" -> { e with oracle = (raw = "true") }
              | "build" -> { e with build = Some (strip_quotes raw) }
              | "unsupported" -> { e with unsupported = parse_array raw }
              | k -> cerr "line %d: unknown key `%s`" ln k))
    lines;
  flush ();
  (* Commands are written relative to the repo root, but engines run with their
     cwd elsewhere (see [sandbox_of]).  Resolve those paths once, here. *)
  let absolutise e =
    { e with cmd = List.map (fun a ->
          if String.length a > 0 && a.[0] <> '/'
             && String.contains a '/' && Sys.file_exists a
          then Filename.concat (Sys.getcwd ()) a
          else a) e.cmd }
  in
  List.rev_map absolutise !acc

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

let is_unsupported e stderr =
  e.unsupported <> []
  && List.exists (fun line ->
      List.exists (fun p -> starts_with p (trim line)) e.unsupported)
    (String.split_on_char '\n' stderr)

(* Run one engine over one file.  [timeout] is seconds; the coreutils `timeout`
   does the enforcing, which keeps signal handling out of this process.

   Sequential, and therefore the honest timer: [run_all] below starts every
   engine at once, which is far faster but makes the engines compete for CPU.
   Consensus does not care about wall time, benchmarking cares about nothing
   else, so the two modes use different functions on purpose. *)
let run ?(timeout = 10) ?stdin_file (e : engine) ~(file : string) : result =
  let file = if Filename.is_relative file then Filename.concat (Sys.getcwd ()) file else file in
  let exe = Filename.remove_extension file ^ ".exe" in
  let argv = List.map (subst ~file ~exe) e.cmd in
  match argv with
  | [] -> { eid = e.id; stdout = ""; stderr = "empty cmd"; code = 2;
            wall_ms = 0.0; status = Unavailable }
  | prog :: _ ->
    let out_f = Filename.temp_file "zyq" ".out" in
    let err_f = Filename.temp_file "zyq" ".err" in
    let boxes = ref [] in
    let cleanup () =
      (try Sys.remove out_f with _ -> ());
      (try Sys.remove err_f with _ -> ());
      List.iter rm_rf !boxes
    in
    let box = sandbox_of () in
    boxes := [ box ];
    let full = "timeout" :: string_of_int timeout :: "env" :: "-C" :: box :: argv in
    let argv_a = Array.of_list full in
    let t0 = Unix.gettimeofday () in
    let code =
      try
        let fd_out = Unix.openfile out_f [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
        let fd_err = Unix.openfile err_f [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
        let fd_in = match stdin_file with
          | Some f when Sys.file_exists f -> Unix.openfile f [ Unix.O_RDONLY ] 0
          | _ -> Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0
        in
        let pid = Unix.create_process argv_a.(0) argv_a fd_in fd_out fd_err in
        let (_, st) = Unix.waitpid [] pid in
        List.iter (fun fd -> try Unix.close fd with _ -> ()) [ fd_in; fd_out; fd_err ];
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
      let so = read_file out_f and se = read_file err_f in
      cleanup ();
      let status =
        (* 127 from the shell, or from a harness that could not find its
           engine, means the engine is missing rather than wrong. *)
        if code = 124 then Timeout
        else if code = 127 then Unavailable
        else if is_unsupported e se then Unsupported
        else Completed
      in
      { eid = e.id; stdout = so; stderr = se; code; wall_ms; status }
    end

(* Start every engine on the same file at once, then collect.  Four engines in
   the time of the slowest, which is what makes sweeping a 560-file corpus
   bearable.  The wall time recorded here is not a benchmark figure -- the
   processes are competing -- and nothing in consensus mode reads it. *)
let run_all ?(timeout = 10) ?stdin_file (engines : engine list) ~(file : string)
  : result list =
  let file = if Filename.is_relative file then Filename.concat (Sys.getcwd ()) file else file in
  let started =
    List.map (fun e ->
        let exe = Filename.remove_extension file ^ ".exe" in
        let argv = List.map (subst ~file ~exe) e.cmd in
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
             let fd_err = Unix.openfile err_f [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600 in
             let fd_in = match stdin_file with
               | Some f when Sys.file_exists f -> Unix.openfile f [ Unix.O_RDONLY ] 0
               | _ -> Unix.openfile "/dev/null" [ Unix.O_RDONLY ] 0
             in
             let pid = Unix.create_process argv_a.(0) argv_a fd_in fd_out fd_err in
             List.iter (fun fd -> try Unix.close fd with _ -> ())
               [ fd_in; fd_out; fd_err ];
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
        let so = read_file out_f and se = read_file err_f in
        (try Sys.remove out_f with _ -> ());
        (try Sys.remove err_f with _ -> ());
        rm_rf box;
        let status =
          if code = 124 then Timeout
          else if code = 126 || code = 127 then Unavailable
          else if is_unsupported e se then Unsupported
          else Completed
        in
        { eid = e.id; stdout = so; stderr = se; code; wall_ms = 0.0; status })
    started
