# emlcalc

A scientific calculator can be implemented with only two buttons for input: 1 and *eml*.

> *eml*(x, y) = *emp*(x) - *ln*(y)

Emlcalc is divided into these parts:

- emleval: Evaluates an E-expression that consists of only literal `1` and the *eml* function represented by `$` using RPN.
- emls2e: Takes S-expressions and expands them into E-expressions.
- emli2s: Takes infix expressions and converts them into S-expressions.

Values supported:

- Complex numbers with double-floating-point precision
- &pi;, *e*

Operations supported:

- +, -, *, /, ^
- ln, exp, log
- sqrt, root
- sin, cos, tan
- sec, cosec, cotan
- Higher order functions?: arc, hyp

