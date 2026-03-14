#!/usr/bin/env bash
set -euo pipefail

export LC_ALL=C.UTF-8
export LANG=C.UTF-8

MODE="${1:-compiler}"
OS="${RUNNER_OS:-unknown}"

RESULT_DIR="results-${OS}-${MODE}"
mkdir -p "$RESULT_DIR"
RESULT_FILE="$RESULT_DIR/.test_results"

PASSED=0
FAILED=0

ROOT_DIR=$(pwd)

C3C="$ROOT_DIR/c3c/build/c3c"
if [[ ! -x "$C3C" && -x "$ROOT_DIR/c3c/build/c3c.exe" ]]; then
    C3C="$ROOT_DIR/c3c/build/c3c.exe"
fi

if [[ ! -x "$C3C" ]]; then
    echo "Compiler not found: $C3C"
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

########################################
# Integration testproject
########################################

run_testproject() {

    echo
    echo "Running C3 integration testproject"
    echo

    pushd c3c/resources/testproject > /dev/null

    ARGS="--trust=full"

    case "$RUNNER_OS" in
        Linux|macOS)
            ARGS="$ARGS --linker=builtin"

            if [ -f "/etc/alpine-release" ]; then
                ARGS="$ARGS --linux-libc=musl"
            fi
            ;;
    esac

    "$C3C" run -vv $ARGS
    "$C3C" clean

    popd > /dev/null
}

########################################
# Select test directories
########################################

if [[ "$MODE" == "compiler" ]]; then
    run_testproject
    BASE_DIR="c3c/test"

elif [[ "$MODE" == "vendor" ]]; then
    BASE_DIR="vendor/libraries"

else
    echo "Unknown mode: $MODE"
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

########################################
# Collect test directories
########################################

mapfile -t TEST_DIRS < <(
    find "$BASE_DIR" -mindepth 1 -type d | sort
)

TOTAL=${#TEST_DIRS[@]}

if (( TOTAL == 0 )); then
    echo "No test directories found."
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

########################################
# Parallel jobs
########################################

JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

echo
echo "Running C3 $MODE tests ($TOTAL directories)"
echo "Using $JOBS parallel jobs"
echo

########################################
# Compile directory
########################################

compile_dir() {

    dir="$1"

    status=0
    "$C3C" compile "$dir" >/dev/null 2>&1 || status=$?

    if [[ $status -eq 0 ]]; then
        echo "PASS|$dir"
    else
        echo "FAIL|$dir"
    fi
}

export -f compile_dir
export C3C

########################################
# Run tests
########################################

COUNT=0

printf "%s\n" "${TEST_DIRS[@]}" |
xargs -I{} -P "$JOBS" bash -c 'compile_dir "$@"' _ {} |
while IFS="|" read -r result dir; do

    COUNT=$((COUNT+1))

    if [[ "$result" == "PASS" ]]; then
        PASSED=$((PASSED+1))
        echo "[$COUNT/$TOTAL] PASS $dir"
    else
        FAILED=$((FAILED+1))
        echo "[$COUNT/$TOTAL] FAIL $dir"
    fi

done

########################################
# Summary
########################################

echo
echo "Checks complete."
echo "Total: $TOTAL"
echo "Passed: $PASSED"
echo "Failed: $FAILED"

echo "$OS|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
