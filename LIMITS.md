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

### Trigonometric functions: `sin`, `cos`, `tan`, `cot`, `sec` and `csc`

`cos` computes (eⁱˣ + e⁻ⁱˣ) / 2, and `sin` computes (eⁱˣ − e⁻ⁱˣ) / 2i. In both, e⁻ⁱˣ is the second argument of `+` or `-`. The other four are built from these by division (`tan` is sin / cos, `cot` is cos / sin, `sec` is 1 / cos and `csc` is 1 / sin), so they inherit the same limits. For example, `(1,2) cot` gives 0.0586 − 1.0366i instead of 0.0328 − 0.9843i.

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

### Inverse trigonometric functions

| Macro | Computes |
|---|---|
| `arcsin` | i · ln(√(1 − z²) − iz) |
| `arccos` | i · ln(z − i√(1 − z²)) |
| `arctan` | −(i/2) · ln((i − z) / (z + i)) |
| `arccot` | (i/2) · ln((z − i) / (z + i)) |
| `arcsec` | arccos(1/z) |
| `arccsc` | arcsin(1/z) |

1 − z² is computed as −(z² − 1), and i − z as −(z − i), so that only the constants 1 and i go through `+` and `-` as the second argument. That removes every `+` and `-` limit from `arctan` and `arccot`. `arcsin` and `arccos` each still have one subtraction whose second argument depends on z.

#### `arcsin` and `arccos` for large inputs

- **`arcsin`** subtracts iz, whose imaginary part is the real part of z. The result is wrong once the real part of z is above π.
- **`arccos`** subtracts i√(1 − z²). The result is wrong once the real part of √(1 − z²) is above π. On the imaginary axis, that happens once the imaginary part is larger than about 2.98 in size: `(0,2.9) arccos` is correct, but `(0,3)` and `(0,-3)` aren't. In the std build, it also fails for real z above about 745, where exp of the subtracted value underflows: `740 arccos` works, but `750 arccos` gives infinity.

| Input | std | Boost | Correct |
|---|---|---|---|
| `3 arcsin` | 1.5708 − 1.76275i | same | 1.5708 ± 1.76275i (see branch cuts below) |
| `3.2 arcsin` | −1.5708 + 1.81204i | same | 1.5708 + 1.83094i |
| `10 arcsin` | −1.5708 + 2.52703i | same | 1.5708 + 2.99322i |
| `(0,3) arccos` | −1.5708 + 1.81171i | same | 1.5708 − 1.81845i |
| `800 arccos` | −infinity + infinity·i | 7.37776i | ±7.37776i |

`arcsec` and `arccsc` inherit these limits for 1/z, so they fail for small z: `(0.2,0.1) arccsc` gives −1.56248 + 1.82183i instead of 1.09692 − 2.18359i.

#### At ±1

