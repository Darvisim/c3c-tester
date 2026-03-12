#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-compiler}"

OS="${RUNNER_OS:-unknown}"
RESULT_DIR="results-${OS}-${MODE}"
mkdir -p "$RESULT_DIR"

PASSED=0
FAILED=0
FILES=()

if [[ "$MODE" == "compiler" ]]; then
    ROOT="c3c"
    C3C="./c3c/build/c3c"
    SEARCH_EXT=(-name "*.c3" -o -name "*.c3t")
    SEARCH_DIRS=("c3c/resources" "c3c/test")

elif [[ "$MODE" == "vendor" ]]; then
    ROOT="vendor"
    C3C="./c3c/build/c3c"
    SEARCH_EXT=(-name "*.c3" -o -name "*.c3i")
    SEARCH_DIRS=("vendor/libraries")

else
    echo "Unknown mode: $MODE"
    exit 1
fi

for dir in "${SEARCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "$dir" -type f \( "${SEARCH_EXT[@]}" \) -print0)
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

    local filled_char=$(printf "\xe2\x96\x88")
    local empty_char=$(printf "\xe2\x96\x91")

    printf "\r["
    for i in $(seq 1 $filled); do printf "$filled_char"; done
    for i in $(seq 1 $empty); do printf "$empty_char"; done
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

echo
echo "Running C3 $MODE checks ($TOTAL files)"
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
    echo "::group::$file (${duration}s)"
    echo "$output"
    echo "::endgroup::"

    if [[ $status -eq 0 ]]; then
        PASSED=$((PASSED+1))
        echo "$file: Passed"
    else
        FAILED=$((FAILED+1))
        echo "$file: Failed"
    fi

    progress_bar "$index" "$TOTAL"
done

echo
echo
echo "Checks complete. Total $TOTAL files. $PASSED passed. $FAILED failed."

echo "$TOTAL|$PASSED|$FAILED" > "$RESULT_DIR/.test_results"
