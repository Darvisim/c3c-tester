#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

# Relax pipefail temporarily if it causes issues during parallel output processing
set +o pipefail

MODE="${1:-compiler}"
RESULT_DIR="results-${PLATFORM}-${MODE}"
mkdir -p "$RESULT_DIR"

RESULT_FILE="$RESULT_DIR/test_results.txt"
LOG_DIR="test_logs_${PLATFORM}_${MODE}"
mkdir -p "$LOG_DIR"

# Global Counters (Initialized with safe increment values)
PASSED=0
FAILED=0
COUNT=0
TOTAL=0
FILES=()
FAILED_LIST=()

# Detect CPU cores
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

C3C=$(get_c3c_path)
ensure_executable "$C3C"

# Verify compiler exists before starting
if [[ ! -f "$C3C" ]]; then
    log_error "C3 Compiler not found at: $C3C"
    echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
    exit 1
fi

if [[ "$MODE" == "integration" ]]; then
    WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_int_tests')
    log_info "Integration mode: using workspace $WORKDIR"
    [ -d "c3c/resources" ] && cp -r c3c/resources "$WORKDIR/"
    
    run_int_test() {
        local name="$1"
        local cmd="$2"
        local dir="${3:-.}"
        local start=$(date +%s%N)
        local status=0
        echo "::group::$name"
        # Always use absolute path for compiler in eval - use bash expansion for safety
        local resolved_cmd="${cmd//\$C3C/$C3C}"
        (cd "$dir" && eval "$resolved_cmd") || status=$?
        echo "::endgroup::"
        local end=$(date +%s%N)
        local duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")
        if [[ $status -eq 0 ]]; then
            PASSED=$((PASSED + 1))
            log_success "$name: Passed ($duration s)"
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("$name")
            log_error "$name: Failed ($duration s)"
        fi
    }
    
    run_int_test "CLI: init" "\$C3C init-lib mylib && \$C3C init myproject" "$WORKDIR"
    if [ -d "$WORKDIR/resources/testfragments" ]; then
        run_int_test "WASM: Compile Check" "\$C3C compile --target wasm32 -g0 --no-entry -Os wasm4.c3" "$WORKDIR/resources/testfragments"
    fi
    if [ -d "$WORKDIR/resources/examples/staticlib-test" ]; then
        if [[ "$PLATFORM" == "Windows" ]]; then
            run_int_test "Static Lib: Build & Run" "\$C3C -vv static-lib add.c3 && \$C3C -vv compile-run test.c3 -l ./add.lib" "$WORKDIR/resources/examples/staticlib-test"
        else
            run_int_test "Static Lib: Build & Run" "\$C3C -vv static-lib add.c3 -o libadd && \$C3C -vv compile-run test.c3 -L . -l add" "$WORKDIR/resources/examples/staticlib-test"
        fi
    fi
    if [ -d "$WORKDIR/resources/testproject" ]; then
        run_int_test "Project: run" "\$C3C run -vv --trust=full" "$WORKDIR/resources/testproject"
    fi
    run_int_test "CLI: vendor-fetch" "\$C3C vendor-fetch raylib" "$WORKDIR"
    
    rm -rf "$WORKDIR"
    TOTAL=$((PASSED + FAILED))
