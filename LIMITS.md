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

## Number expansion

Every number other than `1` is rebuilt from `1` and *eml* before it's used, both when calculating and with `--expand`. `2` is computed as `1 1 +`, and `2.5` as 2 + 5/10¹. The steps are:

- **Digits:** the integer is built one digit at a time: multiply the total by ten, then add the digit.
- **Fraction:** the fraction digits f are added as f / 10ⁿ.
- **Exponent:** the result is multiplied by 10ᵏ, computed with `^`.
- **Sign:** a negative number is multiplied by −1.
- **Complex numbers:** re + im·i is computed as re · (1 + (im/re)·i), or as (im·i) · (1 − (re/im)·i) when the imaginary part is larger. Parts that are zero are left out.

These steps are chosen so that `+` and `-` only ever add or subtract something small: a digit, a fraction below 1, or an imaginary part of size at most 1. So the limits under [Subtraction and addition](#subtraction-and-addition) never apply. Large values only pass through `*`, `/` and `^`.

### Size

The expansion grows with the number of digits and the size of the exponent, not with the size of the number:

| Input | Words after `--expand` |
|---|---|
| `1` | 1 |
| `0` | 9 |
| `2` | 38 |
| `7` | 223 |
| `23` | 538 |
| `1000` | 1,168 |
| `2.5` | 657 |
| `3.14159` | 2,953 |
| `1e300` | 1,309 |
| `(3,4)` | 841 |
| `12345678901234567890` | 10,685 |

### Rounding error

Every number except `1` carries some rounding error. The 6-digit display hides most of it. At full precision in the std build:

| Input | Result | Relative error |
|---|---|---|
| `10` | 10.000000000000002 | 2 × 10⁻¹⁶ |
| `123456` | 123455.99999999975 | 2 × 10⁻¹⁵ |
| `0.1` | 0.099999999999999936 | 6 × 10⁻¹⁶ |
| `3.14159` | 3.1415900000000008 | 3 × 10⁻¹⁶ |
| `1e10` | 10000000000.000074 | 7 × 10⁻¹⁵ |
| `1e300` | 1.0000000000003174 × 10³⁰⁰ | 3 × 10⁻¹³ |
| `1e-300` | 9.9999999999968255 × 10⁻³⁰¹ | 3 × 10⁻¹³ |

The exponent causes the largest errors. 10ᵏ is computed as exp(k · ln 10), so any error in ln 10 is multiplied by k.

### Leftover parts

- **Negative numbers get a tiny imaginary part,** because multiplying by −1 goes through ln(−1) = iπ: `-3` gives −3 + 3.7 × 10⁻¹⁶ i.
- **A part much smaller than the other is lost.** The error is relative to the size of the whole number, so `(1e-300,1)` gives a real part of −1.6 × 10⁻¹⁶ instead of 10⁻³⁰⁰. Likewise, `(0,4)` gives a real part of −6.4 × 10⁻¹⁶ instead of 0.

### In the Boost build

The Boost build has about 50 digits of precision, so the relative errors are around 10⁻⁵⁰ to 10⁻¹⁰⁰. Two things are still visible:

- **Zero isn't exact.** `0` is built as `1 ln`, which comes out as −3.2 × 10⁻⁵⁰ instead of 0. In the std build it's exactly 0.
- **Large numbers show an imaginary part.** Every expanded number gets a small imaginary part, and it grows in proportion to the number. For large numbers it's big enough to print. `1e100` gives 1 × 10¹⁰⁰ − 1663.16i, and `1e300` gives 1 × 10³⁰⁰ − 5.6 × 10²⁰³ i. Relative to the number, both are about 10⁻⁹⁷.

The Boost build accepts much larger and smaller numbers than the std build: `1e400`, `1e-400` and `1e100000` all work, with the same kind of imaginary leftover.

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
