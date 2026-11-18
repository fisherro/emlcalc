#!/bin/bash
# Runs the eml calculator tests. Usage: tests/run.sh (or: make test)
# Set EML to test a different binary, e.g. EML=./eml-boost tests/run.sh
# Written for the bash 3.2 that ships with macOS.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
eml="${EML:-$root/eml}"
case "$eml" in
    /*) ;;
    *) eml="$PWD/$eml" ;;
esac
if [ ! -x "$eml" ]; then
    echo "error: $eml not found; run make first" >&2
    exit 2
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

passed=0
failed=0

fail()
{
    failed=$((failed + 1))
    printf 'FAIL: %s\n' "$1"
    printf '  input:    %s\n' "$2"
    printf '  expected: %s\n' "$3"
    printf '  actual:   %s\n' "$4"
}

# run_eml DIR INPUT [OPTION...]: runs eml in DIR (where it reads library.eml)
# with any options given, and sets $out, $err and $status.
run_eml()
{
    local dir="$1" input="$2"
    shift 2
    out="$(cd "$dir" && printf '%s\n' "$input" | "$eml" "$@" 2>"$tmp/stderr")"
    status=$?
    err="$(cat "$tmp/stderr")"
}

check_output()   # DIR NAME INPUT EXPECTED_STDOUT [OPTION...]
{
    run_eml "$1" "$3" "${@:5}"
    if [ "$status" -ne 0 ]; then
        fail "$2" "$3" "$4" "exit $status, stderr: $err"
    elif [ "$out" != "$4" ]; then
        fail "$2" "$3" "$4" "$out"
    else
        passed=$((passed + 1))
    fi
}

check_error()    # DIR NAME INPUT EXPECTED_STDERR_FRAGMENT [OPTION...]
{
    run_eml "$1" "$3" "${@:5}"
    if [ "$status" -eq 0 ]; then
        fail "$2" "$3" "failure containing '$4'" "exit 0, stdout: $out"
    else
        case "$err" in
            *"$4"*) passed=$((passed + 1)) ;;
            *) fail "$2" "$3" "stderr containing '$4'" "$err" ;;
        esac
    fi
}

# same_number ACTUAL EXPECTED: true if both are numbers as eml prints them,
# "(re,im)" or a plain "re" when the imaginary part is zero, and each part
# matches to within 1e-5 (relative to its size, or absolute below 1).
same_number()
{
    awk -v a="$1" -v b="$2" '
    # Splits s into p[1] (real) and p[2] (imaginary); false if s is not a number.
    function parts(s, p) {
        if (s ~ /^\([^(),]+,[^(),]+\)$/) {
            gsub(/[()]/, "", s); split(s, p, ","); return 1
        }
        if (s ~ /^[^(),[:space:]]+$/) { p[1] = s; p[2] = "0"; return 1 }
        return 0
    }
    BEGIN {
        if (!parts(a, x) || !parts(b, y)) exit 1
        for (k = 1; k <= 2; k++) {
            # "nan" and "inf" must match exactly. Appending "" forces a string
            # comparison; as numbers, NaN != 2 is false in awk.
            if (x[k] ~ /nan|inf/ || y[k] ~ /nan|inf/) {
                if ((x[k] "") != (y[k] "")) exit 1
                continue
            }
            d = x[k] - y[k]; if (d < 0) d = -d
            m = y[k]; if (m < 0) m = -m; if (m < 1) m = 1
            if (!(d <= 1e-5 * m)) exit 1    # written this way so NaN fails
        }
    }'
}

check_approx()   # DIR NAME INPUT EXPECTED_NUMBER [OPTION...]
{
    run_eml "$1" "$3" "${@:5}"
    if [ "$status" -ne 0 ]; then
        fail "$2" "$3" "$4" "exit $status, stderr: $err"
    elif ! same_number "$out" "$4"; then
        fail "$2" "$3" "about $4" "$out"
    else
        passed=$((passed + 1))
    fi
}

# Calculator tests, using the project's library.eml. Use calc_approx when
# rounding error may differ between builds (e.g. std::complex vs Boost).
calc()        { check_output "$root" "$1" "$1" "$2"; }
calc_approx() { check_approx "$root" "$1" "$1" "$2"; }
calc_error()  { check_error  "$root" "$1" "$1" "$2"; }

# expand INPUT EXPECTED_NUMBER: runs INPUT through eml --expand, checks that
# the output uses only 1, eml and the stack operations, then evaluates that
# output with eml --strict and compares it with EXPECTED_NUMBER as
# check_approx does.
expand()
{
    local name="--expand '$1'"
    run_eml "$root" "$1" --expand
    if [ "$status" -ne 0 ]; then
        fail "$name" "$1" "expanded output" "exit $status, stderr: $err"
        return
    fi
    local expanded="$out"
    local others
    others="$(printf '%s\n' "$expanded" | tr ' ' '\n' |
        grep -v -x -e 1 -e eml -e swap -e dup -e over -e rot -e drop \
            -e nip -e tuck -e '' | sort -u | tr '\n' ' ')"
    if [ -n "$others" ]; then
        fail "$name" "$1" "only 1, eml and stack operations" "also: $others"
        return
    fi
    run_eml "$root" "$expanded" --strict
    if [ "$status" -ne 0 ]; then
        fail "$name" "$1" "$2" "evaluating the expansion: exit $status, stderr: $err"
    elif ! same_number "$out" "$2"; then
        fail "$name" "$1" "about $2" "$out"
    else
        passed=$((passed + 1))
    fi
}
expand_error() { check_error "$root" "--expand '$1'" "$1" "$2" --expand; }

# Library tests: LIBRARY is written (with printf, so \n works) to a fresh
# library.eml in a temporary directory.
use_library()
{
    lib_dir="$tmp/lib"
    mkdir -p "$lib_dir"
    printf "$1" > "$lib_dir/library.eml"
    lib_desc="$1"
}
lib()       { check_output "$lib_dir" "library '$lib_desc'" "$1" "$2"; }
lib_error() { check_error  "$lib_dir" "library '$lib_desc'" "$1" "$2"; }

### Calculator ###

calc_approx '2 1 eml'    '7.38906'
calc        '1 exp'      '2.71828'
calc_approx '2 ln'       '0.693147'
calc_approx '1e2 ln'     '4.60517'
calc_approx '5 3 -'      '2'
calc_approx '-1 ln'      '(0,3.14159)'
calc        '(1,2) exp'  '(-1.1312,2.47173)'
calc_approx '1 2 swap -' '1'

# Stack operations. "10 / +" folds the stack into one number whose digits
# are the values left on it, bottom first: "1 2 swap 10 / +" leaves 2 1, so
# 2.1.
calc_approx '1 2 swap 10 / +'         '2.1'
calc_approx '2 dup 10 / +'            '2.2'
calc_approx '1 2 over 10 / + 10 / +'  '1.21'
calc_approx '1 2 3 rot 10 / + 10 / +' '2.31'
calc_approx '1 2 tuck 10 / + 10 / +'  '2.12'
calc_approx '1 2 nip'                 '2'
calc        '1 2 drop'                '1'

calc_error '1 dup'    'Too many values on the stack'
calc_error '1 2'      'Too many values on the stack'
calc_error 'eml'      'Tried to pop an empty stack'
calc_error 'exp'      'Tried to pop an empty stack'
calc_error 'dup'      'Tried to pop an empty stack'
calc_error 'drop'     'Tried to pop an empty stack'
calc_error '1 swap'   'Tried to pop an empty stack'
calc_error '1 over'   'Tried to pop an empty stack'
calc_error '1 2 rot'  'Tried to pop an empty stack'
calc_error '1 nip'    'Tried to pop an empty stack'
calc_error '1 tuck'   'Tried to pop an empty stack'
calc_error 'foo'      'Unknown macro: foo'
calc_error '1abc'     'Unknown macro: 1abc'
calc_error ''         'Empty stack'

### Numbers ###
# Every number except 1 is rebuilt from 1 and eml, so these check that each
# form of number comes back as typed.

calc_approx '0'           '0'
calc_approx '00'          '0'
calc_approx '-0'          '0'
calc_approx '7'           '7'
calc_approx '23'          '23'
calc_approx '102'         '102'
calc_approx '05'          '5'
calc_approx '+4'          '4'
calc_approx '-3'          '-3'
calc_approx '2.5'         '2.5'
calc_approx '.5'          '0.5'
calc_approx '5.'          '5'
calc_approx '-1.5'        '-1.5'
calc_approx '0.05'        '0.05'
calc_approx '3.14159'     '3.14159'
calc_approx '0.0'         '0'
calc_approx '1e2'         '100'
calc_approx '1E2'         '100'
calc_approx '1e0'         '1'
calc_approx '2e3'         '2000'
calc_approx '5e-2'        '0.05'
calc_approx '-4E+1'       '-40'
calc_approx '1.5e2'       '150'
calc_approx '000e2'       '0'
calc_approx '(3,4)'       '(3,4)'
calc_approx '(-3,4)'      '(-3,4)'
calc_approx '(3,-4)'      '(3,-4)'
calc_approx '(0,4)'       '(0,4)'
calc_approx '(0,-4)'      '(0,-4)'
calc_approx '(4,0)'       '4'
calc_approx '(0,0)'       '0'
calc_approx '(5)'         '5'
calc_approx '(1000,5000)' '(1000,5000)'
calc_approx '(5000,1000)' '(5000,1000)'
calc_approx '(0.5,-1.25)' '(0.5,-1.25)'
calc_approx '(1e2,-3e1)'  '(100,-30)'
calc_approx '1 2.5 +'     '3.5'

### Other macros ###

calc        'e'         '2.71828'
calc_approx '2 sq'      '4'
calc_approx '4 inv'     '0.25'
calc_approx '2 10 ^'    '1024'
calc_approx '9 sqrt'    '3'
# root takes the index first: "3 8 root" is the cube root of 8.
calc_approx '3 8 root'  '2'
calc_approx '50 %'      '0.5'
# log takes the base first: "2 8 log" is log base 2 of 8.
calc_approx '2 8 log'       '3'
calc_approx '10 1000 log'   '3'
calc_approx '1000 log10'    '3'
calc_approx '0.001 log10'   '-3'
calc_approx '-100 log10'    '(2,1.36438)'
calc_approx '(3,4) log10'   '(0.69897,0.402719)'
calc_approx '2 (0,1) log'   '(0,2.26618)'
# sign and abs are for real numbers.
calc_approx '-5 sign'   '-1'
calc_approx '5 sign'    '1'
calc_approx '-5 abs'    '5'
calc_approx '5 abs'     '5'

calc_approx '3 half'       '1.5'
calc_approx '(1,2) half'   '(0.5,1)'
# Expected values for sigma are from Python's cmath, as 1/(1 + exp(-z)).
calc_approx '0 sigma'      '0.5'
calc_approx '2 sigma'      '0.880797'
calc_approx '-2 sigma'     '0.119203'
calc_approx '800 sigma'    '1'
calc_approx '-800 sigma'   '0'
calc_approx '(1,2) sigma'  '(1.02142,0.403439)'
calc_approx '2 4 avg'      '3'
calc_approx '-2 -4 avg'    '-3'
calc_approx '(1,2) (3,1) avg' '(2,1.5)'
# hypot computes sqrt(x^2 + y^2), not the size of a complex number.
calc_approx '3 4 hypot'    '5'
calc_approx '-3 4 hypot'   '5'
calc_approx '0 5 hypot'    '5'
calc_approx '5 0 hypot'    '5'
calc_approx '1 27 hypot'   '27.0185'
calc_approx '(1,1) 1 hypot' '(1.27202,0.786151)'

# Boolean macros, for 0 and 1 only.
calc_approx '0 not'      '1'
calc_approx '1 not'      '0'
calc_approx '0 0 and'   '0'
calc_approx '0 1 and'   '0'
calc_approx '1 0 and'   '0'
calc_approx '1 1 and'   '1'
calc_approx '0 0 or'    '0'
calc_approx '0 1 or'    '1'
calc_approx '1 0 or'    '1'
calc_approx '1 1 or'    '1'
calc_approx '0 0 xor'   '0'
calc_approx '0 1 xor'   '1'
calc_approx '1 0 xor'   '1'
calc_approx '1 1 xor'   '0'
calc_approx '0 0 nand'  '1'
calc_approx '0 1 nand'  '1'
calc_approx '1 0 nand'  '1'
calc_approx '1 1 nand'  '0'
calc_approx '0 0 ->'    '1'
calc_approx '0 1 ->'    '1'
calc_approx '1 0 ->'    '0'
calc_approx '1 1 ->'    '1'

# ! approximates n! = gamma(n + 1). Expected values are from Python's
# math.gamma, or a Lanczos approximation for complex n. Large results are
# scaled down, because their imaginary leftovers are large in absolute terms.
calc_approx '0 !'            '1'
calc_approx '1 !'            '1'
calc_approx '5 !'            '120'
calc_approx '10 !'           '3628800'
calc_approx '20 ! 1e18 /'    '2.43290'
calc_approx '170 ! 1e300 /'  '7257416'
calc_approx '0.5 !'          '0.886227'
calc_approx '-0.5 !'         '1.77245'
calc_approx '-3.5 !'         '-0.945309'
calc_approx '-6.5 !'         '0.0109127'
calc_approx '(0,1) !'        '(0.498016,-0.154950)'
calc_approx '(1,2) !'        '(0.112294,0.323613)'
calc_approx '10 lngamma-big' '12.8018'
calc_approx '5 0 nCr'         '1'
calc_approx '5 2 nCr'         '10'
calc_approx '52 5 nCr'        '2598960'
calc_approx '0.5 2 nCr'       '-0.125'

calc_approx '200 grad->rad'          '3.14159'
calc_approx 'pi rad->grad'           '200'
calc_approx '100 grad->rad rad->deg' '90'

# atan2 takes y, then x, as C's atan2(y, x) does. Expected values are from
# Python's math.atan2. y = 0 with negative x is on the branch cut, so it's
# left out.
calc_approx '1 1 atan2'    '0.785398'
calc_approx '1 -1 atan2'   '2.35619'
calc_approx '-1 -1 atan2'  '-2.35619'
calc_approx '-1 1 atan2'   '-0.785398'
calc_approx '3 4 atan2'    '0.643501'
calc_approx '1 0 atan2'    '1.5708'
calc_approx '-5 0 atan2'   '-1.5708'
calc_approx '0 1 atan2'    '0'

calc_approx '2 pi 4 / polar' '(1.41421,1.41421)'
calc_approx '1 pi polar'     '-1'
calc_approx '3 0 polar'      '3'

# Halves are on the branch cut of round, so they're left out.
calc_approx '2.4 round'    '2'
calc_approx '2.6 round'    '3'
calc_approx '-2.6 round'   '-3'
calc_approx '-0.4 round'   '0'
calc_approx '3 round'      '3'
calc_approx '1234.6 round' '1235'

calc_approx '180 deg->rad'  '3.14159'
calc_approx 'pi rad->deg'   '180'

# wrap360 brings any angle into [0, 360). Multiples of 360 are left out:
# they can come out as either 0 or 360.
calc_approx '30 wrap360'    '30'
calc_approx '-30 wrap360'   '330'
calc_approx '370 wrap360'   '10'
calc_approx '-400 wrap360'  '320'
calc_approx '719.5 wrap360' '359.5'
calc_approx '180 wrap360'   '180'
calc_approx '-180 wrap360'  '180'

# dms->rad gives the minutes and seconds the sign of the degrees, then
# wraps. Angles under 1 degree (0 degrees) are left out: the sign of 0 comes
# out as 0 in the std build and -1 in Boost.
calc_approx '90 0 0 dms->rad'             '1.5708'
calc_approx '30 30 0 dms->rad rad->deg'   '30.5'
calc_approx '-30 30 0 dms->rad rad->deg'  '329.5'
calc_approx '10 20 30 dms->rad rad->deg'  '10.341667'
calc_approx '-10 20 30 dms->rad rad->deg' '349.658333'
calc_approx '400 0 0 dms->rad rad->deg'   '40'

### Trigonometry ###
# Expected values are from Python's cmath, with cot, sec and csc computed as
# 1/tan, 1/cos and 1/sin, and arccot, arcsec and arccsc as arctan(1/z),
# arccos(1/z) and arcsin(1/z). The points avoid the limits in LIMITS.md:
# imaginary parts that make sin and cos wrap, ±1 for arcsin and arccos, and
# branch cuts, where the sign of the imaginary part can differ.

calc_approx '0.5 sin'            '0.479426'
calc_approx '-2 sin'             '-0.909297'
calc_approx '(1,1) sin'          '(1.29846,0.634964)'
calc_approx '(-1,-2) sin'        '(-3.16578,-1.9596)'
calc_approx '0.5 cos'            '0.877583'
calc_approx '-2 cos'             '-0.416147'
calc_approx '(1,1) cos'          '(0.83373,-0.988898)'
calc_approx '(0,-10) cos'        '11013.2'
calc_approx '0.5 tan'            '0.546302'
calc_approx '-2 tan'             '2.18504'
calc_approx '(1,1) tan'          '(0.271753,1.08392)'
calc_approx '(0,-10) tan'        '(0,-1)'
calc_approx '0.5 cot'            '1.83049'
calc_approx '-2 cot'             '0.457658'
calc_approx '(-1,-2) cot'        '(-0.0327978,0.984329)'
calc_approx '0.5 sec'            '1.13949'
calc_approx '10 sec'             '-1.19179'
calc_approx '(0.3,0.4) sec'      '(0.95506,0.11225)'
calc_approx '0.5 csc'            '2.08583'
calc_approx '-2 csc'             '-1.09975'
calc_approx '(-1,-2) csc'        '(-0.228375,0.141363)'
calc_approx '0.5 arcsin'         '0.523599'
calc_approx '-0.5 arcsin'        '-0.523599'
calc_approx '(0.3,0.4) arcsin'   '(0.28063,0.405112)'
calc_approx '(1,2) arcsin'       '(0.427079,1.52857)'
calc_approx '(3,1) arcsin'       '(1.2331,1.8242)'
calc_approx '0.5 arccos'         '1.0472'
calc_approx '-0.5 arccos'        '2.0944'
calc_approx '(0.3,0.4) arccos'   '(1.29017,-0.405112)'
calc_approx '(1,2) arccos'       '(1.14372,-1.52857)'
calc_approx '(5,0.1) arccos'     '(0.0204094,-2.29264)'
calc_approx '0.5 arctan'         '0.463648'
calc_approx '-2 arctan'          '-1.10715'
calc_approx '800 arctan'         '1.56955'
calc_approx '(1,2) arctan'       '(1.33897,0.402359)'
calc_approx '(3,4) arctan'       '(1.44831,0.158997)'
calc_approx '2 arccot'           '0.463648'
calc_approx '-0.5 arccot'        '-1.10715'
calc_approx '(1,2) arccot'       '(0.231824,-0.402359)'
calc_approx '(0,5) arccot'       '(0,-0.202733)'
calc_approx '2 arcsec'           '1.0472'
calc_approx '-2 arcsec'          '2.0944'
calc_approx '(1,2) arcsec'       '(1.38448,0.396568)'
calc_approx '(0,5) arcsec'       '(1.5708,0.19869)'
calc_approx '2 arccsc'           '0.523599'
calc_approx '10 arccsc'          '0.100167'
calc_approx '(1,2) arccsc'       '(0.186318,-0.396568)'
calc_approx '(0,5) arccsc'       '(0,-0.19869)'

# An inverse undoes its function.
calc_approx '0.5 sin arcsin'     '0.5'
calc_approx '0.5 cos arccos'     '0.5'
calc_approx '0.5 tan arctan'     '0.5'
calc_approx '(0.3,0.4) tan arctan' '(0.3,0.4)'

### Hyperbolic functions ###
# Expected values are from Python's cmath, with the reciprocal functions
# computed the same way as for trigonometry. The points avoid the limits in
# LIMITS.md: large imaginary parts in arcsinh and arccosh, and branch cuts.

calc_approx '0.5 sinh'           '0.521095'
calc_approx '-7 sinh'            '-548.316'
calc_approx '(-2,2) sinh'        '(1.50931,3.42095)'
calc_approx '(1,2) sinh'         '(-0.489056,1.40312)'
calc_approx '0.5 cosh'           '1.12763'
calc_approx '-7 cosh'            '548.317'
calc_approx '(-2,2) cosh'        '(-1.56563,-3.29789)'
calc_approx '(1,2) cosh'         '(-0.642148,1.06861)'
calc_approx '0.5 tanh'           '0.462117'
calc_approx '-7 tanh'            '-0.999998'
calc_approx '(-5,1) tanh'        '(-1.00004,8.25672e-05)'
calc_approx '(1,2) tanh'         '(1.16674,-0.243458)'
calc_approx '0.5 coth'           '2.16395'
calc_approx '-2 coth'            '-1.03731'
calc_approx '(1,2) coth'         '(0.82133,0.171384)'
calc_approx '0.5 sech'           '0.886819'
calc_approx '-7 sech'            '0.00182376'
calc_approx '(1,2) sech'         '(-0.413149,-0.687527)'
calc_approx '0.5 csch'           '1.91903'
calc_approx '-2 csch'            '-0.275721'
calc_approx '(1,2) csch'         '(-0.221501,-0.635494)'
calc_approx '0.5 arcsinh'        '0.481212'
calc_approx '-7 arcsinh'         '-2.64412'
calc_approx '(1,2) arcsinh'      '(1.46935,1.06344)'
calc_approx '(-1,-2) arcsinh'    '(-1.46935,-1.06344)'
calc_approx '2 arccosh'          '1.31696'
calc_approx '0.5 arccosh'        '(0,1.0472)'
calc_approx '-0.5 arccosh'       '(0,2.0944)'
calc_approx '(1,2) arccosh'      '(1.52857,1.14372)'
calc_approx '(-1,-2) arccosh'    '(1.52857,-1.99787)'
calc_approx '0.5 arctanh'        '0.549306'
calc_approx '-0.5 arctanh'       '-0.549306'
calc_approx '(1,2) arctanh'      '(0.173287,1.1781)'
calc_approx '(0,4) arctanh'      '(0,1.32582)'
calc_approx '2 arccoth'          '0.549306'
calc_approx '-7 arccoth'         '-0.143841'
calc_approx '(1,2) arccoth'      '(0.173287,-0.392699)'
calc_approx '(0,4) arccoth'      '(0,-0.244979)'
calc_approx '0.5 arcsech'        '1.31696'
calc_approx '2 arcsech'          '(0,1.0472)'
calc_approx '(1,2) arcsech'      '(0.396568,-1.38448)'
calc_approx '(0,4) arcsech'      '(0.247466,-1.5708)'
calc_approx '0.5 arccsch'        '1.44364'
calc_approx '-7 arccsch'         '-0.142376'
calc_approx '(1,2) arccsch'      '(0.215612,-0.401586)'
calc_approx '(0,4) arccsch'      '(0,-0.25268)'

# An inverse undoes its function.
calc_approx '0.5 sinh arcsinh'         '0.5'
calc_approx '0.5 cosh arccosh'         '0.5'
calc_approx '0.5 tanh arctanh'         '0.5'
calc_approx '(0.3,0.4) tanh arctanh'   '(0.3,0.4)'

### --expand ###

check_output "$root" "--expand '1'" '1' '1' --expand
expand '2'           '2'
expand '0'           '0'
expand '-1.5'        '-1.5'
expand '2.5e-1'      '0.25'
expand '(3,4)'       '(3,4)'
expand '(0,-4)'      '(0,-4)'
expand '5 3 -'       '2'
expand '1 2 3 rot 10 / + 10 / +'    '2.31'
expand '1 2 tuck 10 / + 10 / +'     '2.12'
expand '1 2 nip 1 drop'             '2'
expand '-30 30 0 dms->rad rad->deg' '329.5'
expand 'pi'          '3.14159'
expand_error 'foo'   'Unknown macro: foo'

### --strict ###

strict()       { check_approx "$root" "--strict '$1'" "$1" "$2" --strict; }
strict_error() { check_error  "$root" "--strict '$1'" "$1" "$2" --strict; }

check_output "$root" "--strict '1 1 eml'" '1 1 eml' '2.71828' --strict
check_output "$root" "-s '1 1 eml'"       '1 1 eml' '2.71828' -s
strict '1 dup eml'                     '2.71828'
strict '1 1 swap 1 swap eml 1 eml eml' '0'
strict '1 1 eml 1 over eml eml'        '14.6129'
strict '1 1 1 eml 1 rot eml eml'       '14.1543'
strict '1 1 eml 1 tuck eml eml'        '0'
strict '1 1 eml 1 nip'                 '1'
strict '1 1 eml 1 drop'                '2.71828'
strict_error '2'     'Numbers can only be 1. 2 is not 1.'
strict_error '1 exp' 'exp not recognized'
strict_error 'foo'   'foo not recognized'
strict_error 'foo'   'the only operations recognized are:
drop, dup, eml, nip, over, rot, swap, tuck'
strict_error '1 1'   'Too many values on the stack'
strict_error ''      'Empty stack'

# Strict mode doesn't use macros, so it doesn't need library.eml.
mkdir -p "$tmp/empty"
check_output "$tmp/empty" "--strict without library.eml" '1 1 eml' '2.71828' --strict

### Options ###

# check_usage NAME EXPECTED_STDERR_FRAGMENT OPTION...: eml must exit with
# status 2 and print the fragment followed by the usage text.
check_usage()
{
    local name="$1" fragment="$2"
    shift 2
    run_eml "$root" '1' "$@"
    if [ "$status" -ne 2 ]; then
        fail "$name" "eml $*" "exit 2" "exit $status, stderr: $err"
    else
        case "$err" in
            *"$fragment"*"Usage:"*) passed=$((passed + 1)) ;;
            *) fail "$name" "eml $*" "'$fragment' and usage text" "$err" ;;
        esac
    fi
}

check_usage 'unknown long option'  'Unrecognized option: --bogus' --bogus
check_usage 'unknown short option' 'Unrecognized option: -x' -x
check_usage '--library with no path' '--library must be followed by a file path' --library
check_usage '--strict with --expand' 'mutually exclusive' --strict --expand

for help in --help -h; do
    run_eml "$root" '' "$help"
    case "$status:$out" in
        0:Usage:*) passed=$((passed + 1)) ;;
        *) fail "$help" "eml $help" "exit 0, usage text on stdout" "exit $status, stdout: $out" ;;
    esac
done

# --library reads macros from another file instead of ./library.eml.
printf 'x: 1\n' > "$tmp/other.eml"
check_output "$root" '--library FILE' 'x' '1' --library "$tmp/other.eml"
check_output "$root" '-l FILE'        'x' '1' -l "$tmp/other.eml"
check_error  "$root" '--library missing file' '1' \
    "Failed to open \"$tmp/missing.eml\"" --library "$tmp/missing.eml"

### Input files ###

printf '1\n' > "$tmp/one.eml"
printf '1 1 eml\n' > "$tmp/e.eml"
printf '1 1\n' > "$tmp/two.eml"

# Each file is evaluated separately; standard input is ignored.
check_output "$root" 'one file'  'foo' '1' "$tmp/one.eml"
check_output "$root" 'two files' 'foo' "$(printf '1\n2.71828')" \
    "$tmp/one.eml" "$tmp/e.eml"
check_output "$root" 'file with --strict' '' '2.71828' --strict "$tmp/e.eml"
check_error  "$root" 'missing file' '' "File \"$tmp/nosuch.eml\" not found" \
    "$tmp/nosuch.eml"
check_error  "$root" 'file with an error' '' 'Too many values on the stack' \
    "$tmp/two.eml"

### Output format ###
# A number is printed as "re" when its imaginary part is zero, and as
# "(re,im)" otherwise. 1 is never rebuilt, so these are exact in both builds.

calc '1'       '1'
calc '1 1 eml' '2.71828'

### --clean ###
# --clean prints a part as 0 when it's smaller than 10,000 epsilon times the
# size of the number, or 1,000 epsilon, whichever is larger. These outputs
# are the same in both builds.

clean()       { check_output "$root" "--clean '$1'" "$1" "$2" --clean; }

clean '2 10 ^'       '1024'
clean '52 5 nCr'     '2.59896e+06'
clean '170 !'        '7.25742e+306'
clean '(0,4) -1 *'   '(0,-4)'
clean '(0,1) sq'     '-1'
clean 'pi sin'       '0'
clean '1 ln'         '0'
clean '0 -1 *'       '0'
# Parts that aren't noise are kept
clean '(1,2) exp'    '(-1.1312,2.47173)'
clean '-1 ln'        '(0,3.14159)'
clean '1e-9'         '1e-09'
clean '-15 sigma'    '3.05902e-07'
check_output "$root" '-c' '2 10 ^' '1024' -c
check_output "$root" '--clean with --strict' '1 1 eml' '2.71828' --strict --clean
# The stack shown with "Too many values" is cleaned too
check_error "$root" '--clean, too many values' '2 10 ^ 1' \
    "$(printf 'stack\n1\n1024')" --clean

# The floor is 1,000 epsilon: about 2e-13 for std::complex<double> and 5e-48
# for Boost. The std build gives exactly 0 for "1 ln"; Boost doesn't.
run_eml "$root" '1 ln'
if [ "$out" = '0' ]; then
    clean '1e-13'     '0'
    clean '-40 sigma' '0'
else
    clean '1e-13'     '1e-13'
    clean '-40 sigma' '4.24835e-18'
    clean '1e-48'     '0'
fi

### Library loading ###

use_library 'a: 1 dup\nb: a eml\n'
lib '1' '1'
lib 'b' '2.71828'

use_library '# comment\n\nx: 1\n'
lib 'x' '1'
# Numbers other than 1 need the arithmetic macros, but only when one is used.
lib_error '2' 'Library is missing these required macros: ln, -, +, *, /, ^, neg, i'

use_library 'loop: 1 loop\n'
lib_error '1' 'undefined macro loop'

use_library 'a: b\nb: a\n'
lib_error '1' 'undefined macro b'

use_library 'b: 1 a\na: 1\n'
lib_error '1' 'undefined macro a'

use_library 'a: 1 eml1\n'
lib_error '1' 'undefined macro eml1'

use_library 'a: 1\na: 2\n'
lib_error '1' 'Duplicate macros are not allowed (a)'

use_library ': 1\n'
lib_error '1' 'A macro name cannot be empty'

use_library '2: 1\n'
lib_error '1' 'A macro name cannot be a number'

use_library 'dup: 1\n'
lib_error '1' 'dup is a built-in and cannot be a macro'

use_library 'no colon here\n'
lib_error '1' 'No colon found in macro'

rm -f "$lib_dir/library.eml"
lib_error '1' 'Failed to open "library.eml"'

### Infix front end ###
# infix translates infix notation into RPN for eml. infix_rpn checks the
# translation's text; infix_value pipes it into eml and checks the result as
# check_approx does. Skipped if infix isn't built (it needs OCaml).

infix="${INFIX:-$root/infix}"
case "$infix" in
    /*) ;;
    *) infix="$PWD/$infix" ;;
esac

run_infix()      # INPUT [OPTION...]: sets $out, $err and $status
{
    local input="$1"
    shift
    out="$(cd "$root" && printf '%s\n' "$input" | "$infix" "$@" 2>"$tmp/stderr")"
    status=$?
    err="$(cat "$tmp/stderr")"
}

infix_rpn()      # INPUT EXPECTED_RPN
{
    run_infix "$1"
    if [ "$status" -ne 0 ]; then
        fail "infix '$1'" "$1" "$2" "exit $status, stderr: $err"
    elif [ "$out" != "$2" ]; then
        fail "infix '$1'" "$1" "$2" "$out"
    else
        passed=$((passed + 1))
    fi
}

infix_value()    # INPUT EXPECTED_NUMBER
{
    run_infix "$1"
    if [ "$status" -ne 0 ]; then
        fail "infix '$1'" "$1" "$2" "exit $status, stderr: $err"
        return
    fi
    check_approx "$root" "infix '$1' | eml" "$out" "$2"
}

infix_error()    # INPUT EXPECTED_STDERR_FRAGMENT
{
    run_infix "$1"
    if [ "$status" -eq 0 ]; then
        fail "infix '$1'" "$1" "failure containing '$2'" "exit 0, stdout: $out"
    else
        case "$err" in
            *"$2"*) passed=$((passed + 1)) ;;
            *) fail "infix '$1'" "$1" "stderr containing '$2'" "$err" ;;
        esac
    fi
}

if [ ! -x "$infix" ]; then
    echo "note: $infix not found; skipping the infix tests (make infix)"
else

# Precedence and associativity
infix_rpn '1 + 2 * 3'   '2 3 * 1 +'
infix_rpn '(1 + 2) * 3' '1 2 + 3 *'
infix_rpn '8 - 4 - 2'   '8 4 - 2 -'
infix_rpn '8 / 4 / 2'   '8 4 / 2 /'
infix_rpn '2 ^ 3 ^ 2'   '2 3 2 ^ ^'
infix_rpn '2 ** 10'     '2 10 ^'
infix_rpn '2 ^ -3'      '2 -3 ^'
infix_rpn '2 ^ 3!'      '2 3 ! ^'
infix_rpn '+5'          '5'
infix_value '8 - 4 - 2' '2'
infix_value '8 / 4 / 2' '1'
infix_value '2 ^ 3 ^ 2' '512'

# Unary minus binds looser than ^ and !, tighter than * and /. It folds
# into literals; otherwise it's "-1 *", because neg wraps and overflows.
infix_rpn '-3'          '-3'
infix_rpn '--3'         '3'
infix_rpn '-2 ^ 2'      '2 2 ^ -1 *'
infix_rpn '-3!'         '3 ! -1 *'
infix_rpn '-2 * 3'      '-2 3 *'
infix_rpn '-pi'         'pi -1 *'
infix_value '-2 ^ 2'    '-4'
infix_value '-3!'       '-6'
infix_value '-(800 + 0)' '-800'

# Complex literals fold into (re,im) instead of going through +
infix_rpn '4i'          '(0,4)'
infix_rpn 'i'           'i'
infix_rpn '3 + 4i'      '(3,4)'
infix_rpn '3 - 4i'      '(3,-4)'
infix_rpn '4i + 3'      '(3,4)'
infix_rpn '4i - 3'      '(-3,4)'
infix_rpn '-3 - 4i'     '(-3,-4)'
infix_rpn '-(3 + 4i)'   '(-3,-4)'
infix_rpn '3 + 4 * i'   '(3,4)'
infix_rpn '3 + i'       '(3,1)'
infix_rpn '-i'          '(0,-1)'
infix_rpn '2.5e3i'      '(0,2.5e3)'
infix_value '3 + 4i'    '(3,4)'
infix_value '-(0 + 4i)' '(0,-4)'

# Literals go second in + and *, and c - x becomes x * -1 + c
infix_rpn '1 + sin(1)'  '1 sin 1 +'
infix_rpn '2 * sin(1)'  '1 sin 2 *'
infix_rpn 'sin(1) - 1'  '1 sin 1 -'
infix_rpn '1 - sin(1)'  '1 sin -1 * 1 +'
infix_rpn '2 + 3'       '2 3 +'
infix_value '1 - sin(1)' '0.158529'
infix_value '1 - (0 + 4i) * 1' '(1,-4)'

# Number text passes through unchanged, so Boost keeps its precision
infix_rpn '.5 + 1e-3'   '.5 1e-3 +'
infix_rpn '1.'          '1.'
infix_rpn '2E+3'        '2E+3'

# Functions, constants and argument order
infix_rpn 'sin(pi / 4)' 'pi 4 / sin'
infix_rpn 'log(2, 8)'   '2 8 log'
infix_rpn 'root(3, 8)'  '3 8 root'
infix_rpn 'atan2(1, 2)' '1 2 atan2'
infix_rpn 'eml(1, 1)'   '1 1 eml'
infix_rpn 'deg_to_rad(180)'      '180 deg->rad'
infix_rpn 'dms_to_rad(1, 2, 3)'  '1 2 3 dms->rad'
infix_rpn 'lngamma_big(10)'      '10 lngamma-big'
infix_value '1 + 2 * sin(pi / 4)'     '2.41421'
infix_value 'sin(1)^2 + cos(1)^2'     '1'
infix_value 'e ^ (i * pi)'            '-1'
infix_value 'log(2, 8)'               '3'
infix_value 'log10(1000)'             '3'
infix_value 'nCr(52, 5)'              '2598960'
infix_value 'atan2(1, 1) * 4'         '3.14159'
infix_value 'hypot(3, 4)'             '5'
infix_value '5!'                      '120'

# Juxtaposition multiplies. It binds tighter than * and / but looser than
# ^ and !, so 1/2pi is 1/(2pi) and 2pi^2 is 2(pi^2).
infix_rpn '2pi'          '2 pi *'
infix_rpn '2 pi'         '2 pi *'
infix_rpn 'pi e'         'pi e *'
infix_rpn 'pi(2)'        'pi 2 *'
infix_rpn '2(1 + i)'     '2 (1,1) *'
infix_rpn '(1 + 2)(3 + 4)' '1 2 + 3 4 + *'
infix_rpn '(1 + 2)3'     '1 2 + 3 *'
infix_rpn '2sin(1)'      '1 sin 2 *'
infix_rpn 'sin(1)cos(1)' '1 sin 1 cos *'
infix_rpn '3!2'          '3 ! 2 *'
infix_rpn '1/2pi'        '1 2 pi * /'
infix_rpn '2pi^2'        'pi 2 ^ 2 *'
infix_rpn '2^3pi'        '2 3 ^ pi *'
infix_rpn '-2pi'         '-2 pi *'
infix_rpn '2 * 3pi'      '3 pi * 2 *'
infix_rpn '6/2(1 + 2)'   '6 1 2 + 2 * /'
infix_rpn '4 i'          '(0,4)'
infix_rpn '3 + 4 i'      '(3,4)'
# e after a number is an exponent only when digits follow
infix_rpn '2e'           '2 e *'
infix_rpn '2e3'          '2e3'
infix_rpn '2e - 1'       '2 e * 1 -'
infix_value '1/2pi'      '0.159155'
infix_value '6/2(1 + 2)' '1'
infix_value '2e - 1'     '4.43656'

# Errors
infix_error ''              'unexpected end of input'
infix_error '1 +'           'unexpected end of input'
infix_error '(1 + 2'        "missing ')'"
infix_error 'log(2, 8'      "missing ')'"
infix_error '1 + 2)'        "unexpected ')'"
infix_error '1, 2'          "unexpected ','"
infix_error '2 3'           'missing operator between 2 and 3'
infix_error '(1)2 3'        'missing operator between 2 and 3'
infix_error '2 3i'          'missing operator between 2 and 3i'
infix_error '2i 3'          'missing operator between 2i and 3'
infix_error 'pi()'          "unexpected ')'"
infix_error 'pie'           'unknown function pie'
infix_error '1 $ 2'         "unexpected character '\$'"
infix_error 'foo(1)'        'unknown function foo'
infix_error 'sin'           'sin takes 1 argument: sin(...)'
infix_error 'sin()'         'sin takes 1 argument, not 0'
infix_error 'log(8)'        'log takes 2 arguments, not 1'
infix_error 'swap(1, 2)'    "swap leaves 2 values on the stack"
infix_error '1 +'           '<stdin>:1:4: error:'

# Options and files
run_infix '1' --bogus
if [ "$status" -eq 2 ] && case "$err" in *'Unrecognized option: --bogus'*) true ;; *) false ;; esac
then passed=$((passed + 1))
else fail 'infix --bogus' '' 'exit 2, Unrecognized option' "exit $status, stderr: $err"
fi

printf 'sq(3)\n' > "$tmp/a.txt"
printf '1 +\n  2' > "$tmp/b.txt"
run_infix '' "$tmp/a.txt" "$tmp/b.txt"
expected="$(printf '3 sq\n1 2 +')"
if [ "$status" -eq 0 ] && [ "$out" = "$expected" ]
then passed=$((passed + 1))
else fail 'infix with files' '' "$expected" "exit $status, stdout: $out, stderr: $err"
fi

# The library sets which functions exist and their argument counts,
# worked out from the stack effects of the macro bodies.
printf 'three: eml eml\nsecond: rot drop drop\n+: swap drop\n' > "$tmp/infix.eml"
run_infix 'three(1, 2, 3) + second(4, 5, 6)' --library "$tmp/infix.eml"
if [ "$status" -eq 0 ] && [ "$out" = '1 2 3 three 4 5 6 second +' ]
then passed=$((passed + 1))
else fail 'infix --library arities' '' '1 2 3 three 4 5 6 second +' "exit $status, stdout: $out, stderr: $err"
fi
run_infix 'sin(1)' --library "$tmp/infix.eml"
case "$status:$err" in
    1:*'unknown function sin'*) passed=$((passed + 1)) ;;
    *) fail 'infix --library without sin' '' 'unknown function sin' "exit $status, stderr: $err" ;;
esac
run_infix '1' --library "$tmp/missing.eml"
case "$status:$err" in
    1:*'Failed to open'*) passed=$((passed + 1)) ;;
    *) fail 'infix --library missing' '' 'Failed to open' "exit $status, stderr: $err" ;;
esac

fi

### Summary ###

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
