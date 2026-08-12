(* A deliberately small regular-expression subset: literals, `.`, character
   classes, the three repetition operators, groups and alternation.

   Two things in zyq need pattern matching and both used to get it from
   somewhere else.  Redaction was five `sed` expressions inside vm_compare.sh,
   which meant only that runner applied them.  Typed golden wildcards
   (`***int***`) were Python regexes inside expected_compare.sh, which fell
   back to a plain glob when python3 was absent — quietly turning "an integer
   goes here" into "anything at all goes here", in the one situation where you
   are least likely to notice.

   Both now come from here, which is why this exists rather than a call out to
   a regex library: it removes a dependency on the host having Python, and it
   makes the wildcard table something `corpus.toml` declares instead of
   something a runner hard-codes.

   Not supported, on purpose: backreferences, lookaround, non-greedy
   quantifiers, `{n,m}`, anchors.  Nothing zyq compares needs them, and each
   one is a way for a pattern to do something surprising to a corpus of 588
   files.  Matching is over bytes; the classes in use are ASCII, and a `+` run
   of non-space bytes keeps a UTF-8 sequence intact because no continuation
   byte is a space. *)

exception Error of string

let err fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

type node =
  | Lit of char
  | Any
  | Cls of bool * (char * char) list       (* negated?, inclusive ranges *)
  | Rep of node * int * int                (* node, min, max *)
  | Alt of node list list                  (* alternatives, each a sequence *)

type t = { src : string; prog : node list }

(* ------------------------------------------------------------------ parsing *)

