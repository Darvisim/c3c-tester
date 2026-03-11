#!/usr/bin/env bash
set -euo pipefail

C3C="./c3c/build/c3c"
TEST_DIRS=("c3c/resources" "c3c/test")

TOTAL=0
PASSED=0
FAILED=0

echo "::group::Running C3 Tests"

progress_bar() {
    local progress=$1
    local total=$2
    local width=40

    if [ "$total" -eq 0 ]; then
        return
    fi

    local done=$((progress * width / total))
    local left=$((width - done))

    printf "\r["
    printf "%0.s#" $(seq 1 $done)
    printf "%0.s-" $(seq 1 $left)
    printf "] %d/%d" "$progress" "$total"
}

FILES=()

for dir in "${TEST_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "$dir" -type f \( -name "*.c3t" -o -name "*.c3" \) -print0)
done

TOTAL=${#FILES[@]}

echo "Found $TOTAL test files"

for i in "${!FILES[@]}"; do
    file="${FILES[$i]}"
    progress_bar $((i+1)) "$TOTAL"

    echo "::group::Test: $file"

    if [[ "$file" == *.c3t ]]; then
        if "$C3C" compile-test "$file"; then
            PASSED=$((PASSED+1))
        else
            FAILED=$((FAILED+1))
        fi
    else
        if "$C3C" compile-run "$file"; then
            PASSED=$((PASSED+1))
        else
            FAILED=$((FAILED+1))
        fi
    fi

    echo "::endgroup::"
done

echo
echo "Tests completed."

echo "::endgroup::"

echo "$TOTAL|$PASSED|$FAILED" > .test_results
