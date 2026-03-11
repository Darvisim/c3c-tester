#!/usr/bin/env bash
set -euo pipefail

C3C="./c3c/build/c3c"
TEST_DIRS=("c3c/resources" "c3c/test")

PASSED=0
FAILED=0
FILES=()

for dir in "${TEST_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "$dir" -type f \( -name "*.c3t" -o -name "*.c3" \) -print0)
done

TOTAL=${#FILES[@]}

progress_bar() {
    local current=$1
    local total=$2
    local width=40

    [ "$total" -eq 0 ] && return
    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    # Universal UTF-8 Hex Sequences
    local filled_char=$(printf "\xe2\x96\x88") # Solid Block █
    local empty_char=$(printf "\xe2\x96\x91")  # Light Shade ░

    printf "\r["
    for i in $(seq 1 $filled); do printf "$filled_char"; done
    for i in $(seq 1 $empty); do printf "$empty_char"; done
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

echo
echo "Running C3 test suite ($TOTAL tests)"
echo

for i in "${!FILES[@]}"; do
    file="${FILES[$i]}"
    index=$((i+1))

    start=$(date +%s%N)

    status=0
    output=$("$C3C" compile "$file" 2>&1) || status=$?

    end=$(date +%s%N)
    duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")

    echo

    if [[ $status -eq 0 ]]; then
        PASSED=$((PASSED+1))
        echo "::group::$file (${duration}s)"
        echo "$output"
        echo "::endgroup::"
        echo "$file: Passed"
    else
        FAILED=$((FAILED+1))
        echo "::group::$file (${duration}s)"
        echo "$output"
        echo "::endgroup::"
        echo "$file: Failed"
    fi

    progress_bar "$index" "$TOTAL"
done

echo
echo
echo "Tests complete. Total $TOTAL files. $PASSED passed. $FAILED failed."

echo "$TOTAL|$PASSED|$FAILED" > .test_results