else
    # File-based test modes (compiler, vendor)
    if [[ "$MODE" == "compiler" ]]; then
        SEARCH_DIRS=("c3c/resources" "c3c/test")
    elif [[ "$MODE" == "vendor" ]]; then
        SEARCH_DIRS=("vendor/libraries")
    else
        log_error "Unknown mode: $MODE"
        exit 1
    fi

    for dir in "${SEARCH_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' file; do FILES+=("$file"); done < <(find "$dir" -type f \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) -print0)
    done

    TOTAL=${#FILES[@]}
    if [[ "$TOTAL" -eq 0 ]]; then
        log_warn "No test files found."
        echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
        exit 0
    fi

    log_info "Running C3 $MODE checks ($TOTAL files) using $JOBS parallel jobs"

    progress_bar() {
        local current=$1; local total=$2; local width=40; local percent=$(( current * 100 / (total > 0 ? total : 1) ))
        local full_char=$(printf "\xe2\x96\x88")
        local filled_blocks=$((percent * width / 100))
        if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
            printf " ["
            for ((i=0;i<filled_blocks;i++)); do printf "%s" "$full_char"; done
            for ((i=filled_blocks;i<width;i++)); do printf " "; done
            printf "] [%3d%%] (%d/%d)\n" "$percent" "$current" "$total"
        else
            printf "\r["
            for ((i=0;i<filled_blocks;i++)); do printf "%s" "$full_char"; done
            for ((i=filled_blocks;i<width;i++)); do printf " "; done
            printf "] %3d%% (%d/%d)" "$percent" "$current" "$total"
        fi
    }

    compile_one() {
        local file="$1"; local log_dir="$2"; local ext="${file##*.}"; local start=$(date +%s%N); local status=0; local output=""; local injected=0
        if ! grep -Eq 'fn[[:space:]]+.*[[:space:]]main[[:space:]]*\(' "$file" && ! grep -Eq 'fn[[:space:]]+main[[:space:]]*\(' "$file"; then
            local tmp_dir="${TMPDIR:-/tmp}/c3c_tests"
            mkdir -p "$tmp_dir"; local base=$(basename "$file"); local tmp="${tmp_dir}/${base%.*}.tmp.${ext}"
            cp "$file" "$tmp"; printf "\n// injected\nfn void main() => 0;\n" >> "$tmp"
            output=$("$C3C" compile "$tmp" 2>&1) || status=$?; rm -f "$tmp"; injected=1
        else
            output=$("$C3C" compile "$file" 2>&1) || status=$?
        fi
        local end=$(date +%s%N); local dur=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")
        local safe=$(echo "$file" | sed 's/[^[:alnum:]]/_/g'); echo -e "$output" > "${log_dir}/${safe}.log"
        if [[ $status -eq 0 ]]; then
            echo "RESULT:PASS|$file|$dur|$injected"
        else
            echo "RESULT:FAIL|$file|$dur|$injected"
        fi
    }
    export -f compile_one log_info log_success log_warn log_error
    export C3C BLUE GREEN YELLOW RED NC

    RESULTS_BUFFER="results_buffer_${PLATFORM}_${MODE}.txt"
    printf "%s\n" "${FILES[@]}" | xargs -I{} -P "$JOBS" bash -c 'compile_one "$@"' _ {} "$LOG_DIR" > "$RESULTS_BUFFER"

    while read -r line; do
        if [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*) ]]; then
            res="${BASH_REMATCH[1]}"; file="${BASH_REMATCH[2]}"; dur="${BASH_REMATCH[3]}"; inj="${BASH_REMATCH[4]}"
            COUNT=$((COUNT + 1))
            echo "::group::$file ($dur s)"
            [[ "$inj" == "1" ]] && log_info "main() was injected."
            safe=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
            [ -f "${LOG_DIR}/${safe}.log" ] && cat "${LOG_DIR}/${safe}.log"
            echo "::endgroup::"
            if [[ "$res" == "PASS" ]]; then
                PASSED=$((PASSED + 1))
                log_success "$file: Passed"
            else
                FAILED=$((FAILED + 1))
                FAILED_LIST+=("$file")
                log_error "$file: Failed"
            fi
            progress_bar "$COUNT" "$TOTAL"
            echo ""
        fi
    done < "$RESULTS_BUFFER"
    rm -f "$RESULTS_BUFFER"
fi

rm -rf "$LOG_DIR"
echo -e "\nChecks complete. Total $TOTAL, $PASSED passed, $FAILED failed."
echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
for fail in "${FAILED_LIST[@]+"${FAILED_LIST[@]}"}"; do
    echo "$fail" >> "$RESULT_FILE"
done
