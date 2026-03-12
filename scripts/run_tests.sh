#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-compiler}"

OS="${RUNNER_OS:-unknown}"
RESULT_DIR="results-${OS}-${MODE}"
mkdir -p "$RESULT_DIR"

PASSED=0
FAILED=0
FILES=()

# Detect CPU cores for parallel testing
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

if [[ "$MODE" == "compiler" ]]; then
    ROOT="c3c"
    C3C="./c3c/build/c3c"
    SEARCH_EXT=(-name ".c3" -o -name ".c3t")
    SEARCH_DIRS=("c3c/resources" "c3c/test")

elif [[ "$MODE" == "vendor" ]]; then
    ROOT="vendor"
    C3C="./c3c/build/c3c"
    SEARCH_EXT=(-name ".c3" -o -name ".c3i")
    SEARCH_DIRS=("vendor/libraries")

else
    echo "Unknown mode: $MODE"
    exit 1
fi

# Ensure compiler exists
if [[ ! -x "$C3C" ]]; then
    echo "Compiler not found: $C3C"
    exit 1
fi

# Collect test files
for dir in "${SEARCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "$dir" -type f ( "${SEARCH_EXT[@]}" ) -print0)
done

TOTAL=${#FILES[@]}

if [[ "$TOTAL" -eq 0 ]]; then
    echo "No test files found."
    echo "$OS|$MODE|0|0|0" > "$RESULT_DIR/.test_results"
    exit 0
fi

echo
echo "Running C3 $MODE checks ($TOTAL files)"
echo "Using $JOBS parallel jobs"
echo

progress_bar() {
    local current=$1
    local total=$2
    local width=40

    local percent=$(( current * 100 / total ))
    local filled=$(( current * width / total ))
    local empty=$(( width - filled ))

    local filled_char=$(printf "\xe2\x96\x88")
    local empty_char=$(printf "\xe2\x96\x91")

    printf "\r["
    for ((i=0;i<filled;i++)); do printf "$filled_char"; done
    for ((i=0;i<empty;i++)); do printf "$empty_char"; done
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

compile_file() {

    file="$1"
    ext="${file##*.}"

    start=$(date +%s%N)

    status=0

    if grep -Eq 'fn[[:space:]]+.main[[:space:]](' "$file"; then
        output=$("$C3C" compile "$file" 2>&1) || status=$?
    else
        tmp=$(mktemp "${TMPDIR:-/tmp}/c3tmpXXXXXX.${ext}")

        cat "$file" > "$tmp"
        echo "" >> "$tmp"
        echo "// injected by CI" >> "$tmp"
        echo "fn void main() => 0;" >> "$tmp"

        output=$("$C3C" compile "$tmp" 2>&1) || status=$?

        rm -f "$tmp"
    fi

    end=$(date +%s%N)
    duration=$(awk "BEGIN {printf "%.3f", ($end-$start)/1000000000}")

    echo "::group::$file (${duration}s)"
    echo "$output"
    echo "::endgroup::"

    if [[ $status -eq 0 ]]; then
        echo "PASS|$file"
    else
        echo "FAIL|$file"
    fi
}

export -f compile_file
export C3C

COUNT=0

printf "%s\n" "${FILES[@]}" |
xargs -I{} -P "$JOBS" bash -c 'compile_file "$@"' _ {} |
while IFS="|" read -r result file; do

    COUNT=$((COUNT+1))

    if [[ "$result" == "PASS" ]]; then
        PASSED=$((PASSED+1))
        echo "$file: Passed"
    else
        FAILED=$((FAILED+1))
        echo "$file: Failed"
    fi

    progress_bar "$COUNT" "$TOTAL"
done

echo
echo
echo "Checks complete. Total $TOTAL files. $PASSED passed. $FAILED failed."

echo "$OS|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_DIR/.test_results"
