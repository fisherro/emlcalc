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

TBD: A program that takes conventional infix notation and converts it into a form digestible by `eml` in normal mode.

## Building and testing

The program can be built with `make` or `make eml`.

The `eml-boost` target will build `eml-boost`, which uses `boost::multiprecision::cpp_complex` instead of `std::complex<double>`.

The `test` and `test-boost` targets can be used to run the test cases.

## Known limits

Known limits are documented in LIMITS.md

## Generative AI and this experiment

November 2026

In my other personal projects, I'm letting coding agents write the bulk of the code. I review the code and guide the agent much like mentoring a junior programmer. With this project, though, what I wanted to get out of it meant writing the code myself. Claude reviewed the code and wrote the tests, but I wrote all the code in eml.cpp and library.eml

While that did serve my purposes, it also highlighted for me how much slower the "old" way of working is. So many write-compile-fix-compile-tweak-compile cycles. I'm also not convinced that my code is significantly better than what Opus is able to write these days.

I'm fairly certain that the structure of the code would have been much different if I had let Claude write it. Because my conception of how it would be structured at the start was different than what I arrived at by working through it myself. I'm confident that Claude, however, would have followed the structure I outlined for it...for good or ill. At least until *I* realized that it should be different and instructed Claude to change course.

It has really brought home to me how the collaboration with coding agents really does, overall, make me more productive. Though it still needs to be a collaboration. I'm not comfortable simple "vibe coding" any but the most trivial things.

(Of course, there are many issues with generative AI that I'm not addressing here. But this is not about those.)

