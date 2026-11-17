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
# the output uses only 1, eml, swap and dup, then evaluates that output with
# eml --strict and compares it with EXPECTED_NUMBER as check_approx does.
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
        grep -v -x -e 1 -e eml -e swap -e dup -e '' | sort -u | tr '\n' ' ')"
    if [ -n "$others" ]; then
        fail "$name" "$1" "only 1 eml swap dup" "also: $others"
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

calc_error '1 dup'    'Too many values on the stack'
calc_error '1 2'      'Too many values on the stack'
calc_error 'eml'      'Tried to pop an empty stack'
calc_error 'exp'      'Tried to pop an empty stack'
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

### --expand ###

check_output "$root" "--expand '1'" '1' '1' --expand
expand '2'           '2'
expand '0'           '0'
expand '-1.5'        '-1.5'
expand '2.5e-1'      '0.25'
expand '(3,4)'       '(3,4)'
expand '(0,-4)'      '(0,-4)'
expand '5 3 -'       '2'
expand 'pi'          '3.14159'
expand_error 'foo'   'Unknown macro: foo'

### --strict ###

strict()       { check_approx "$root" "--strict '$1'" "$1" "$2" --strict; }
strict_error() { check_error  "$root" "--strict '$1'" "$1" "$2" --strict; }

check_output "$root" "--strict '1 1 eml'" '1 1 eml' '2.71828' --strict
check_output "$root" "-s '1 1 eml'"       '1 1 eml' '2.71828' -s
strict '1 dup eml'                     '2.71828'
strict '1 1 swap 1 swap eml 1 eml eml' '0'
strict_error '2'     'Numbers can only be 1. 2 is not 1.'
strict_error '1 exp' 'exp not recognized'
strict_error 'foo'   'foo not recognized'
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
