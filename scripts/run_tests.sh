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
FILES=()

# Detect CPU cores
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

if [[ "$MODE" == "compiler" ]]; then
    ROOT="c3c"
    C3C="./c3c/build/c3c"
    SEARCH_DIRS=("c3c/resources" "c3c/test")
    EXTENSIONS=("c3" "c3t")

elif [[ "$MODE" == "vendor" ]]; then
    ROOT="vendor"
    C3C="./c3c/build/c3c"
    SEARCH_DIRS=("vendor/libraries")
    EXTENSIONS=("c3" "c3i")

else
    echo "Unknown mode: $MODE"
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

# Ensure compiler exists
if [[ ! -x "$C3C" ]]; then
    echo "Compiler not found: $C3C"
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

# Collect test files
for dir in "${SEARCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue

    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(
        find "$dir" -type f \( \
            -name "*.c3" -o \
            -name "*.c3t" -o \
            -name "*.c3i" \
        \) -print0
    )
done

TOTAL=${#FILES[@]}

if [[ "$TOTAL" -eq 0 ]]; then
    echo "No test files found."
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

echo
echo "Running C3 $MODE checks ($TOTAL files)"
echo "Using $JOBS parallel jobs"
echo

# High resolution progress bar
progress_bar() {

    local current=$1
    local total=$2
    local width=40

    (( current > total )) && current=$total

    local percent=$(( current * 100 / total ))
    (( percent > 100 )) && percent=100

    local parts=(" " "▏" "▎" "▍" "▌" "▋" "▊" "▉")

    local total_blocks=$((width * 8))
    local filled_blocks=$((percent * total_blocks / 100))

    local full_blocks=$((filled_blocks / 8))
    local partial_block=$((filled_blocks % 8))

    printf "\r["

    for ((i=0;i<full_blocks;i++)); do
        printf "█"
    done

    if (( full_blocks < width )); then
        printf "%s" "${parts[$partial_block]}"

        for ((i=full_blocks+1;i<width;i++)); do
            printf " "
        done
    fi

    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

compile_file() {

    file="$1"
    ext="${file##*.}"

    start=$(date +%s%N)

    status=0

    if grep -Eq 'fn[[:space:]]+main[[:space:]]*\(' "$file" 2>/dev/null; then
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
    duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")

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
stdbuf -oL xargs -I{} -P "$JOBS" bash -c 'compile_file "$@"' _ {} |
while IFS="|" read -r result file; do

    COUNT=$((COUNT+1))

    if (( COUNT > TOTAL )); then
        COUNT=$TOTAL
    fi

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

echo "$OS|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
