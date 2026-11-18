# emlcalc

Emlcalc demonstrates that a scientific calculator could be implemented with only two buttons: 1 and *eml*.

This idea comes from Andrzej Odrzywołek, [All elementary functions from a single binary operator](https://arxiv.org/abs/2603.21852) (arXiv:2603.21852, 2026).

The *eml* function is...

> *eml*(x, y) = *exp*(x) - *ln*(y)

## Strict mode

When `eml --strict` is run, it accepts a sequence of whitespace-separated tokens. Each token must be `1`, `eml`, or a stack operation.

Stack operations are provided as one concession to convenience. They're an implementation detail and only operate on the stack doing no computation.

Example:

```sh
$ echo "1 1 swap 1 swap eml 1 eml eml" | ./eml --strict
0
```

## Expand mode

When `eml --expand` is run, it accepts a sequence of whitespace-separated tokens. In this case, however, complex numbers are allowed as well as a number of macros. It then outputs an expanded form suitable for input to `eml --strict`.

The library.eml file in the current directory defines the macros that can be used. In this file, a macro is a single line that begins with the macro name followed by a colon and then followed by the input that should be substituted for it.

Example:

```sh
$ echo "1 ln" | ./eml --expand
1 1 swap 1 swap eml 1 eml eml
```

## Normal mode

When `eml` is run without any options, it is the equivalent of `eml --expand | eml --strict`.

Example:

```sh
$ echo "1 ln" | ./eml
0
```

## Cleaning up rounding error

Results often have tiny leftover parts from rounding error, because every calculation goes through `exp` and `ln`. For example, a negative number usually gets a tiny imaginary part. The `--clean` (`-c`) option prints such parts as 0. It works in normal and strict mode, and has no effect with `--expand`.

Example:

```sh
$ echo "2 10 ^" | ./eml
(1024,3.18585e-13)
$ echo "2 10 ^" | ./eml --clean
1024
```

A part is treated as rounding error when it's smaller than 10,000 times the number type's epsilon multiplied by the size of the whole number, or smaller than 1,000 times epsilon, whichever is larger. Both limits come from `std::numeric_limits`, so they scale with the precision of the build. A genuinely tiny result is also printed as 0: in the std build that's anything below about 2 × 10⁻¹³.

## Reading files

If `eml` is given file paths on the command line, it will read from them instead of standard input. Each file is a separate evaluation (with its own stack).

The `--library` option can be used to specify a path to the library file if it is not "./library.eml".

## Library

The library contains macros that can be used in normal or expand mode.

Each macro is its own line starting with the macro name followed by a colon followed by the text to substitute in place of the macro.

A macro can use other macros that were defined before it.

Each macro name must be unique and cannot be a number or a built-in.

A line starting with `#` is a comment. Blank lines are ignored.

To use numbers other than 1 in normal or expand mode, these macros are required: `ln`, `-`, `+`, `*`, `/`, `^`, `neg`, `i`

Example:

```txt
ln: 1 swap 1 swap eml exp eml
```

## Stack operations

- `dup`: `x` &rarr; `x x`
- `swap`: `x y` &rarr; `y x`
- `over`: `x y` &rarr; `x y x`
- `rot`: `x y z` &rarr; `y z x`
- `drop`: `x` &rarr; empty stack
- `nip`: `x y` &rarr; `y`
- `tuck`: `x y` &rarr; `y x y`

## Infix front-end

`infix` translates conventional infix notation into RPN for `eml` in normal mode. It reads one expression from standard input, or one from each file given on the command line, and prints the translation.

Example:

```sh
$ echo "1 + 2 * sin(pi/4)" | ./infix
pi 4 / sin 2 * 1 +
$ echo "1 + 2 * sin(pi/4)" | ./infix | ./eml
(2.41421,-3.14018e-16)
```

Like `eml`, it reads ./library.eml, or the file given with `--library`. The library decides which functions exist and how many arguments each takes, so new macros can be used without changing `infix`.

### Syntax

- Numbers are written as in `eml`: `2`, `2.5`, `.5`, `1e-3`. Their text is passed through unchanged.
- An imaginary number is a number followed by `i`: `4i`, `2.5e3i`. `i`, `pi` and `e` are the library's constants.
- Operators, from loosest to tightest:
  - `+` and `-`
  - `*` and `/`
  - implicit multiplication (see below)
  - unary `-` and `+`
  - `^` (or `**`), which is right-associative: `2^3^2` is `2^(3^2)`
  - postfix `!` (factorial)

  So `-2^2` is -4, and `-3!` is -6.
- Functions are called as `name(arg, ...)`. The arguments are in the same order as on the `eml` stack:
  - `log(b, x)` is the base-b log of x
  - `root(n, x)` is the nth root of x
  - `atan2(y, x)`
- A function with no arguments is written without parentheses: `pi`, not `pi()`.
- An identifier can't contain `-` or `>`. In a name, `_to_` stands for `->` and `_` stands for `-`, so `deg_to_rad(180)` calls `deg->rad` and `lngamma_big(10)` calls `lngamma-big`.
- Writing two operands next to each other multiplies them: `2pi`, `2 pi`, `pi e`, `2(1+i)`, `(1+2)(3+4)`, `2sin(1)`, `sin(1)cos(1)`, `3!2`. `pi(2)` is also a multiplication, because `pi` takes no arguments.
  - Implicit multiplication binds tighter than `*` and `/`, so `1/2pi` is 1/(2π) and `6/2(1+2)` is 1. It binds looser than `^` and `!`, so `2pi^2` is 2π².
  - Two numbers in a row, like `2 3`, are an error, since that's more likely a typo.
  - Names must be separated: `pie` is an unknown function, not `pi e`.
  - After a number, `e` is an exponent only when digits follow: `2e3` is 2000 and `2e-1` is 0.2, but `2e` is 2·e and `2e - 1` is 2e − 1.

### Working around eml's limits

The translator rearranges expressions to avoid some of the limits described in LIMITS.md:

- Complex literals are folded into one number. `3+4i` becomes `(3,4)`, not `3 4 i * +`, which would give the wrong answer because 4i's imaginary part is larger than π. Negative literals are folded the same way: `-3` stays `-3`.
- Unary minus becomes `-1 *` instead of `neg`. `neg` computes 0 - x, which overflows for x > 709 and wraps when x's imaginary part is outside (-π, π].
- In `+` and `*`, a literal is put second: `1 + sin(1)` becomes `1 sin 1 +`.
- `c - x`, where c is a literal, becomes `x -1 * c +`, so that the computed value is never the second argument of `-`.

These rewrites only move literal text around and never do arithmetic, so `eml-boost` keeps its full precision.

### Errors

Syntax errors give the position, the line, and a caret:

```sh
$ echo "log(2, 8" | ./infix
<stdin>:1:9: error: missing ')'
  log(2, 8
          ^
```

## Building and testing

`make` builds both `eml` and `infix`. `make eml` builds only `eml`.

`make infix` builds `infix`, which is written in OCaml and needs `ocamlopt` (`sudo port install ocaml`).

The `eml-boost` target will build `eml-boost`, which uses `boost::multiprecision::cpp_complex` instead of `std::complex<double>`.

The `test` and `test-boost` targets can be used to run the test cases.

## Known limits

Known limits are documented in LIMITS.md

## Generative AI and this experiment

November 2026

In my other personal projects, I'm letting coding agents write the bulk of the code. I review the code and guide the agent much like mentoring a junior programmer. With this project, though, what I wanted to get out of it meant writing the code myself. Claude reviewed the code and wrote the tests, but I wrote all the code in eml.cpp and library.eml

(Claude also wrote infix.)

While that did serve my purposes, it also highlighted for me how much slower the "old" way of working is. So many write-compile-fix-compile-tweak-compile cycles. I'm also not convinced that my code is significantly better than what Opus is able to write these days.

I'm fairly certain that the structure of the code would have been much different if I had let Claude write it. Because my conception of how it would be structured at the start was different than what I arrived at by working through it myself. I'm confident that Claude, however, would have followed the structure I outlined for it...for good or ill. At least until *I* realized that it should be different and instructed Claude to change course.

It has really brought home to me how the collaboration with coding agents really does, overall, make me more productive. Though it still needs to be a collaboration. I'm not comfortable simple "vibe coding" any but the most trivial things.

(Of course, there are many issues with generative AI that I'm not addressing here. But this is not about those.)

