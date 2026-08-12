(* What the corpus knows about itself: which files an engine may be judged on,
   what in an output the program did not decide, and what a golden marker
   stands for.

   All three used to be properties of whoever was running the tests.  A file
   the browser engine cannot execute was excluded inside test_runner.mjs, so
   zyml counted it as a divergence; a trace id vm_compare.sh redacted was
   compared verbatim by everything else.  Here they are properties of the
   corpus, read once from `corpus.toml`, and every command in zyq sees the
   same ones. *)

type rule = {
  pat : string;                     (* glob over the corpus-relative path *)
  engines : string list;            (* [] means every engine *)
  tag : string;
  reason : string;
}

type redaction = { rx : Rx.t; with_ : string; why : string }

type wildcard = { marker : string; rxw : Rx.t }

(* How a golden was recorded.  Most were recorded by running the program; the
   ones under errors/semantic/ were recorded by *checking* it, because those
   files are supposed to fail and running them proves nothing.  Two scripts
   knew this by each excluding the other's directory; here it is stated once. *)
type goldenspec = { gpat : string; via : string; by : string }

type t = {
  rules : rule list;
  redactions : redaction list;
  wildcards : wildcard list;        (* longest marker first *)
  goldens : goldenspec list;
}

let empty = { rules = []; redactions = []; wildcards = []; goldens = [] }

(* ------------------------------------------------------------------- globs *)

(* `?` one character, `*` any run within a path segment, `**` any run across
   segments.  Segment-aware because `stdlib/*.zy` must not reach into
   `stdlib/nested/x.zy` — an exclusion that silently widens is how a real
   failure gets skipped. *)
let glob_match (pat : string) (s : string) : bool =
  let pn = String.length pat and sn = String.length s in
  let rec go pi si =
    if pi >= pn then si >= sn
    else if pat.[pi] = '*' then
      if pi + 1 < pn && pat.[pi + 1] = '*' then begin
        (* `**` crosses separators *)
        let pi' = pi + 2 in
        let rec try_from k = k <= sn && (go pi' k || try_from (k + 1)) in
        try_from si
      end else begin
        let pi' = pi + 1 in
        let rec try_from k =
          k <= sn
          && (go pi' k
              || (k < sn && s.[k] <> '/' && try_from (k + 1)))
        in
        try_from si
      end
    else if pat.[pi] = '?' then si < sn && s.[si] <> '/' && go (pi + 1) (si + 1)
    else si < sn && pat.[pi] = s.[si] && go (pi + 1) (si + 1)
  in
  go 0 0

(* -------------------------------------------------------------------- load *)

let load (path : string) : t =
  let where = Filename.basename path in
  if not (Sys.file_exists path) then empty
  else begin
    let tables = Toml.parse path in
    let rules = ref [] and reds = ref [] and wilds = ref [] and golds = ref [] in
    List.iter (fun (t : Toml.table) ->
        match t.name with
        | "golden" ->
          Toml.reject_unknown ~where t [ "match"; "via"; "by" ];
          let via = match Toml.str ~where t "via" with Some s -> s | None -> "run" in
          if via <> "run" && via <> "check" then
            Toml.err "%s line %d: `via` must be run or check, not %s" where t.line via;
          golds := { gpat = Toml.str_exn ~where t "match"; via;
                     by = Toml.str_exn ~where t "by" } :: !golds
        | "rule" ->
          Toml.reject_unknown ~where t [ "match"; "engines"; "tag"; "reason" ];
          rules := {
            pat = Toml.str_exn ~where t "match";
            engines = Toml.list ~where t "engines";
            tag = (match Toml.str ~where t "tag" with Some s -> s | None -> "");
            (* An exclusion whose reason nobody wrote down is indistinguishable
               from a bug someone hid, so it is not optional. *)
            reason = Toml.str_exn ~where t "reason";
          } :: !rules
        | "redact" ->
          Toml.reject_unknown ~where t [ "find"; "with"; "reason" ];
          let src = Toml.str_exn ~where t "find" in
          let rx =
            try Rx.parse src
            with Rx.Error m -> Toml.err "%s line %d: bad `find`: %s" where t.line m
          in
          reds := { rx; with_ = Toml.str_exn ~where t "with";
                    why = Toml.str_exn ~where t "reason" } :: !reds
        | "wildcard" ->
          Toml.reject_unknown ~where t [ "name"; "pattern" ];
          let name = Toml.str_exn ~where t "name" in
          let src = Toml.str_exn ~where t "pattern" in
          let rxw =
            try Rx.parse src
            with Rx.Error m -> Toml.err "%s line %d: bad `pattern`: %s" where t.line m
          in
          wilds := { marker = "***" ^ name ^ "***"; rxw } :: !wilds
        | other -> Toml.err "%s line %d: unknown table [[%s]]" where t.line other)
      tables;
    (* Longest marker first, so `***float***` is recognised before `***int***`
       and the built-in `****` never shadows a typed marker. *)
    let wildcards =
      List.stable_sort
        (fun a b -> compare (String.length b.marker) (String.length a.marker))
        (List.rev !wilds)
    in
    { rules = List.rev !rules; redactions = List.rev !reds; wildcards;
      goldens = List.rev !golds }
  end

(* ------------------------------------------------------- the in-file marker *)

(* A `.zy` file may declare its own exclusion in its first lines:

     // @zyq-skip: reason                 every engine
     // @zyq-skip zyjs,zyml: reason       only those

   corpus.toml is the right place for a file in the shared corpus.  This is for
   a corpus that lives in another repository and travels with its files — the
   playground's example pool is `web/examples/`, and a rule about it belongs
   next to it, not in a config zyquality owns.

   It replaces two markers that meant almost the same thing and were read by
   one runner each: `@vm-skip` in vm_compare.sh and `@skip-parity` in
   test_runner.mjs.  Both are still recognised, and each excuses *the engine it
   was about* rather than all of them.

   That distinction is not pedantry.  Each marker lived in a two-engine runner,
   where "skip this engine" and "skip this file" are indistinguishable — so
   reading them as "every engine" looks equivalent and silently removes the
   file from the four-engine comparison as well.  `gaps/gap_key_input_type_check.zy`
   carried `@vm-skip` from a version where the VM could not run it; all four
   engines agree on it now, and a universal reading would have hidden that
   forever. *)

let marker_names = [
  ("@zyq-skip", []);          (* engines named in the marker, or all *)
  ("@vm-skip", [ "zyvm" ]);   (* vm_compare.sh: the VM could not run this *)
  ("@skip-parity", [ "zyjs" ]); (* test_runner.mjs: the browser engine could not *)
]

(* The file's leading comment block: every `//` line and blank line before the
   first statement.

   Deliberately not "the first N lines".  N was 10, and the first file to carry
   a marker had a fourteen-line header explaining why — so the marker sat just
   past the window and did nothing, silently, which is the exact failure this
   whole exercise exists to remove.  Raising N would have moved the cliff, not
   removed it.  Stopping at the first statement is precise in both directions:
   a header may be as long as it likes, and a `//` comment further down the
   file can never trigger a skip. *)
let read_header path =
  match open_in_bin path with
  | exception _ -> []
  | ic ->
    let starts p s =
      String.length s >= String.length p && String.sub s 0 (String.length p) = p in
    let rec go acc =
      match input_line ic with
      | exception End_of_file -> List.rev acc
      | l ->
        let t = String.trim l in
        if t = "" || starts "//" t then go (l :: acc) else List.rev acc
    in
    let out = go [] in
    close_in ic; out

(* Returns the engines it applies to ([] meaning all) and the reason. *)
let marker_in (path : string) : (string list * string) option =
  let starts p s =
    String.length s >= String.length p && String.sub s 0 (String.length p) = p in
  let find_marker l =
    List.find_map (fun (name, implied) ->
        (* The marker has to be in a comment; anywhere else it is program text. *)
        let rec at i =
          if i + String.length name > String.length l then None
          else if String.sub l i (String.length name) = name then Some (i + String.length name)
          else at (i + 1)
        in
        if starts "//" (String.trim l) then
          Option.map (fun k -> (implied, k)) (at 0)
        else None)
      marker_names
  in
  let rec scan = function
    | [] -> None
    | l :: t ->
      (match find_marker l with
       | None -> scan t
       | Some (implied, k) ->
         let rest = String.sub l k (String.length l - k) in
         (* `[engines]: reason`, or just `: reason`, or nothing at all. *)
         let named, why =
           match String.index_opt rest ':' with
           | None -> [], String.trim rest
           | Some c ->
             let head = String.trim (String.sub rest 0 c) in
             let why = String.trim (String.sub rest (c + 1) (String.length rest - c - 1)) in
             (List.filter (( <> ) "")
                (List.map String.trim (String.split_on_char ',' head)), why)
         in
         (* A legacy marker carries its engine with it; `@zyq-skip` carries
            none, so what the author wrote is what applies. *)
         Some ((if named <> [] then named else implied), why))
  in
  scan (read_header path)

(* ------------------------------------------------------------------ queries *)

(* Why [engine] may not be judged on [rel], if it may not.  [path] is the file
   itself, so its own marker can be read; omit it and only corpus.toml counts. *)
let excused ?path (c : t) ~(engine : string) ~(rel : string) : rule option =
  match
    List.find_opt (fun r ->
        (r.engines = [] || List.mem engine r.engines) && glob_match r.pat rel)
      c.rules
  with
  | Some r -> Some r
  | None ->
    match path with
    | None -> None
    | Some p ->
      match marker_in p with
      | Some (engines, why) when engines = [] || List.mem engine engines ->
        Some { pat = rel; engines; tag = "IN_FILE"; reason = why }
      | _ -> None

(* Excluded for every engine — the file's output is not a function of the
   program, so there is nothing to compare. *)
let excused_everywhere ?path (c : t) ~(rel : string) : rule option =
  match List.find_opt (fun r -> r.engines = [] && glob_match r.pat rel) c.rules with
  | Some r -> Some r
  | None ->
    match path with
    | None -> None
    | Some p ->
      match marker_in p with
      | Some ([], why) -> Some { pat = rel; engines = []; tag = "IN_FILE"; reason = why }
      | _ -> None

(* How this file's golden was recorded — the last matching [[golden]] wins, so
   a general rule can be written first and narrowed afterwards. *)
let golden_via (c : t) ~(rel : string) : string =
  List.fold_left (fun acc g -> if glob_match g.gpat rel then g.via else acc)
    "run" c.goldens

(* Which engine's answer this golden is.  A golden is not a neutral truth — it
   is one engine printing one thing on one day — so judging a second engine
   against it answers the consensus question in a noisier way.  `zyq expect`
   therefore defaults to the recording engine, and comparing others against a
   golden has to be asked for. *)
let golden_by (c : t) ~(rel : string) : string option =
  List.fold_left (fun acc g -> if glob_match g.gpat rel then Some g.by else acc)
    None c.goldens

let tags (c : t) =
  List.sort_uniq compare
    (List.filter_map (fun r -> if r.tag = "" then None else Some r.tag) c.rules)

let redact (c : t) (s : string) : string =
  List.fold_left (fun acc r -> Rx.replace_all r.rx ~with_:r.with_ acc) s c.redactions

(* Where the corpus happens to sit on this machine is not something a program
   decided, so it is removed from every diagnostic before comparing.

   This is not cosmetic.  47 goldens carried the path the corpus had the day
   they were recorded — `tests/arity/x.zy:8:1` in some, an absolute
   `/home/…/interpreter/tests/…` in others — which made them pass in exactly
   one checkout, on one machine, run from one directory.  Nothing detected
   that, because the suite was only ever run from that directory.  Stripping
   the root leaves the corpus-relative path, which is the part that means
   something and the part that is the same everywhere. *)
let strip_root ~(root : string) (s : string) : string =
  let root = if Filename.check_suffix root "/" then root else root ^ "/" in
  let rl = String.length root in
  if rl <= 1 then s
  else begin
    let n = String.length s in
    let b = Buffer.create n in
    let i = ref 0 in
    while !i < n do
      if !i + rl <= n && String.sub s !i rl = root then i := !i + rl
      else begin Buffer.add_char b s.[!i]; incr i end
    done;
    Buffer.contents b
  end

(* A rule that matches nothing describes a file somebody deleted or renamed.
   It is not an error — but left unreported it becomes a rule nobody dares
   remove, which is how the SKIP_SET in test_runner.mjs reached 40 entries with
   at least one path that no longer existed. *)
let dead_rules (c : t) ~(files : string list) : rule list =
  List.filter (fun r -> not (List.exists (fun f -> glob_match r.pat f) files)) c.rules

(* --------------------------------------------------- golden-line matching *)

(* A golden line is matched against the whole actual line: text outside a
   marker is literal, a marker stands for whatever its pattern accepts.

   Implemented directly rather than by building one big regex, because the
   literal parts must stay literal — a golden containing `[1, 2]` or `(a|b)`
   is text, and compiling it as a pattern would make those characters mean
   something they do not. *)

type seg = Text of string | Wild of Rx.t | AnyRun

let split_line (c : t) (golden : string) : seg list =
  let n = String.length golden in
  let segs = ref [] and buf = Buffer.create n in
  let flush () =
    if Buffer.length buf > 0 then begin
      segs := Text (Buffer.contents buf) :: !segs; Buffer.clear buf
    end
  in
  let starts_at i m =
    let ml = String.length m in
    i + ml <= n && String.sub golden i ml = m
  in
  let i = ref 0 in
  while !i < n do
    match List.find_opt (fun w -> starts_at !i w.marker) c.wildcards with
    | Some w ->
      flush ();
      segs := Wild w.rxw :: !segs;
      i := !i + String.length w.marker
    | None ->
      if starts_at !i "****" then begin
        flush (); segs := AnyRun :: !segs; i := !i + 4
      end else begin Buffer.add_char buf golden.[!i]; incr i end
  done;
  flush ();
  List.rev !segs

(* Backtracking over the segment list.  [AnyRun] is the only segment that can
   consume a variable amount without a pattern of its own, so it is the only
   one that needs to try several lengths. *)
let line_matches (c : t) ~(golden : string) ~(actual : string) : bool =
  if not (String.length golden >= 3
          && (let rec has i =
                i + 3 <= String.length golden
                && (String.sub golden i 3 = "***" || has (i + 1))
              in has 0))
  then String.equal golden actual
  else begin
    let an = String.length actual in
    let rec go segs i =
      match segs with
      | [] -> i = an
      | Text t :: rest ->
        let tl = String.length t in
        i + tl <= an && String.sub actual i tl = t && go rest (i + tl)
      | Wild rx :: rest ->
        (* The pattern is greedy; ask it where it could stop and let the rest
           of the line decide.  Trying every end point keeps a greedy `+` from
           eating text a later literal segment needs. *)
        let ok = ref false in
        let j = ref an in
        while (not !ok) && !j >= i do
          if Rx.match_between rx actual i !j && go rest !j then ok := true;
          decr j
        done;
        !ok
      | AnyRun :: rest ->
        let ok = ref false in
        let j = ref an in
        while (not !ok) && !j >= i do
          if go rest !j then ok := true;
          decr j
        done;
        !ok
    in
    go (split_line c golden) 0
  end

(* Whole-output comparison: same number of lines, and every line matching.  A
   differing line count is reported as a plain mismatch, which is what
   expected_compare.sh did — a golden cannot say "and then some more lines". *)
let golden_matches (c : t) ~(golden : string) ~(actual : string) : bool =
  let gl = String.split_on_char '\n' golden
  and al = String.split_on_char '\n' actual in
  List.length gl = List.length al
  && List.for_all2 (fun g a -> line_matches c ~golden:g ~actual:a) gl al

(* The first line that does not match, for the report. *)
let first_mismatch (c : t) ~(golden : string) ~(actual : string) =
  let gl = String.split_on_char '\n' golden
  and al = String.split_on_char '\n' actual in
  let rec go i gs as_ =
    match gs, as_ with
    | [], [] -> None
    | g :: gt, a :: at ->
      if line_matches c ~golden:g ~actual:a then go (i + 1) gt at else Some (i, g, a)
    | g :: _, [] -> Some (i, g, "<no line>")
    | [], a :: _ -> Some (i, "<no line>", a)
  in
  go 1 gl al
