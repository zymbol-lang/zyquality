(* Comparing two outputs.

   "Are these the same answer?" has three useful readings, and picking the wrong
   one either hides bugs or invents them:

   - [Exact]   byte for byte.  The default, because for text, collections and
               error messages "close" means nothing.
   - [Lines]   exact, ignoring trailing whitespace per line.
   - [Numeric] numbers compared with a tolerance, everything between them
               compared exactly.  For floating point only — two engines that
               disagree on an *integer* have a bug, not a rounding difference. *)

type mode =
  | Exact
  | Lines
  | Numeric of tol

(* Why ULP and not a fixed epsilon: an absolute epsilon is far too permissive
   near zero (1e-9 swallows the entire interesting range) and far too strict at
   1e18 (where consecutive doubles are 256 apart).  Counting representable
   doubles between two values is scale-free. *)
and tol =
  | Ulp of int
  | Relative of float

let mode_name = function
  | Exact -> "exact"
  | Lines -> "lines"
  | Numeric (Ulp n) -> Printf.sprintf "numeric(%d ulp)" n
  | Numeric (Relative r) -> Printf.sprintf "numeric(%g)" r

let parse_mode ?(tol = Ulp 1) = function
  | "exact" -> Some Exact
  | "lines" -> Some Lines
  | "numeric" -> Some (Numeric tol)
  | _ -> None

let parse_tol s =
  match String.trim s with
  | "" -> None
  | s ->
    let n = String.length s in
    if n > 3 && String.sub s (n - 3) 3 = "ulp" then
      match int_of_string_opt (String.trim (String.sub s 0 (n - 3))) with
      | Some k -> Some (Ulp k)
      | None -> None
    else match float_of_string_opt s with
      | Some f -> Some (Relative f)
      | None -> None

(* ---------------------------------------------------------------- tokenising *)

(* Split a string into number and non-number runs.  A number is an optional
   sign, digits, an optional fraction and an optional exponent — the shapes
   every engine here prints. *)

type tok = Num of string | Txt of string

let is_digit c = c >= '0' && c <= '9'

let tokenize (s : string) : tok list =
  let n = String.length s in
  let toks = ref [] and buf = Buffer.create 32 in
  let flush_txt () =
    if Buffer.length buf > 0 then begin
      toks := Txt (Buffer.contents buf) :: !toks; Buffer.clear buf
    end
  in
  let i = ref 0 in
  while !i < n do
    (* A `-` starts a number only when a digit follows and the previous
       character cannot end one, so `3-4` stays three tokens. *)
    let starts_num =
      is_digit s.[!i]
      || (s.[!i] = '-' && !i + 1 < n && is_digit s.[!i + 1]
          && (!i = 0 || not (is_digit s.[!i - 1] || s.[!i - 1] = '.')))
    in
    if starts_num then begin
      flush_txt ();
      let start = !i in
      if s.[!i] = '-' then incr i;
      while !i < n && is_digit s.[!i] do incr i done;
      if !i < n && s.[!i] = '.' && !i + 1 < n && is_digit s.[!i + 1] then begin
        incr i;
        while !i < n && is_digit s.[!i] do incr i done
      end;
      if !i < n && (s.[!i] = 'e' || s.[!i] = 'E') then begin
        let save = !i in
        incr i;
        if !i < n && (s.[!i] = '+' || s.[!i] = '-') then incr i;
        if !i < n && is_digit s.[!i] then
          while !i < n && is_digit s.[!i] do incr i done
        else i := save
      end;
      toks := Num (String.sub s start (!i - start)) :: !toks
    end else begin Buffer.add_char buf s.[!i]; incr i end
  done;
  flush_txt ();
  List.rev !toks

(* ------------------------------------------------------------ number compare *)

(* Distance in representable doubles.  Ordering the IEEE-754 bit patterns as
   signed magnitudes makes consecutive doubles differ by exactly 1. *)
let ulp_distance (a : float) (b : float) : float =
  if a = b then 0.0
  else if Float.is_nan a || Float.is_nan b then infinity
  else begin
    let key f =
      let bits = Int64.bits_of_float f in
      if Int64.compare bits 0L >= 0 then bits
      else Int64.sub Int64.min_int bits
    in
    Float.abs (Int64.to_float (Int64.sub (key a) (key b)))
  end

let looks_integer s = not (String.contains s '.' || String.contains s 'e'
                           || String.contains s 'E')

let num_equal tol (a : string) (b : string) =
  if String.equal a b then true
  else if looks_integer a && looks_integer b then
    (* Integers are exact by definition.  Two engines printing different
       integers is a defect, never a precision artefact -- so the tolerance
       deliberately does not apply here. *)
    false
  else
    match float_of_string_opt a, float_of_string_opt b with
    | Some x, Some y ->
      (match tol with
       | Ulp k -> ulp_distance x y <= float_of_int k
       | Relative r ->
         let d = Float.abs (x -. y) in
         let scale = Float.max (Float.abs x) (Float.abs y) in
         d <= r *. Float.max scale 1.0)
    | _ -> false

(* --------------------------------------------------------------- comparison *)

let strip_trailing_ws s =
  String.split_on_char '\n' s
  |> List.map (fun l ->
      let n = ref (String.length l) in
      while !n > 0 && (l.[!n - 1] = ' ' || l.[!n - 1] = '\t' || l.[!n - 1] = '\r')
      do decr n done;
      String.sub l 0 !n)
  |> String.concat "\n"