let esc = function
  | 'n' -> '\n' | 't' -> '\t' | 'r' -> '\r' | '0' -> '\000'
  | c -> c                        (* \. \[ \\ \* … : the character itself *)

let parse (src : string) : t =
  let n = String.length src in
  let pos = ref 0 in
  let peek () = if !pos < n then Some src.[!pos] else None in

  let parse_class () =
    (* at '[' *)
    incr pos;
    let neg = (peek () = Some '^') in
    if neg then incr pos;
    let ranges = ref [] in
    let first = ref true in
    let rec go () =
      match peek () with
      | None -> err "unterminated [class] in %s" src
      | Some ']' when not !first -> incr pos
      | Some c ->
        first := false;
        let lo =
          if c = '\\' && !pos + 1 < n then (pos := !pos + 2; esc src.[!pos - 1])
          else (incr pos; c)
        in
        (* `a-z`, but a trailing `-` before `]` is a literal dash *)
        if peek () = Some '-' && !pos + 1 < n && src.[!pos + 1] <> ']' then begin
          incr pos;
          let hi =
            if src.[!pos] = '\\' && !pos + 1 < n then (pos := !pos + 2; esc src.[!pos - 1])
            else (incr pos; src.[!pos - 1])
          in
          if Char.code hi < Char.code lo then
            err "reversed range %c-%c in %s" lo hi src;
          ranges := (lo, hi) :: !ranges
        end else ranges := (lo, lo) :: !ranges;
        go ()
    in
    go ();
    if !ranges = [] then err "empty [class] in %s" src;
    Cls (neg, !ranges)
  in

  (* alt := seq ('|' seq)* ; stops at ')' or end of input *)
  let rec parse_alt () =
    let branches = ref [ parse_seq () ] in
    while peek () = Some '|' do
      incr pos;
      branches := parse_seq () :: !branches
    done;
    List.rev !branches

  and parse_seq () =
    let acc = ref [] in
    let rec go () =
      match peek () with
      | None | Some '|' | Some ')' -> ()
      | Some _ -> acc := parse_rep () :: !acc; go ()
    in
    go ();
    List.rev !acc

  and parse_rep () =
    let a = parse_atom () in
    match peek () with
    | Some '*' -> incr pos; Rep (a, 0, max_int)
    | Some '+' -> incr pos; Rep (a, 1, max_int)
    | Some '?' -> incr pos; Rep (a, 0, 1)
    | _ -> a

  and parse_atom () =
    match peek () with
    | Some '(' ->
      incr pos;
      let alts = parse_alt () in
      if peek () <> Some ')' then err "unclosed ( in %s" src;
      incr pos;
      Alt alts
    | Some '[' -> parse_class ()
    | Some '.' -> incr pos; Any
    | Some '\\' ->
      if !pos + 1 >= n then err "trailing backslash in %s" src;
      pos := !pos + 2;
      Lit (esc src.[!pos - 1])
    | Some (')' | '|') | None -> err "unexpected end of pattern in %s" src
    | Some ('*' | '+' | '?' as c) -> err "`%c` with nothing to repeat in %s" c src
    | Some c -> incr pos; Lit c
  in
  let alts = parse_alt () in
  if !pos <> n then err "unbalanced ) in %s" src;
  let prog = match alts with [ one ] -> one | many -> [ Alt many ] in
  { src; prog }

(* ----------------------------------------------------------------- matching *)

let in_class neg ranges c =
  let hit = List.exists (fun (lo, hi) -> c >= lo && c <= hi) ranges in
  if neg then not hit else hit

(* Backtracking, greedy, continuation-passing.  [k] receives the index just
   past the match and decides whether the rest of the pattern is happy with it;
   returning false makes this node give back characters and try again. *)
let rec m_seq nodes s i k =
  match nodes with
  | [] -> k i
  | nd :: rest -> m_node nd s i (fun j -> m_seq rest s j k)

and m_node nd s i k =
  let n = String.length s in
  match nd with
  | Lit c -> i < n && s.[i] = c && k (i + 1)
  | Any -> i < n && s.[i] <> '\n' && k (i + 1)
  | Cls (neg, rs) -> i < n && in_class neg rs s.[i] && k (i + 1)
  | Alt alts -> List.exists (fun seq -> m_seq seq s i k) alts
  | Rep (inner, lo, hi) ->
    (* Consume as much as possible first, then hand back one repetition at a
       time.  [j > i'] refuses a repetition that consumed nothing, which is the
       only way this can fail to terminate. *)
    let rec go count i' =
      (count < hi && m_node inner s i' (fun j -> j > i' && go (count + 1) j))
      || (count >= lo && k i')
    in
    go 0 i

(* Match anchored at [i]; returns where the match ended.  Longest first, since
   the matcher is greedy, and the continuation is what decides. *)
let match_at (r : t) (s : string) (i : int) : int option =
  let out = ref None in
  ignore (m_seq r.prog s i (fun j -> out := Some j; true));
  !out

(* Match anchored at [i] and required to end exactly at [stop]. *)
let match_between (r : t) (s : string) (i : int) (stop : int) : bool =
  m_seq r.prog s i (fun j -> j = stop)

let is_match (r : t) (s : string) : bool =
  match match_at r s 0 with Some j -> j = String.length s | None -> false

(* Leftmost match at or after [from]. *)
let search (r : t) (s : string) ~(from : int) : (int * int) option =
  let n = String.length s in
  let rec go i =
    if i > n then None
    else match match_at r s i with
      | Some j -> Some (i, j)
      | None -> go (i + 1)
  in
  go from

(* Replace every non-overlapping match with [with_].  A zero-width match would
   loop forever, so it advances one byte and keeps the original character —
   patterns that can match nothing are a config mistake, not a reason to hang. *)
let replace_all (r : t) ~(with_ : string) (s : string) : string =
  let b = Buffer.create (String.length s) in
  let n = String.length s in
  let rec go i =
    if i > n then ()
    else match search r s ~from:i with
      | None -> Buffer.add_substring b s i (n - i)
      | Some (st, en) ->
        Buffer.add_substring b s i (st - i);
        if en = st then begin
          if st < n then Buffer.add_char b s.[st];
          go (st + 1)
        end else begin
          Buffer.add_string b with_;
          go en
        end
  in
  go 0;
  Buffer.contents b

let source (r : t) = r.src
