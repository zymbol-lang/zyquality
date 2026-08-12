(* A tiny reader for the shape zyq's config files use: arrays of tables holding
   strings, booleans and string arrays.

   Why not a real TOML parser: it would be the project's first external
   dependency, for four config files whose entire vocabulary is `[[table]]` and
   `key = value`.  Why not the previous one: it lived inside [Engine] and knew
   only about `[[engine]]`, so `corpus.toml` could not exist without either
   copying it or widening a module that had no business growing.

   What a hand-rolled reader owes its users is loud failure.  Every line that
   is not understood raises, with the line number — a config reader that skips
   what it cannot parse turns a typo into a silently missing rule, and a
   missing exclusion rule reads as a bug in the language. *)

exception Error of string

let err fmt = Printf.ksprintf (fun s -> raise (Error s)) fmt

type value =
  | Str of string
  | Bool of bool
  | List of string list

type table = {
  name : string;                    (* the [[name]] it appeared under *)
  line : int;                       (* where the table started, for messages *)
  keys : (string * value) list;
}

(* ------------------------------------------------------------------ scalars *)

(* TOML has two string forms and zyq's configs need both.  A basic string, in
   double quotes, honours backslash escapes; a literal string, in single
   quotes, does not.  The literal form is what makes a character class such as
   a negated-double-quote run writable in corpus.toml without a second layer of
   escaping on top of the one the pattern already uses. *)
let unquote ~line s =
  let n = String.length s in
  if n >= 2 && s.[0] = '\'' && s.[n - 1] = '\'' then String.sub s 1 (n - 2)
  else if n >= 2 && s.[0] = '"' && s.[n - 1] = '"' then begin
    let b = Buffer.create n in
    let i = ref 1 in
    while !i < n - 1 do
      if s.[!i] = '\\' && !i + 1 < n - 1 then begin
        (match s.[!i + 1] with
         | 'n' -> Buffer.add_char b '\n'
         | 't' -> Buffer.add_char b '\t'
         | 'r' -> Buffer.add_char b '\r'
         | '\\' -> Buffer.add_char b '\\'
         | '"' -> Buffer.add_char b '"'
         | c -> err "line %d: unknown escape \\%c" line c);
        i := !i + 2
      end else begin Buffer.add_char b s.[!i]; incr i end
    done;
    Buffer.contents b
  end
  else err "line %d: expected a quoted string, got: %s" line s

(* Split on commas outside quotes.  Both quote characters open a string, and
   only the matching one closes it, so a comma inside '"a,b"' stays put. *)
let split_top ~sep s =
  let parts = ref [] and buf = Buffer.create 32 and quote = ref '\000' in
  String.iter (fun c ->
      if !quote <> '\000' then begin
        Buffer.add_char buf c;
        if c = !quote then quote := '\000'
      end else if c = '"' || c = '\'' then begin
        quote := c; Buffer.add_char buf c
      end else if c = sep then begin
        parts := Buffer.contents buf :: !parts; Buffer.clear buf
      end else Buffer.add_char buf c)
    s;
  parts := Buffer.contents buf :: !parts;
  List.rev !parts

let parse_list ~line s =
  let n = String.length s in
  if n < 2 || s.[0] <> '[' || s.[n - 1] <> ']' then
    err "line %d: expected a [list], got: %s" line s;
  let inner = String.sub s 1 (n - 2) in
  if String.trim inner = "" then []
  else List.map (fun p -> unquote ~line (String.trim p)) (split_top ~sep:',' inner)

(* Strip a trailing `# comment`, but only outside quotes: a pattern like
   '[0-9]#' is data, not a comment. *)
let strip_comment s =
  let b = Buffer.create (String.length s) and quote = ref '\000' in
  (try
     String.iter (fun c ->
         if !quote <> '\000' then begin
           Buffer.add_char b c;
           if c = !quote then quote := '\000'
         end else if c = '"' || c = '\'' then begin
           quote := c; Buffer.add_char b c
         end else if c = '#' then raise Exit
         else Buffer.add_char b c)
       s
   with Exit -> ());
  String.trim (Buffer.contents b)

(* -------------------------------------------------------------------- files *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic; s

let is_table_header l =
  let n = String.length l in
  n > 4 && String.sub l 0 2 = "[[" && String.sub l (n - 2) 2 = "]]"

(* Parse [path] into the tables it declares, in file order. *)
let parse (path : string) : table list =
  if not (Sys.file_exists path) then err "config not found: %s" path;
  let lines = String.split_on_char '\n' (read_file path) in
  let out = ref [] and cur = ref None in
  let flush () =
    match !cur with
    | Some t -> out := { t with keys = List.rev t.keys } :: !out; cur := None
    | None -> ()
  in
  List.iteri (fun i raw ->
      let ln = i + 1 in
      let l = String.trim raw in
      if l = "" || l.[0] = '#' then ()
      else if is_table_header l then begin
        flush ();
        cur := Some { name = String.sub l 2 (String.length l - 4); line = ln; keys = [] }
      end
      else begin
        let l = strip_comment l in
        if l = "" then ()
        else match String.index_opt l '=' with
          | None -> err "line %d: expected `key = value`, got: %s" ln l
          | Some eq ->
            let key = String.trim (String.sub l 0 eq) in
            let rhs = String.trim (String.sub l (eq + 1) (String.length l - eq - 1)) in
            let v =
              if rhs = "true" then Bool true
              else if rhs = "false" then Bool false
              else if rhs <> "" && rhs.[0] = '[' then List (parse_list ~line:ln rhs)
              else Str (unquote ~line:ln rhs)
            in
            (match !cur with
             | None -> err "line %d: `%s` appears before any [[table]]" ln key
             | Some t -> cur := Some { t with keys = (key, v) :: t.keys })
      end)
    lines;
  flush ();
  List.rev !out

(* ------------------------------------------------------------------ lookups *)

(* [where] names the file so an error says which config is wrong, not just
   which key. *)
let str ~where (t : table) k =
  match List.assoc_opt k t.keys with
  | Some (Str s) -> Some s
  | Some _ -> err "%s line %d: `%s` must be a string" where t.line k
  | None -> None

let str_exn ~where t k =
  match str ~where t k with
  | Some s -> s
  | None -> err "%s line %d: [[%s]] has no `%s`" where t.line t.name k

let bool ~where (t : table) k ~default =
  match List.assoc_opt k t.keys with
  | Some (Bool b) -> b
  | Some _ -> err "%s line %d: `%s` must be true or false" where t.line k
  | None -> default

let list ~where (t : table) k =
  match List.assoc_opt k t.keys with
  | Some (List l) -> l
  | Some _ -> err "%s line %d: `%s` must be a [list]" where t.line k
  | None -> []

let has (t : table) k = List.mem_assoc k t.keys

(* Any key the caller did not ask about is a mistake — usually a typo in a key
   name, which would otherwise leave the entry silently at its default. *)
let reject_unknown ~where (t : table) (known : string list) =
  List.iter (fun (k, _) ->
      if not (List.mem k known) then
        err "%s line %d: [[%s]] has no key `%s`" where t.line t.name k)
    t.keys
