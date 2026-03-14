#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

MODE="${1:-compiler}"
RESULT_DIR="results-${PLATFORM}-${MODE}"
mkdir -p "$RESULT_DIR"

RESULT_FILE="$RESULT_DIR/test_results.txt"

PASSED=0
FAILED=0
FILES=()

# Detect CPU cores
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

if [[ "$MODE" == "compiler" ]]; then
    ROOT="c3c"
    SEARCH_DIRS=("c3c/resources" "c3c/test")
    EXTENSIONS=("c3" "c3t")
elif [[ "$MODE" == "vendor" ]]; then
    ROOT="vendor"
    SEARCH_DIRS=("vendor/libraries")
    EXTENSIONS=("c3" "c3i")
else
    log_error "Unknown mode: $MODE"
    echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

C3C=$(get_c3c_path)

# Ensure compiler exists and is executable
if [[ -f "$C3C" ]]; then
    ensure_executable "$C3C"
else
    log_error "Compiler not found: $C3C"
    echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

# Collect test files
for dir in "${SEARCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do
        FILES+=("$file")
    done < <(find "$dir" -type f \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) -print0)
done

TOTAL=${#FILES[@]}

if [[ "$TOTAL" -eq 0 ]]; then
    log_warn "No test files found."
    echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

log_info "Running C3 $MODE checks ($TOTAL files) using $JOBS parallel jobs"

progress_bar() {
    local current=$1
    local total=$2
    local width=40
    local percent=$(( current * 100 / total ))
    # Hex codes for UTF-8 characters:
    # █ -> \xe2\x96\x88
    # ▏ -> \xe2\x96\x8f
    # ... and so on. We'll use a simpler bar for CI if needed, 
    # but the user wants the "shapes" replaced with hex codes.
    local full_char=$(printf "\xe2\x96\x88")
    local parts=($(printf "\x20") 
                  $(printf "\xe2\x96\x8f") 
                  $(printf "\xe2\x96\x8e") 
                  $(printf "\xe2\x96\x8d") 
                  $(printf "\xe2\x96\x8c") 
                  $(printf "\xe2\x96\x8b") 
                  $(printf "\xe2\x96\x8a") 
                  $(printf "\xe2\x96\x89"))

    local filled_blocks=$((percent * width * 8 / 100))
    local full_blocks=$((filled_blocks / 8))
    local partial_block=$((filled_blocks % 8))

    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        # In CI, only print every 5% to avoid log bloat, but show the bar
        if [[ $(( current % (total / 20 + 1) )) -eq 0 || $current -eq $total ]]; then
            printf " [" "$percent"
            for ((i=0;i<full_blocks;i++)); do printf "%s" "$full_char"; done
            if (( full_blocks < width )); then
                printf "%s" "${parts[$partial_block]}"
                for ((i=full_blocks+1;i<width;i++)); do printf " "; done
            fi
            printf "] [%3d%%] (%d/%d)\n" "$current" "$total"
        fi
        return
    fi

    printf "\r["
    for ((i=0;i<full_blocks;i++)); do printf "%s" "$full_char"; done
    if (( full_blocks < width )); then
        printf "%s" "${parts[$partial_block]}"
        for ((i=full_blocks+1;i<width;i++)); do printf " "; done
    fi
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

compile_file() {
    local file="$1"
    local ext="${file##*.}"
    local start=$(date +%s%N)
    local status=0

    # Inject main if missing. Robustly check for 'fn ... main('
    if ! grep -Eq 'fn[[:space:]]+.*main[[:space:]]*\(' "$file"; then
        local tmp=$(mktemp "${TMPDIR:-/tmp}/c3tmpXXXXXX.${ext}")
        cp "$file" "$tmp"
        printf "\n// injected by CI\nfn void main() => 0;\n" >> "$tmp"
        output=$("$C3C" compile "$tmp" 2>&1) || status=$?
        rm -f "$tmp"
    else
        output=$("$C3C" compile "$file" 2>&1) || status=$?
    fi

    local end=$(date +%s%N)
    local duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")

    echo "::group::$file (${duration}s)"
    echo "$output"
    echo "::endgroup::"

    if [[ $status -eq 0 ]]; then
        echo "RESULT:PASS|$file"
    else
        echo "RESULT:FAIL|$file"
    fi
}

export -f compile_file
export C3C

COUNT=0
printf "%s\n" "${FILES[@]}" | xargs -I{} -P "$JOBS" bash -c 'compile_file "$@"' _ {} | while read -r line; do
    if [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*) ]]; then
        result="${BASH_REMATCH[1]}"
        file="${BASH_REMATCH[2]}"
        COUNT=$((COUNT+1))
        if [[ "$result" == "PASS" ]]; then
            PASSED=$((PASSED+1))
            echo "::notice file=$file::Passed"
        else
            FAILED=$((FAILED+1))
            echo "::error file=$file::Failed"
        fi
        progress_bar "$COUNT" "$TOTAL"
    else
        echo "$line"
    fi
done

echo -e "\n\nChecks complete. Total $TOTAL files. $PASSED passed. $FAILED failed."
echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
