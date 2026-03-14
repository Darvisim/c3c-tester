#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

MODE="${1:-compiler}"
RESULT_DIR="results-${PLATFORM}-${MODE}"
mkdir -p "$RESULT_DIR"

RESULT_FILE="$RESULT_DIR/test_results.txt"
LOG_DIR="test_logs_${PLATFORM}_${MODE}"
mkdir -p "$LOG_DIR"

PASSED=0
FAILED=0
FILES=()
FAILED_LIST=()

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
    local full_char=$(printf "\xe2\x96\x88")

    local filled_blocks=$((percent * width / 100))

    if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
        printf " ["
        for ((i=0;i<filled_blocks;i++)); do printf "%s" "$full_char"; done
        for ((i=filled_blocks;i<width;i++)); do printf " "; done
        printf "] [%3d%%] (%d/%d)\n" "$percent" "$current" "$total"
        return
    fi

    printf "\r["
    for ((i=0;i<filled_blocks;i++)); do printf "%s" "$full_char"; done
    for ((i=filled_blocks;i<width;i++)); do printf " "; done
    printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
}

compile_file() {
    local file="$1"
    local log_dir="$2"
    local ext="${file##*.}"
    local start=$(date +%s%N)
    local status=0
    local output=""
    local injected=0
    
    # Safe mktemp for macOS/Linux/Windows
    local safe_fname=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
    local log_file="${log_dir}/${safe_fname}.log"

    # Improved main() detection
    if ! grep -Eq 'fn[[:space:]]+([[:alnum:]_<>\[\]*]+[[:space:]]+)?main[[:space:]]*\(' "$file"; then
        local tmp_dir="${TMPDIR:-/tmp}/c3c_tests"
        mkdir -p "$tmp_dir"
        local tmp="${tmp_dir}/$(basename "$file").${ext}"
        cp "$file" "$tmp"
        printf "\n// injected by CI\nfn void main() => 0;\n" >> "$tmp"
        output=$("$C3C" compile "$tmp" 2>&1) || status=$?
        rm -f "$tmp"
        injected=1
    else
        output=$("$C3C" compile "$file" 2>&1) || status=$?
    fi

    local end=$(date +%s%N)
    local duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")

    # Write logs to file to ensure atomicity later
    echo -e "$output" > "$log_file"
    
    # Return compact status line
    if [[ $status -eq 0 ]]; then
        echo "RESULT:PASS|$file|$duration|$injected"
    else
        echo "RESULT:FAIL|$file|$duration|$injected"
    fi
}

export -f compile_file log_info log_success log_warn log_error
export C3C BLUE GREEN YELLOW RED NC

COUNT=0
printf "%s\n" "${FILES[@]}" | xargs -I{} -P "$JOBS" bash -c 'compile_file "$@"' _ {} "$LOG_DIR" | while read -r line; do
    if [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*) ]]; then
        res="${BASH_REMATCH[1]}"
        file="${BASH_REMATCH[2]}"
        dur="${BASH_REMATCH[3]}"
        inj="${BASH_REMATCH[4]}"
        
        safe_fname=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
        log_file="${LOG_DIR}/${safe_fname}.log"
        
        COUNT=$((COUNT+1))
        
        # Serialized atomic output
        echo "::group::$file (${dur}s)"
        if [[ "$inj" == "1" ]]; then
            log_info "main() was injected for this file."
        fi
        cat "$log_file"
        echo "::endgroup::"
        
        if [[ "$res" == "PASS" ]]; then
            PASSED=$((PASSED+1))
            log_success "$file: Passed"
        else
            FAILED=$((FAILED+1))
            FAILED_LIST+=("$file")
            log_error "$file: Failed"
        fi
        
        progress_bar "$COUNT" "$TOTAL"
        echo "" # Separation
    else
        echo "$line"
    fi
done

rm -rf "$LOG_DIR"

echo -e "\n\nChecks complete. Total $TOTAL files. $PASSED passed. $FAILED failed."

echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
for fail in "${FAILED_LIST[@]}"; do
    echo "$fail" >> "$RESULT_FILE"
done
