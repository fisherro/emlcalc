# emlcalc

Emlcalc demonstrates that a scientific calculator could be implemented with only two buttons: 1 and *eml*.

This idea comes from Andrzej Odrzywołek, [All elementary functions from a single binary operator](https://arxiv.org/abs/2603.21852) (arXiv:2603.21852, 2026).

The *eml* function is...

> *eml*(x, y) = *exp*(x) - *ln*(y)

## Strict mode

(Strict mode has not been implemented yet.)

When `eml --strict` is run, it accepts a sequence of whitespace-separated tokens. Each token must be `1`, `eml`, or a stack operation.

Stack operations are provided as one concession to convenience. They're an implementation detail and only operate on the stack doing no computation. The currently supported stack operations are: `swap` and `dup`.

## Expand mode

When `eml --expand` is run, it accepts a sequence of whitespace-separated tokens. In this case, however, complex numbers are allowed as well as a number of macros. It then outputs an expanded form suitable for input to `eml --strict`.

The library.eml file in the current directory defines the macros that can be used. In this file, a macro is a single line that begins with the macro name followed by a colon and then followed by the input that should be substituted for it.

## Normal mode

When `eml` is run without any options, it is the equivalent of `eml --expand | eml --strict`.

## Infix front-end

TBD: A program that takes conventional infix notation and converts it into a form digestible by `eml` in normal mode.

