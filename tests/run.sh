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

# same_number ACTUAL EXPECTED: true if both are "(re,im)" and each part
# matches to within 1e-5 (relative to its size, or absolute below 1).
same_number()
{
    awk -v a="$1" -v b="$2" 'BEGIN {
        if (a !~ /^\(.*,.*\)$/ || b !~ /^\(.*,.*\)$/) exit 1
        gsub(/[()]/, "", a); gsub(/[()]/, "", b)
        split(a, x, ","); split(b, y, ",")
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

check_approx()   # DIR NAME INPUT EXPECTED_NUMBER
{
    run_eml "$1" "$3"
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
# the output uses only 1, eml, swap and dup, then evaluates that output and
# compares it with EXPECTED_NUMBER as check_approx does.
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
    run_eml "$root" "$expanded"
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

calc_approx '2 1 eml'    '(7.38906,0)'
calc        '1 exp'      '(2.71828,0)'
calc_approx '2 ln'       '(0.693147,0)'
calc_approx '1e2 ln'     '(4.60517,0)'
calc_approx '5 3 -'      '(2,0)'
calc_approx '-1 ln'      '(0,3.14159)'
calc        '(1,2) exp'  '(-1.1312,2.47173)'
calc_approx '1 2 swap -' '(1,0)'

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

calc_approx '0'           '(0,0)'
calc_approx '00'          '(0,0)'
calc_approx '-0'          '(0,0)'
calc_approx '7'           '(7,0)'
calc_approx '23'          '(23,0)'
calc_approx '102'         '(102,0)'
calc_approx '05'          '(5,0)'
calc_approx '+4'          '(4,0)'
calc_approx '-3'          '(-3,0)'
calc_approx '2.5'         '(2.5,0)'
calc_approx '.5'          '(0.5,0)'
calc_approx '5.'          '(5,0)'
calc_approx '-1.5'        '(-1.5,0)'
calc_approx '0.05'        '(0.05,0)'
calc_approx '3.14159'     '(3.14159,0)'
calc_approx '0.0'         '(0,0)'
calc_approx '1e2'         '(100,0)'
calc_approx '1E2'         '(100,0)'
calc_approx '1e0'         '(1,0)'
calc_approx '2e3'         '(2000,0)'
calc_approx '5e-2'        '(0.05,0)'
calc_approx '-4E+1'       '(-40,0)'
calc_approx '1.5e2'       '(150,0)'
calc_approx '000e2'       '(0,0)'
calc_approx '(3,4)'       '(3,4)'
calc_approx '(-3,4)'      '(-3,4)'
calc_approx '(3,-4)'      '(3,-4)'
calc_approx '(0,4)'       '(0,4)'
calc_approx '(0,-4)'      '(0,-4)'
calc_approx '(4,0)'       '(4,0)'
calc_approx '(0,0)'       '(0,0)'
calc_approx '(5)'         '(5,0)'
calc_approx '(1000,5000)' '(1000,5000)'
calc_approx '(5000,1000)' '(5000,1000)'
calc_approx '(0.5,-1.25)' '(0.5,-1.25)'
calc_approx '(1e2,-3e1)'  '(100,-30)'
calc_approx '1 2.5 +'     '(3.5,0)'

### --expand ###

check_output "$root" "--expand '1'" '1' '1' --expand
expand '2'           '(2,0)'
expand '0'           '(0,0)'
expand '-1.5'        '(-1.5,0)'
expand '2.5e-1'      '(0.25,0)'
expand '(3,4)'       '(3,4)'
expand '(0,-4)'      '(0,-4)'
expand '5 3 -'       '(2,0)'
expand 'pi'          '(3.14159,0)'
expand_error 'foo'   'Unknown macro: foo'

### Library loading ###

use_library 'a: 1 dup\nb: a eml\n'
lib '1' '(1,0)'
lib 'b' '(2.71828,0)'

use_library '# comment\n\nx: 1\n'
lib 'x' '(1,0)'
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
lib_error '1' 'Failed to open library.eml'

### Summary ###

echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]
