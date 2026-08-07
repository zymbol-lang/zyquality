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
