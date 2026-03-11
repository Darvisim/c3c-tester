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

    local percent=$(( current * 100 / total ))
    local filled=$(( percent * width / 100 ))
    local empty=$(( width - filled ))

    printf "\r["
    printf "%0.s#" $(seq 1 $filled)
    printf "%0.s-" $(seq 1 $empty)
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

echo
echo "Running C3 test suite ($TOTAL tests)"
echo

for i in "${!FILES[@]}"; do
    file="${FILES[$i]}"
    index=$((i+1))

    start=$(date +%s%N)

    output=""
    status=0

    if [[ "$file" == *.c3t ]]; then
        output=$("$C3C" compile-test "$file" 2>&1) || status=$?
    else
        output=$("$C3C" compile-run "$file" 2>&1) || status=$?
    fi

    end=$(date +%s%N)
    duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")

    echo

    if [[ $status -eq 0 ]]; then
        PASSED=$((PASSED+1))
        echo "::group::✅ $file (${duration}s)"
        echo "$output"
        echo "::endgroup::"
    else
        FAILED=$((FAILED+1))
        echo "❌ $file (${duration}s)"
        echo "$output"
    fi

    progress_bar "$index" "$TOTAL"
done

echo
echo
echo "Tests complete. Total $TOTAL files. $PASSED passed. $FAILED failed."

echo "$TOTAL|$PASSED|$FAILED" > .test_results