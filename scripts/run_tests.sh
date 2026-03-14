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

C3C="./c3c/build/c3c"

# Ensure compiler exists
if [[ ! -x "$C3C" ]]; then
    echo "Compiler not found: $C3C"
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

############################################
# Run upstream testproject (integration test)
############################################

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

    if [[ "$RUNNER_OS" == "Windows" ]]; then
        "$C3C" -vv --emit-llvm run hello_world_win32 $ARGS
        "$C3C" clean
        "$C3C" -vv build hello_world_win32_lib $ARGS
    fi

    popd > /dev/null
}

############################################
# Configure search paths
############################################

if [[ "$MODE" == "compiler" ]]; then

    run_testproject

    SEARCH_DIRS=("c3c/resources" "c3c/test")

elif [[ "$MODE" == "vendor" ]]; then

    SEARCH_DIRS=("vendor/libraries")

else
    echo "Unknown mode: $MODE"
    echo "$OS|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

############################################
# Collect test files
############################################

for dir in "${SEARCH_DIRS[@]}"; do

    [ -d "$dir" ] || continue

    while IFS= read -r -d '' file; do

        # Skip integration project files
        if [[ "$file" == *"testproject"* ]]; then
            continue
        fi

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

############################################
# Progress bar (1/8 block resolution)
############################################

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

############################################
# Compilation function
############################################

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

############################################
# Run tests in parallel
############################################

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