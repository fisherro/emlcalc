# emlcalc

Emlcalc demonstrates that a scientific calculator could be implemented with only two buttons: 1 and *eml*.

This idea comes from Andrzej Odrzywołek, [All elementary functions from a single binary operator](https://arxiv.org/abs/2603.21852) (arXiv:2603.21852, 2026).

The *eml* function is...

> *eml*(x, y) = *exp*(x) - *ln*(y)

## Strict mode

When `eml --strict` is run, it accepts a sequence of whitespace-separated tokens. Each token must be `1`, `eml`, or a stack operation.

Stack operations are provided as one concession to convenience. They're an implementation detail and only operate on the stack doing no computation. The currently supported stack operations are: `swap` and `dup`.

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

## Infix front-end

TBD: A program that takes conventional infix notation and converts it into a form digestible by `eml` in normal mode.

## Building and testing

The program can be built with `make` or `make eml`.

The `eml-boost` target will build `eml-boost`, which uses `boost::multiprecision::cpp_complex` instead of `std::complex<double>`.

The `test` and `test-boost` targets can be used to run the test cases.

