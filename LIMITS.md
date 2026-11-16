# Known limits

Every operation in emlcalc is built from *eml*(x, y) = exp(x) − ln(y), evaluated with double-precision complex numbers. Most of the limits below follow from that: every value passes through `exp` and `ln` at some point, and those functions have a limited range in floating point.

All examples below were run with `eml` on macOS (libc++). Exact boundary values may differ slightly with other standard libraries.

## Subtraction and addition

The `-` macro computes x − y as eml(ln x, exp y) = exp(ln x) − ln(exp y). The second argument, y, only comes back correctly if ln(exp y) = y, and that fails in two ways. `+` is defined as x − (0 − y), so it has the same limits. The first argument has no limits of its own.

### The imaginary part of y must be between −π and π

`ln` always returns an imaginary part between −π and π, so a larger one wraps around and the result is off by a multiple of 2π.

| Input | Result | Correct |
|---|---|---|
| `1 (0,3.1) +` | 1 + 3.1i | 1 + 3.1i |
| `1 (0,3.2) +` | 1 − 3.08319i | 1 + 3.2i |
| `1 (0,3.2) -` | 1 + 3.08319i | 1 − 3.2i |

### The real part of y must keep `exp` in range

`exp` overflows to infinity above about 709.78. Below about −708 it loses precision, and below about −745 it underflows to zero.

- **`-`** passes y through `exp` once, so y must be below about 709.78. Between −745 and −708 the result loses precision, and below −745 it's infinity.
- **`+`** passes both y and −y through `exp`, so y must be between about −709.78 and 709.78.

| Input | Result | Correct |
|---|---|---|
| `1 709 +` | 710 | 710 |
| `1 710 +` | infinity | 711 |
| `1 -710 +` | −infinity | −709 |
| `1 710 -` | −infinity | −709 |
| `1 -745 -` | 745.44 | 746 |
| `1 -746 -` | infinity | 747 |

### `*`, `/` and `^` aren't affected by the wraparound

These macros add or subtract logarithms and then apply `exp` to the result. An error of 2πi in the exponent has no effect, since exp(z + 2πi) = exp(z). So they work for negative and complex inputs even when an intermediate `+` or `-` wraps around: `-2 -3 *` gives 6, and `(0,4) (0,4) *` gives −16.

## Zero

| Input | Result | Correct | Notes |
|---|---|---|---|
| `0 2 ^` | infinity | 0 | **Wrong.** `^` computes exp(y · ln 0) through `*`, which goes wrong when ln 0 = −infinity. |
| `0 sqrt` | infinity | 0 | **Wrong**, for the same reason: `sqrt` and `root` use `^`. |
| `2 0 ^` | 1 | 1 | |
| `0 3 *` | 0 | 0 | |
| `2 0 /` | infinity | — | Division by zero gives infinity. |
| `0 inv` | infinity | — | Division by zero gives infinity. |
| `0 0 /` | NaN | — | 0/0 is undefined. |
| `0 ln` | −infinity | — | The usual floating-point convention. |

## Overflow

Results above about 1.8 × 10³⁰⁸, the largest double, become infinity: `710 exp` and `1e300 1e10 *` both give infinity. That's normal for doubles. The difference in emlcalc is that intermediate steps can overflow even when the final result would fit, as in the `+` limits above.

## Macros that inherit these limits

Any macro that applies `+` or `-` to a value it computed inherits the limits above for that value.

### Trigonometric functions: `sin`, `cos` and `tan`

`cos` computes (eⁱˣ + e⁻ⁱˣ) / 2, and `sin` computes (eⁱˣ − e⁻ⁱˣ) / 2i. In both, e⁻ⁱˣ is the second argument of `+` or `-`. `tan` divides `sin` by `cos`, so it inherits both of their limits.

For x = a + bi, e⁻ⁱˣ = eᵇ(cos a − i sin a), which grows as b grows:

- **Real x:** both terms have size 1, so the results are always correct.
- **Negative imaginary part:** e⁻ⁱˣ is small, so the results are correct. For example, `(0,-10) cos` gives 11013.2, and `(0,-10) tan` gives −i.
- **Positive imaginary part:** the results are wrong once eᵇ · |sin a| reaches π, which wraps the imaginary part of e⁻ⁱˣ. They also fail once eᵇ · |cos a| goes above about 709, which overflows `exp`. When both `sin` and `cos` overflow, `tan` gives NaN, because infinity divided by infinity isn't a number.

| Input | Result | Correct |
|---|---|---|
| `(1,1) sin` | 1.29846 + 0.634964i | 1.29846 + 0.634964i |
| `(1,1) cos` | 0.83373 − 0.988898i | 0.83373 − 0.988898i |
| `(1,1) tan` | 0.271753 + 1.08392i | 0.271753 + 1.08392i |
| `(1,2) sin` | 0.0242 + 1.9596i | 3.16578 + 1.9596i |
| `(1,2) cos` | 2.03272 + 0.0897i | 2.03272 − 3.0519i |
| `(1,2) tan` | 0.0543 + 0.9616i | 0.0338 + 1.0148i |
| `(0,6) cos` | 201.716 | 201.716 |
| `(0,7) sin` | −infinity − infinity·i | 548.316i |
| `(0,7) cos` | infinity | 548.317 |
| `(0,7) tan` | NaN | 0.999998i |

Rearranging the definitions can't avoid this. When b is large, one of eⁱˣ and e⁻ⁱˣ is always large, and whichever one goes second through `+` or `-` hits the limit. Swapping the terms would only move the failures to negative imaginary parts.

#### Near the poles of `tan`

At π/2, where tan is infinite, `pi 2 / tan` gives 4.4 × 10¹⁵ + 5.6 × 10¹⁵ i, while Python's `cmath.tan` gives 1.6 × 10¹⁶. Neither is meaningful. The computed π/2 is slightly off, so cos(π/2) comes out as a tiny rounding error instead of 0. Dividing by it gives a huge number, which in emlcalc also has a large imaginary part, because the rounding error in cos(π/2) has an imaginary part too.

## Rounding error

- **Leftover imaginary parts.** Taking ln of a negative number goes through iπ, which leaves a tiny imaginary part, often around 10⁻¹⁶: `-2 3 *` gives −6 + 7.3 × 10⁻¹⁶ i, and `i` gives 6.1 × 10⁻¹⁷ + i.
- **Errors grow with nesting.** Each layer of `exp` and `ln` adds rounding error: `-8 3 ^` gives −512 + 1.1 × 10⁻¹² i.
- **The display hides most of it.** Results are printed to 6 significant digits, so errors in the real part rarely show.

## Input

- **No spaces in complex numbers.** `(1,2)` works, but `(1, 2)` fails with `Unknown macro: (1,`, because input is split into words at spaces.
- **No very small numbers.** Numbers below about 2.2 × 10⁻³⁰⁸, the smallest normal double, can't be typed: `1e-320` fails with `Unknown macro: 1e-320`.

## The program and the library

- **Library location.** `library.eml` is read from the current directory, so `eml` only finds it when run from the project folder.
- **Library format** (intentional choices):
  - A comment must start with `#` in the first column; indented comments are rejected.
  - A macro must be defined before another macro uses it, which rules out recursion.
  - A macro can't be redefined.
  - Macro names lose any internal spaces: `my mac` becomes `mymac`.
- **Stack words.** Only `swap` and `dup` exist, so a two-argument function that uses both of its arguments more than once can't be written yet. That needs `over` or `rot`.
- **No conditionals.** Macros can't make decisions, so functions defined in pieces, by cases, can't be written.
- **Output precision.** Results are printed to 6 significant digits.
