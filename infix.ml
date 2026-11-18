(* infix: translates conventional infix notation into RPN for eml.

   Usage: infix [--library <file>] [<file> ...]

   Reads one infix expression from standard input (or one from each file
   given) and prints the equivalent RPN for eml's normal mode:

     $ echo '1 + 2 * sin(pi/4)' | ./infix
     pi 4 / sin 2 * 1 +

   The library is read to learn which functions exist and how many
   arguments each takes, so new macros are usable without changing this
   program.

   The translation has four stages:
     tokenize : string -> token list
     parse    : token list -> expr          (a Pratt parser)
     fold     : expr -> expr                (complex literals into (re,im))
     lower    : expr -> expr                (rearranges around eml's limits)
     emit     : expr -> string list         (postorder walk) *)

(* ---------- Errors ---------- *)

(* A problem not tied to a place in the input, e.g. a bad library. *)
exception Error of string

(* A problem at a character offset in the input. *)
exception Syntax_error of int * string

(* ksprintf formats the message, then hands it to the function, which
   raises. These work like printf: error "%s takes %d" name n. *)
let error fmt = Printf.ksprintf (fun message -> raise (Error message)) fmt

let syntax_error pos fmt =
  Printf.ksprintf (fun message -> raise (Syntax_error (pos, message))) fmt

(* ---------- Characters ---------- *)

let is_space c = c = ' ' || c = '\t' || c = '\n' || c = '\r'
let is_digit c = '0' <= c && c <= '9'
let is_letter c = ('a' <= c && c <= 'z') || ('A' <= c && c <= 'Z')
let is_ident_start c = is_letter c || c = '_'
let is_ident_char c = is_ident_start c || is_digit c

let words line =
  String.map (fun c -> if is_space c then ' ' else c) line
  |> String.split_on_char ' '
  |> List.filter (fun word -> word <> "")

let plural n = if n = 1 then "" else "s"

(* ---------- The library ---------- *)

(* How a word changes the stack: it pops [inputs] values, then pushes
   [outputs] values. A function usable in an expression has outputs = 1,
   and its inputs are its arguments. *)
type stack_effect = { inputs : int; outputs : int }

let built_ins =
  [ ("eml", { inputs = 2; outputs = 1 });
    ("swap", { inputs = 2; outputs = 2 });
    ("dup", { inputs = 1; outputs = 2 });
    ("over", { inputs = 2; outputs = 3 });
    ("rot", { inputs = 3; outputs = 3 });
    ("drop", { inputs = 1; outputs = 0 });
    ("nip", { inputs = 2; outputs = 1 });
    ("tuck", { inputs = 2; outputs = 3 }) ]

(* Like eml's parse_number: it must contain a digit, and either be a
   complex literal or read as a real. *)
let is_number word =
  String.exists is_digit word
  && (word.[0] = '(' || Option.is_some (float_of_string_opt word))

(* The effect of running words in order. Track the stack depth relative to
   the start; the lowest it goes is how many values the sequence needs. *)
let sequence_effect effect_of words =
  let depth, lowest =
    List.fold_left
      (fun (depth, lowest) word ->
        let { inputs; outputs } = effect_of word in
        let popped = depth - inputs in
        (popped + outputs, min lowest popped))
      (0, 0) words
  in
  { inputs = -lowest; outputs = depth - lowest }

(* Reads the library into a table from each word's name to its effect.
   Macros can only use earlier macros, so one pass is enough. *)
let read_library path =
  let table = Hashtbl.create 100 in
  List.iter (fun (name, stack_effect) -> Hashtbl.replace table name stack_effect) built_ins;
  let effect_of macro word =
    if is_number word then { inputs = 0; outputs = 1 }
    else
      match Hashtbl.find_opt table word with
      | Some stack_effect -> stack_effect
      | None -> error "%s: the %s macro uses the undefined word %s" path macro word
  in
  let lines =
    try In_channel.with_open_text path In_channel.input_lines
    with Sys_error _ -> error "Failed to open \"%s\"" path
  in
  List.iter
    (fun line ->
      if String.trim line = "" || line.[0] = '#' then ()
      else
        match String.index_opt line ':' with
        | None -> error "%s: no colon found in macro: %s" path line
        | Some colon ->
            let name = String.trim (String.sub line 0 colon) in
            let body = String.sub line (colon + 1) (String.length line - colon - 1) in
            Hashtbl.replace table name (sequence_effect (effect_of name) (words body)))
    lines;
  table

(* An identifier can't contain - or >, so deg_to_rad stands for deg->rad
   and lngamma_big for lngamma-big. *)
let mangle name =
  let rec join = function
    | [] -> ""
    | [ part ] -> part
    | part :: "to" :: (_ :: _ as rest) -> part ^ "->" ^ join rest
    | part :: rest -> part ^ "-" ^ join rest
  in
  join (String.split_on_char '_' name)

(* Finds the library word that [name] refers to, and its argument count. *)
let resolve library name pos =
  let found =
    match Hashtbl.find_opt library name with
    | Some stack_effect -> Some (name, stack_effect)
    | None -> (
        let mangled = mangle name in
        match Hashtbl.find_opt library mangled with
        | Some stack_effect -> Some (mangled, stack_effect)
        | None -> None)
  in
  match found with
  | None -> syntax_error pos "unknown function %s" name
  | Some (word, { inputs; outputs = 1 }) -> (word, inputs)
  | Some (word, { outputs; _ }) ->
      syntax_error pos "%s leaves %d value%s on the stack, so it can't be used in an expression"
        word outputs (plural outputs)

(* ---------- Tokens ---------- *)

type token =
  | NUMBER of string     (* literal text, kept exactly as written *)
  | IMAGINARY of string  (* 4i, holding "4" *)
  | IDENT of string
  | OP of string         (* + - * / ^ ! ( ) , *)
  | END

(* A token and the offset where it starts, for error messages. *)
type located = { token : token; pos : int }

let describe = function
  | NUMBER s -> s
  | IMAGINARY s -> s ^ "i"
  | IDENT s -> s
  | OP s -> "'" ^ s ^ "'"
  | END -> "end of input"

let tokenize text =
  let n = String.length text in
  let rec skip_while ok i = if i < n && ok text.[i] then skip_while ok (i + 1) else i in
  (* digits [. digits] [e [+-] digits] *)
  let number_end i =
    let i = skip_while is_digit i in
    let i = if i < n && text.[i] = '.' then skip_while is_digit (i + 1) else i in
    if i < n && (text.[i] = 'e' || text.[i] = 'E') then
      let j = if i + 1 < n && (text.[i + 1] = '+' || text.[i + 1] = '-') then i + 2 else i + 1 in
      if j < n && is_digit text.[j] then skip_while is_digit j else i
    else i
  in
  let end_of_text =
    let rec back i = if i > 0 && is_space text.[i - 1] then back (i - 1) else i in
    back n
  in
  let rec go i tokens =
    let i = skip_while is_space i in
    (* END goes just after the last token, not after trailing newlines. *)
    if i >= n then List.rev ({ token = END; pos = end_of_text } :: tokens)
    else
      let c = text.[i] in
      if is_digit c || (c = '.' && i + 1 < n && is_digit text.[i + 1]) then
        let j = number_end i in
        let literal = String.sub text i (j - i) in
        if j < n && text.[j] = 'i' && not (j + 1 < n && is_ident_char text.[j + 1]) then
          go (j + 1) ({ token = IMAGINARY literal; pos = i } :: tokens)
        else if j < n && is_ident_char text.[j] then
          syntax_error j "missing operator after %s (implicit multiplication isn't supported)" literal
        else go j ({ token = NUMBER literal; pos = i } :: tokens)
      else if is_ident_start c then
        let j = skip_while is_ident_char i in
        go j ({ token = IDENT (String.sub text i (j - i)); pos = i } :: tokens)
      else if c = '*' && i + 1 < n && text.[i + 1] = '*' then
        go (i + 2) ({ token = OP "^"; pos = i } :: tokens)
      else if String.contains "+-*/^!()," c then
        go (i + 1) ({ token = OP (String.make 1 c); pos = i } :: tokens)
      else syntax_error i "unexpected character '%c'" c
  in
  go 0 []

(* ---------- The syntax tree ---------- *)

type expr =
  | Num of string               (* real literal text: "2.5", "-3" *)
  | Imag of string              (* imaginary literal: Imag "4" is 4i *)
  | Complex of string * string  (* (re,im) literal *)
  | Name of string              (* a library word taking no arguments: pi *)
  | Neg of expr                 (* unary minus *)
  | Call of string * expr list  (* library word applied to arguments;
                                   operators too: Call ("+", [a; b]) *)

(* ---------- Parsing ---------- *)

(* Binding powers. A higher number binds tighter. For infix operators the
   pair is (left, right): left < right makes an operator left-associative,
   left > right makes it right-associative.
     + -     (10, 11)
     * /     (20, 21)
     unary - 30          so -x^2 is -(x^2), and -2*3 is (-2)*3
     ^       (41, 40)    so 2^3^2 is 2^(3^2)
     !       50          postfix, tightest *)
let infix_power = function
  | "+" | "-" -> Some (10, 11)
  | "*" | "/" -> Some (20, 21)
  | "^" -> Some (41, 40)
  | _ -> None

let prefix_power = 30
let postfix_power = 50

let parse library tokens =
  (* The parser's position in the token list. END is always last and is
     never consumed, so List.hd is safe. *)
  let rest = ref tokens in
  let peek () = List.hd !rest in
  let advance () = rest := List.tl !rest in

  (* Called where an operator or closing token should be. *)
  let unexpected { token; pos } =
    match token with
    | NUMBER _ | IMAGINARY _ | IDENT _ | OP "(" ->
        syntax_error pos "missing operator before %s (implicit multiplication isn't supported)"
          (describe token)
    (* The top level accepts END, so reaching here means an open "(". *)
    | END -> syntax_error pos "missing ')'"
    | _ -> syntax_error pos "unexpected %s" (describe token)
  in
  let expect s =
    match peek () with
    | { token = OP s'; _ } when s = s' -> advance ()
    | located -> unexpected located
  in
  (* Operators are library macros too, so check they're defined. *)
  let operator op args pos =
    let word, inputs = resolve library op pos in
    if inputs <> List.length args then
      syntax_error pos "the library's %s takes %d argument%s" op inputs (plural inputs);
    Call (word, args)
  in

  let rec expression min_power =
    let rec loop lhs =
      let { token; pos } = peek () in
      match token with
      | OP "!" when postfix_power >= min_power ->
          advance ();
          loop (operator "!" [ lhs ] pos)
      | OP op -> (
          match infix_power op with
          | Some (left, right) when left >= min_power ->
              advance ();
              let rhs = expression right in
              loop (operator op [ lhs; rhs ] pos)
          | _ -> lhs)
      | _ -> lhs
    in
    loop (prefix ())

  and prefix () =
    let { token; pos } = peek () in
    match token with
    | NUMBER s -> advance (); Num s
    | IMAGINARY s -> advance (); Imag s
    | IDENT name -> advance (); identifier name pos
    | OP "-" -> advance (); Neg (expression prefix_power)
    | OP "+" -> advance (); expression prefix_power
    | OP "(" ->
        advance ();
        let e = expression 0 in
        expect ")";
        e
    | END -> syntax_error pos "unexpected end of input"
    | OP _ -> syntax_error pos "unexpected %s" (describe token)

  (* pi, or sin(x), or log(b, x) *)
  and identifier name pos =
    let word, inputs = resolve library name pos in
    let args =
      match (peek ()).token with
      | OP "(" -> advance (); arguments ()
      | _ ->
          if inputs > 0 then
            syntax_error pos "%s takes %d argument%s: %s(...)" name inputs (plural inputs) name;
          []
    in
    let given = List.length args in
    if given <> inputs then
      syntax_error pos "%s takes %d argument%s, not %d" name inputs (plural inputs) given;
    if inputs = 0 then Name word else Call (word, args)

  (* After the "(": zero or more comma-separated expressions, then ")". *)
  and arguments () =
    match (peek ()).token with
    | OP ")" -> advance (); []
    | _ ->
        let rec more args =
          let args = expression 0 :: args in
          match (peek ()).token with
          | OP "," -> advance (); more args
          | OP ")" -> advance (); List.rev args
          | _ -> unexpected (peek ())
        in
        more []
  in

  let e = expression 0 in
  (match (peek ()).token with END -> () | _ -> unexpected (peek ()));
  e

(* ---------- Rewriting ---------- *)

let negate s = if s.[0] = '-' then String.sub s 1 (String.length s - 1) else "-" ^ s

(* Folds literals so that eml reads them as numbers instead of computing
   them. 3+4i would otherwise become "3 4 i * +", which is wrong because 4i
   goes through + as the second argument and wraps (its imaginary part is
   more than pi). Folded, it's the literal (3,4).

   The rewrites are textual, never arithmetic, so the Boost build keeps its
   precision. Works bottom-up: fold the children, then look at the shape. *)
let rec fold e =
  match e with
  | Num _ | Imag _ | Complex _ -> e
  | Name "i" -> Imag "1"
  | Name _ -> e
  | Neg a -> (
      match fold a with
      | Num s -> Num (negate s)
      | Imag s -> Imag (negate s)
      | Complex (re, im) -> Complex (negate re, negate im)
      | a -> Neg a)
  | Call (op, args) -> (
      match (op, List.map fold args) with
      | "*", [ Num s; Imag "1" ] | "*", [ Imag "1"; Num s ] -> Imag s
      | "+", [ Num re; Imag im ] | "+", [ Imag im; Num re ] -> Complex (re, im)
      | "-", [ Num re; Imag im ] -> Complex (re, negate im)
      | "-", [ Imag im; Num re ] -> Complex (negate re, im)
      | op, args -> Call (op, args))

(* A value whose size we can see, as opposed to one computed at run time. *)
let is_literal = function
  | Num _ | Imag _ | Complex _ | Name _ -> true
  | Neg _ | Call _ -> false

let times_minus_one e = Call ("*", [ e; Num "-1" ])

(* Rearranges the tree around the limits of eml's + and -. In "a b -" (and
   "a b +", which the library defines with neg and -), b goes through
   ln(exp(b)), which overflows when b > 709 and wraps when b's imaginary
   part is outside (-pi, pi]. Multiplication has neither problem. So:
     -x     ->  x * -1        rather than neg, which is 0 - x
     c + x  ->  x + c         put the literal second
     c * x  ->  x * c         (harmless, and reads like the library)
     c - x  ->  x * -1 + c    keeps x out of the second argument
   Literal negatives were already folded, so Neg only sees computed values. *)
let rec lower e =
  match e with
  | Num _ | Imag _ | Complex _ | Name _ -> e
  | Neg a -> times_minus_one (lower a)
  | Call (op, args) -> (
      match (op, List.map lower args) with
      | ("+" | "*"), [ a; b ] when is_literal a && not (is_literal b) -> Call (op, [ b; a ])
      | "-", [ a; b ] when is_literal a && not (is_literal b) ->
          Call ("+", [ times_minus_one b; a ])
      | op, args -> Call (op, args))

(* ---------- Output ---------- *)

let rec emit e =
  match e with
  | Num s -> [ s ]
  | Imag "1" -> [ "i" ]
  | Imag s -> [ Printf.sprintf "(0,%s)" s ]
  | Complex (re, im) -> [ Printf.sprintf "(%s,%s)" re im ]
  | Name word -> [ word ]
  | Neg a -> emit a @ [ "-1"; "*" ]
  | Call (word, args) -> List.concat_map emit args @ [ word ]

let translate library text =
  tokenize text |> parse library |> fold |> lower |> emit |> String.concat " "

(* ---------- Command line ---------- *)

let help_text =
  {|Usage: infix [--library <file>] [<file> ...]
Translates an infix expression from standard input or given files into RPN
for eml. Each file is a separate expression.
  -l, --library File path to the macro library
  -h, --help    Prints this text
|}

exception Usage of string

type options = { library : string; files : string list }

let parse_options args =
  let rec go options = function
    | [] -> { options with files = List.rev options.files }
    | ("-l" | "--library") :: path :: rest -> go { options with library = path } rest
    | [ ("-l" | "--library") ] -> raise (Usage "--library must be followed by a file path")
    | ("-h" | "--help") :: _ -> print_string help_text; exit 0
    | arg :: _ when String.length arg > 1 && arg.[0] = '-' ->
        raise (Usage ("Unrecognized option: " ^ arg))
    | file :: rest -> go { options with files = file :: options.files } rest
  in
  go { library = "library.eml"; files = [] } args

(* Prints a syntax error like a compiler does, with the line and a caret. *)
let report_syntax_error source text pos message =
  let n = String.length text in
  let pos = min pos n in
  let line_start =
    if pos = 0 then 0
    else match String.rindex_from_opt text (pos - 1) '\n' with Some k -> k + 1 | None -> 0
  in
  let line_end = match String.index_from_opt text pos '\n' with Some k -> k | None -> n in
  let line_number =
    1 + List.length (List.filter (( = ) '\n') (List.of_seq (String.to_seq (String.sub text 0 line_start))))
  in
  let column = pos - line_start in
  Printf.eprintf "%s:%d:%d: error: %s\n  %s\n  %s^\n" source line_number (column + 1) message
    (String.sub text line_start (line_end - line_start))
    (String.make column ' ')

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  try
    let options = parse_options args in
    let library = read_library options.library in
    let inputs =
      match options.files with
      | [] -> [ ("<stdin>", In_channel.input_all stdin) ]
      | files ->
          List.map
            (fun file ->
              try (file, In_channel.with_open_text file In_channel.input_all)
              with Sys_error _ -> error "File \"%s\" not found" file)
            files
    in
    List.iter
      (fun (source, text) ->
        try print_endline (translate library text)
        with Syntax_error (pos, message) ->
          report_syntax_error source text pos message;
          exit 1)
      inputs
  with
  | Usage message ->
      prerr_endline message;
      prerr_string help_text;
      exit 2
  | Error message ->
      prerr_endline ("error: " ^ message);
      exit 1