let equal mode a b =
  match mode with
  | Exact -> String.equal a b
  | Lines -> String.equal (strip_trailing_ws a) (strip_trailing_ws b)
  | Numeric tol ->
    let rec go xs ys =
      match xs, ys with
      | [], [] -> true
      | Txt x :: xt, Txt y :: yt -> String.equal x y && go xt yt
      | Num x :: xt, Num y :: yt -> num_equal tol x y && go xt yt
      | _ -> false
    in
    go (tokenize a) (tokenize b)

(* The first place two outputs stop agreeing, for the report. *)
let first_difference a b =
  let la = String.split_on_char '\n' a and lb = String.split_on_char '\n' b in
  let rec go i xs ys =
    match xs, ys with
    | [], [] -> None
    | x :: xt, y :: yt -> if String.equal x y then go (i + 1) xt yt else Some (i, x, y)
    | x :: _, [] -> Some (i, x, "<no line>")
    | [], y :: _ -> Some (i, "<no line>", y)
  in
  go 1 la lb

(* -------------------------------------------------------- diagnostic text *)

(* What an engine says ABOUT a program — stderr — normalised the way ZyDDT
   normalises it (ZyDDT/engines.toml, [normalise]), so `--strict` and
   `--audit-exclusions` compare what the engines said and not how each one drew
   it.  Without this, every diagnostic of the Rust CLI and of the browser
   engine differed by construction: the CLI writes ANSI colour into a pipe and
   draws the source line under every message, and the browser engine does
   neither.  That difference was answered with exclusions — eight ANSI_FORMAT
   rules — and an exclusion compared this way can never expire, so they hid
   four real divergences behind a reason that was about colour.

   Applied to stderr only.  stdout is what the program printed, and some
   programs print escapes on purpose: the TUI cases are made of them. *)

(* `sed 's/\x1b\[[0-9;]*m//g'` *)
let strip_ansi (s : string) =
  let n = String.length s in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if s.[!i] = '\027' && !i + 1 < n && s.[!i + 1] = '[' then begin
      let j = ref (!i + 2) in
      while !j < n && (s.[!j] = ';' || (s.[!j] >= '0' && s.[!j] <= '9')) do incr j done;
      if !j < n && s.[!j] = 'm' then i := !j + 1
      else begin Buffer.add_char b s.[!i]; incr i end
    end else begin Buffer.add_char b s.[!i]; incr i end
  done;
  Buffer.contents b

let is_blank c = c = ' ' || c = '\t' || c = '\r'

(* `  12 | >> x ¶` and `     |    ^^^`: the excerpt the Rust engines draw under a
   diagnostic.  The same fact drawn twice. *)
let is_excerpt (l : string) =
  let n = String.length l in
  let i = ref 0 in
  while !i < n && is_blank l.[!i] do incr i done;
  while !i < n && is_digit l.[!i] do incr i done;
  while !i < n && is_blank l.[!i] do incr i done;
  !i < n && l.[!i] = '|'

(* `--> path:12:4`, `--> path:12` and `--> line 12` all become `--> 12`.  The
   path is where the corpus sits on this machine; the column only two of the
   three engines can produce (ZyDDT: keep_location = "line", compare_column =
   false).  A location this does not recognise is kept, never dropped. *)
let normalise_location (l : string) =
  let t = String.trim l in
  let n = String.length t in
  if n < 3 || String.sub t 0 3 <> "-->" then None
  else begin
    let rest = String.trim (String.sub t 3 (n - 3)) in
    let all_digits s = s <> "" && String.for_all is_digit s in
    if String.length rest > 5 && String.sub rest 0 5 = "line " then
      Some ("--> " ^ String.trim (String.sub rest 5 (String.length rest - 5)))
    else
      match List.rev (String.split_on_char ':' rest) with
      | col :: line :: _ :: _ when all_digits col && all_digits line -> Some ("--> " ^ line)
      | line :: _ :: _ when all_digits line -> Some ("--> " ^ line)
      | _ -> Some ("--> " ^ rest)
  end

(* A path inside the text of a message becomes its last component: an absolute
   path, or one ending in `.zy` (ZyDDT's PATHISH).  `failed to parse module …
   in '/home/…/m/x.zy'` against `… in 'm/x.zy'` was one engine printing an
   absolute path and another a relative one.  A module name like `std/math` is
   neither, and is information, so it is kept. *)
let normalise_paths (s : string) =
  let n = String.length s in
  let pathish c =
    (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || is_digit c
    || c = '_' || c = '.' || c = '~' || c = '-' || c = '/' || Char.code c >= 0x80
  in
  let b = Buffer.create n in
  let i = ref 0 in
  while !i < n do
    if pathish s.[!i] then begin
      let j = ref !i in
      while !j < n && pathish s.[!j] do incr j done;
      let tok = String.sub s !i (!j - !i) in
      let last = match String.rindex_opt tok '/' with
        | Some k -> String.sub tok (k + 1) (String.length tok - k - 1)
        | None -> tok
      in
      let absolute = String.length tok > 1 && tok.[0] = '/' in
      let zy = Filename.check_suffix tok ".zy" && String.contains tok '/' in
      Buffer.add_string b (if last <> "" && (absolute || zy) then last else tok);
      i := !j
    end else begin Buffer.add_char b s.[!i]; incr i end
  done;
  Buffer.contents b

let normalise_diagnostics (s : string) =
  String.split_on_char '\n' (strip_ansi s)
  |> List.filter_map (fun l ->
      if String.trim l = "" || is_excerpt l then None
      else match normalise_location l with
        | Some loc -> Some loc
        | None -> Some (normalise_paths (String.trim l)))
  |> String.concat "\n"
