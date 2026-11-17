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

### Summary ###

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