√(1 − z²) is `0 sqrt` there, which gives infinity (see [Zero](#zero)). In the std build, `1 arcsin`, `1 arccos`, `1 arcsec` and `1 arccsc` all give −infinity + infinity·i. At −1 the results happen to come out close: `-1 arcsin` gives −1.5708 + 1.1 × 10⁻⁸ i. In the Boost build, 1 − z² comes out as a tiny nonzero number instead of 0, so all of these are close to correct.

#### Branch cuts

Where a function has a branch cut, such as `arcsin` and `arccos` on the real axis beyond ±1, the two sides give results whose imaginary parts differ in sign. Libraries like Python's `cmath` and C++'s `std::asin` pick a side using the sign of a zero imaginary part. Values computed through *eml* don't keep that sign, so on the cut emlcalc sometimes lands on the other side:

| Input | emlcalc | `cmath` |
|---|---|---|
| `2 arcsin` | 1.5708 − 1.31696i | 1.5708 + 1.31696i |
| `2 arccos` | 1.31696i | −1.31696i |
| `0.5 arcsec` | 1.31696i | −1.31696i |

Both are valid limits of the function. Just off the cut, the results agree: `(5,0.1) arccos` gives 0.0204094 − 2.29264i in both.

#### `arccot` at 0

0 is a branch point of `arccot`, and its value there depends on the sign of a rounding error: `0 arccot` gives π/2 in the std build and −π/2 in the Boost build. (Python's `cmath.atan(1/0)` raises a division-by-zero error.)

### Hyperbolic functions

| Macro | Computes |
|---|---|
| `sinh` | (e²ˣ − 1) / 2eˣ |
| `cosh` | (e²ˣ + 1) / 2eˣ |
| `tanh`, `coth`, `sech`, `csch` | sinh / cosh, 1 / tanh, 1 / cosh, 1 / sinh |
| `arcsinh` | ln(z + √(z² + 1)) |
| `arccosh` | ln(z + √(z + 1) · √(z − 1)) |
| `arctanh` | ln((1 + z) / (1 − z)) / 2 |
| `arccoth` | ln((z + 1) / (z − 1)) / 2 |
| `arcsech` | arccosh(1/z) |
| `arccsch` | arcsinh(1/z), written out |

`sinh` and `cosh` are written as (e²ˣ ∓ 1) / 2eˣ rather than the usual (eˣ ∓ e⁻ˣ) / 2, so that only the constant 1 goes through `+` and `-` as the second argument. With the usual form, e⁻ˣ goes second, so any real x below about −6.56 overflows `exp`, and complex x with a negative real part wraps. 1 − z in `arctanh` is computed as −(z − 1) for the same reason. With these forms, `sinh`, `cosh`, `tanh`, `coth`, `sech`, `csch`, `arctanh` and `arccoth` have no `+` or `-` limits.

#### Overflow in the std build

e²ˣ overflows once x is above about 354.9, half of where eˣ itself does. So `sinh`, `cosh` and the functions built from them give infinity between there and about 710, even though the true value still fits in a double: `354 sinh` gives 2.74926 × 10¹⁵³, but `355 sinh` gives infinity. At the other end, they work down to about −709. The Boost build has neither limit.

#### `arcsinh` and `arccosh` for large inputs

Both add √(z² + 1) or √(z + 1) · √(z − 1), which has about the same size as z, as the second argument of `+`. So both inherit the `+` limits for values of that size:

- **Large real z:** in the std build, `700 arcsinh` gives 7.24423, but `720 arcsinh` and `720 arccosh` give infinity. Large negative z works, because the added value is then positive: `-700 arcsinh` gives −7.24423.
- **Large imaginary parts:** the result is wrong once the imaginary part of the added value is above π. On the imaginary axis, that happens for `arcsinh` once the imaginary part is above about 3.3, and for `arccosh` once it's above about 2.98:

| Input | std | Boost | Correct |
|---|---|---|---|
| `(0,3.4) arcsinh` | −1.00395 + 1.5708i | 1.86153 + 1.5708i | 1.89456 + 1.5708i |
| `(0,2.9) arccosh` | 1.78634 + 1.5708i | same | 1.78634 + 1.5708i |
| `(0,3) arccosh` | −2.11273 − 1.5708i | same | 1.81845 + 1.5708i |

`arcsech` and `arccsch` inherit these limits for 1/z, so they fail only for very small z.

#### Branch cuts

The same convention issue as for the inverse trigonometric functions applies. On a branch cut, the imaginary part, or for `arcsinh` on the imaginary axis the real part, sometimes has the opposite sign from `cmath`:

| Input | emlcalc | `cmath` |
|---|---|---|
| `2 arctanh` | 0.549306 − 1.5708i | 0.549306 + 1.5708i |
| `0.5 arccoth` | 0.549306 − 1.5708i | 0.549306 + 1.5708i |
| `-2 arccosh` (std only) | 1.31696 − 3.14159i | 1.31696 + 3.14159i |
| `(0,3.2) arcsinh` | −1.83094 + 1.5708i | 1.83094 + 1.5708i |

#### Poles

At their poles, these functions give infinity in the std build: `1 arctanh`, `0 arcsech`. In the Boost build, 1 − z comes out as a tiny nonzero number rather than 0, so `1 arctanh` gives a large finite number (57.77) instead.

#### Large imaginary leftovers

For large inputs, `sinh` and `cosh` pass a large number through several layers of `exp` and `ln`, so the imaginary leftover grows with it. `-100 sinh` gives −1.34406 × 10⁴³ + 1.7 × 10²⁹ i. That's only about 10⁻¹⁴ relative to the result, but it shows in the output.

## Other macros

### `sign` and `abs`

`sign` computes x / √(x²) and `abs` computes √(x²). For real x, √(x²) is |x|, because the square root is never negative. That choice of root is what lets them work without a conditional.

**Only for real numbers.** For complex z, √(z²) is z when the real part is positive and −z when it's negative. So `sign` gives +1 or −1 depending on which half of the plane z is in (the function some algebra systems call csgn), and `abs` reflects z into the right half-plane: `(-3,4) abs` gives 3 − 4i, not 5. No rearrangement can fix this. Anything built from exp and ln is smooth in the complex sense away from its branch cuts, and a function like that can't be real-valued and non-constant, as |z| is.

**The imaginary axis is a branch cut** of √(z²), so there the result depends on the sign of a rounding leftover. csgn gives +1 for `(0,2)` and −1 for `(0,-2)`, but the std build gives 1 for both and the Boost build gives −1 for both.

**Zero** goes through `0 sqrt` (see [Zero](#zero)):

| Input | std | Boost |
|---|---|---|
| `0 sign` | 0 | −1 |
| `0 abs` | infinity | 3.2 × 10⁻⁵⁰ |

### `wrap360`

`wrap360` brings an angle in degrees into [0, 360) without a conditional. It uses the wraparound of `ln` on purpose: it converts 180 − d to radians, computes ln(e^(iθ)) / i, which `ln` wraps into (−π, π], and converts back.

- **Multiples of 360** land on the edge of the wrap, so they can come out as either 0 or 360: `720 wrap360` gives 0, but `360 wrap360` and `-360 wrap360` give 360. `0 wrap360` gives 0 in the std build and 360 in the Boost build.
- **Large angles lose precision,** because the error in θ grows with its size. The correct value for 10ᵏ with k ≥ 3 is 280:

| Input | std | Boost |
|---|---|---|
| `1e10 wrap360` | 280 | 280 |
| `1e12 wrap360` | 280.003 | 280 |
| `1e14 wrap360` | 280.951 | 280 |
| `1e17 wrap360` | 73.6631 + 0.48i | 280 |
| `1e20 wrap360` | −infinity | 280 |
| `1e50 wrap360` | −infinity | 4.05 − 1.59i |
| `1e80 wrap360` | −infinity | NaN |

### `dms->rad`

`dms->rad` takes degrees, minutes and seconds, gives the minutes and seconds the sign of the degrees, wraps the total with `wrap360`, and converts it to radians.

- **The result is in [0, 2π).** `-30 30 0 dms->rad` gives 5.75086 (329.5°), not −0.532325 (−30.5°).
- **Minutes and seconds should be positive.** The sign comes from the degrees alone, so `-30 -30 0` means −30° + 30′, which is −29.5° (330.5°).
- **Angles under 1° don't work.** The sign of 0 degrees comes from `0 sign` (see above), so the minutes and seconds are dropped in the std build and given the wrong sign in Boost. −0 can't be typed anyway, so there's no way to say which direction is meant. Use decimal degrees instead: `-0.5 wrap360 deg->rad`.

| Input | std | Boost | Correct |
|---|---|---|---|
| `0 30 0 dms->rad rad->deg` | 0 | 359.5 | 0.5 |
| `0 -30 0 dms->rad rad->deg` | 0 | 0.5 | 359.5 |

- **Large degrees** inherit the `wrap360` limits.

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

- **Library location.** By default, `library.eml` is read from the current directory, so `eml` only finds it when run from the project folder. Use `--library` to give its path from anywhere else.
- **Library format** (intentional choices):
  - A comment must start with `#` in the first column; indented comments are rejected.
  - A macro must be defined before another macro uses it, which rules out recursion.
  - A macro can't be redefined.
  - Macro names lose any internal spaces: `my mac` becomes `mymac`.
- **No conditionals.** Macros can't make decisions, so functions defined in pieces, by cases, can't be written.
- **Output precision.** Results are printed to 6 significant digits.
