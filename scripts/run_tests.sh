#!/usr/bin/env bash
set -euo pipefail

C3C="./c3c/build/c3c"
TEST_DIRS=("resources" "tests")
TOTAL=0
PASSED=0
FAILED=0

echo "::group::Running C3 Tests"

# Simple shell progress bar
progress_bar() {
    local progress=$1
    local total=$2
    local width=40
    local done=$((progress * width / total))
    local left=$((width - done))
    printf "\r[%0.s#" $(seq 1 $done)
    printf "%0.s-" $(seq 1 $left)
    printf " %d/%d" "$progress" "$total"
}

# Collect all test files
FILES=()
for dir in "${TEST_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d $'\0' file; do
        FILES+=("$file")
    done < <(find "$dir" -type f \( -name "*.c3t" -o -name "*.c3" \) -print0)
done

TOTAL=${#FILES[@]}

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
    elif [[ "$file" == *.c3 ]]; then
        if "$C3C" compile-run "$file"; then
            PASSED=$((PASSED+1))
        else
            FAILED=$((FAILED+1))
        fi
    fi
    echo "::endgroup::"
done

echo -e "\nTests completed."
echo "::endgroup::"

# Export results for summary.sh
echo "$TOTAL|$PASSED|$FAILED" > .test_results
