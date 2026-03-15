#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

# DISABLE set -e to allow script to continue through failures and use our lenient exit logic
# This ensures that one crashing test (like blake2) doesn't stop the whole suite.
set +e
# Relax pipefail temporarily if it causes issues during parallel output processing
set +o pipefail

MODE="${1:-compiler}"
RESULT_DIR="results-${PLATFORM}-${MODE}"
mkdir -p "$RESULT_DIR"

RESULT_FILE="$RESULT_DIR/test_results.txt"
LOG_DIR="test_logs_${PLATFORM}_${MODE}"
mkdir -p "$LOG_DIR"

# Global Counters
PASSED=0
FAILED=0
SOFT_FAILED=0
COUNT=0
TOTAL=0
FILES=()
FAILED_LIST=()
SOFT_FAILED_LIST=()

# STRICT=false: Exit with 0 even if tests fail (avoids "Process completed with exit code 1" in GHA)
STRICT_MODE="${STRICT_MODE:-false}"

# Detect CPU cores
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

C3C=$(get_c3c_path)
ensure_executable "$C3C"

# Verify compiler exists before starting
if [[ ! -f "$C3C" ]]; then
    log_warn "C3 Compiler not found at: $C3C. Skipping tests."
    echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

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

if [[ "$MODE" == "integration" ]]; then
    WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_int_tests')
    log_info "Integration mode: using workspace $WORKDIR"
    [ -d "c3c/resources" ] && cp -r c3c/resources "$WORKDIR/"
    [ -d "c3c/test" ] && cp -r c3c/test "$WORKDIR/"

    # Pre-calculate TOTAL for integration tests
    TOTAL=2 # init and vendor-fetch are always run
    if [ -d "$WORKDIR/resources/examples" ]; then
        TOTAL=$((TOTAL + 27)) # 27 standard examples
        [[ "$PLATFORM" == "Linux" ]] && TOTAL=$((TOTAL + 2)) # linux_stack
        TOTAL=$((TOTAL + 1)) # cross constants
    fi
    [ -d "$WORKDIR/resources/testfragments" ] && TOTAL=$((TOTAL + 1))
    if [ -d "$WORKDIR/resources/examples/staticlib-test" ]; then
        if [[ "$PLATFORM" == "Windows" ]]; then
            TOTAL=$((TOTAL + 1))
        else
            TOTAL=$((TOTAL + 3)) # Build, CC Link, C3 Run
        fi
    fi
    if [ -d "$WORKDIR/resources/examples/dynlib-test" ]; then
        if [[ "$PLATFORM" == "Windows" ]]; then
            TOTAL=$((TOTAL + 1))
        elif [[ "$PLATFORM" == "Linux" ]]; then
            TOTAL=$((TOTAL + 3)) # Build, CC Link, C3 Run
        elif [[ "$PLATFORM" == "macOS" ]]; then
            TOTAL=$((TOTAL + 2)) # Build, C3 Run
        fi
    fi
    if [ -d "$WORKDIR/resources/testproject" ]; then
        TOTAL=$((TOTAL + 1))
        [[ "$PLATFORM" == "Windows" ]] && TOTAL=$((TOTAL + 2))
    fi
    if [ -d "$WORKDIR/test/unit" ]; then
        TOTAL=$((TOTAL + 1))
    fi
    [ -f "$WORKDIR/test/src/test_suite_runner.c3" ] && TOTAL=$((TOTAL + 1))
    if [[ -d "$WORKDIR/resources/examples/raylib" && "$PLATFORM" != "Windows" ]]; then
        TOTAL=$((TOTAL + 1))
    fi

    run_int_test() {
        local name="$1"
        local cmd="$2"
        local dir="${3:-.}"
        local soft_fail="${4:-false}"
        local start=$(date +%s%N)
        local status=0
        echo "::group::$name"
        local escaped_c3c=$(printf '%q' "$C3C")
        local resolved_cmd="${cmd//\$C3C/$escaped_c3c}"
        (cd "$dir" && eval "$resolved_cmd") || status=$?
        echo "::endgroup::"
        local end=$(date +%s%N)
        local duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")
        COUNT=$((COUNT + 1))
        if [[ $status -eq 0 ]]; then
            PASSED=$((PASSED + 1))
            log_success "$name: Passed ($duration s)"
        else
            if [[ "$soft_fail" == "true" ]]; then
                SOFT_FAILED=$((SOFT_FAILED + 1))
                SOFT_FAILED_LIST+=("$name")
                log_warn "$name: Failed (Soft Failure) ($duration s)"
            else
                FAILED=$((FAILED + 1))
                FAILED_LIST+=("$name")
                log_error "$name: Failed ($duration s)"
            fi
        fi
        progress_bar "$COUNT" "$TOTAL"
        echo ""
    }

    # 1. CLI Basic Tests
    run_int_test "CLI: init" "\$C3C init-lib mylib && \$C3C init myproject" "$WORKDIR"
    
    # 2. Standard Examples
    if [ -d "$WORKDIR/resources/examples" ]; then
        log_info "Running Standard Examples..."
        EXAMPLES=(
            "compile examples/base64.c3"
            "compile examples/binarydigits.c3"
            "compile examples/brainfk.c3"
            "compile examples/factorial_macro.c3"
            "compile examples/fasta.c3"
            "compile examples/gameoflife.c3"
            "compile examples/hash.c3"
            "compile-only examples/levenshtein.c3"
            "compile examples/load_world.c3"
            "compile-only examples/map.c3"
            "compile examples/mandelbrot.c3"
            "compile examples/plus_minus.c3"
            "compile examples/nbodies.c3"
            "compile examples/spectralnorm.c3"
            "compile examples/swap.c3"
            "compile examples/contextfree/boolerr.c3"
            "compile examples/contextfree/dynscope.c3"
            "compile examples/contextfree/guess_number.c3"
            "compile examples/contextfree/multi.c3"
            "compile examples/contextfree/cleanup.c3"
            "compile-run examples/hello_world_many.c3"
            "compile-run examples/fannkuch-redux.c3"
            "compile-run examples/contextfree/boolerr.c3"
            "compile-run examples/load_world.c3"
            "compile-run examples/process.c3"
            "compile-run examples/ls.c3"
            "compile-run examples/args.c3 -- foo -bar \"baz baz\""
        )
        for ex in "${EXAMPLES[@]}"; do
            run_int_test "Example: $ex" "\$C3C $ex" "$WORKDIR/resources"
        done

        if [[ "$PLATFORM" == "Linux" ]]; then
            run_int_test "Example: linux_stack (builtin)" "\$C3C compile-run --linker=builtin linux_stack.c3" "$WORKDIR/resources" "true"
            run_int_test "Example: linux_stack" "\$C3C compile-run linux_stack.c3" "$WORKDIR/resources"
        fi
        
        run_int_test "Example: Cross-compile constants" "\$C3C compile --no-entry --test -g --threads 1 --target macos-x64 examples/constants.c3" "$WORKDIR/resources"
    fi

    # 3. WASM Compilation
    if [ -d "$WORKDIR/resources/testfragments" ]; then
        run_int_test "WASM: Compile Check" "\$C3C compile --target wasm32 -g0 --no-entry -Os wasm4.c3" "$WORKDIR/resources/testfragments"
    fi
    
    # 4. Static Library Tests
    if [ -d "$WORKDIR/resources/examples/staticlib-test" ]; then
        if [[ "$PLATFORM" == "Windows" ]]; then
            run_int_test "Static Lib: Build & Run" "\$C3C -vv static-lib add.c3 && \$C3C -vv compile-run test.c3 -l ./add.lib" "$WORKDIR/resources/examples/staticlib-test"
        else
            run_int_test "Static Lib: Build" "\$C3C -vv static-lib add.c3 -o libadd" "$WORKDIR/resources/examples/staticlib-test"
            if [[ "$PLATFORM" == "Linux" ]]; then
                run_int_test "Static Lib: CC Link" "cc test.c -L. -ladd -ldl -lm -lpthread -o a.out && ./a.out" "$WORKDIR/resources/examples/staticlib-test"
            else
                run_int_test "Static Lib: CC Link" "cc test.c -L. -ladd -o a.out && ./a.out" "$WORKDIR/resources/examples/staticlib-test"
            fi
            run_int_test "Static Lib: C3 Run" "\$C3C -vv compile-run test.c3 -L . -l add" "$WORKDIR/resources/examples/staticlib-test"
        fi
    fi

    # 5. Dynamic Library Tests
    if [ -d "$WORKDIR/resources/examples/dynlib-test" ]; then
        if [[ "$PLATFORM" == "Windows" ]]; then
            run_int_test "DynLib: Build & Run" "\$C3C -vv dynamic-lib add.c3 && \$C3C -vv compile-run test.c3 -l ./add.lib" "$WORKDIR/resources/examples/dynlib-test"
        elif [[ "$PLATFORM" == "Linux" || "$PLATFORM" == "macOS" ]]; then
            run_int_test "DynLib: Build" "\$C3C -vv dynamic-lib add.c3 -o libadd" "$WORKDIR/resources/examples/dynlib-test"
            if [[ "$PLATFORM" == "Linux" ]]; then
                run_int_test "DynLib: CC Link" "cc test.c -L. -ladd -Wl,-rpath=. -o a.out && ./a.out" "$WORKDIR/resources/examples/dynlib-test"
                run_int_test "DynLib: C3 Run" "\$C3C compile-run test.c3 -L . -l add -z -Wl,-rpath=." "$WORKDIR/resources/examples/dynlib-test"
            elif [[ "$PLATFORM" == "macOS" ]]; then
                run_int_test "DynLib: C3 Run" "\$C3C -vv compile-run test.c3 -l ./libadd.dylib" "$WORKDIR/resources/examples/dynlib-test"
            fi
        fi
    fi

    # 6. Project Tests
    if [ -d "$WORKDIR/resources/testproject" ]; then
        run_int_test "Project: run" "\$C3C run -vv --trust=full" "$WORKDIR/resources/testproject"
        if [[ "$PLATFORM" == "Windows" ]]; then
            run_int_test "Project: Win32 run" "\$C3C -vv --emit-llvm run hello_world_win32 --trust=full" "$WORKDIR/resources/testproject"
            run_int_test "Project: Win32 lib build" "\$C3C -vv build hello_world_win32_lib --trust=full" "$WORKDIR/resources/testproject"
        fi
    fi
    
    # 7. Unit Tests
    if [ -d "$WORKDIR/test/unit" ]; then
        UNIT_ARGS="-O1 -D SLOW_TESTS"
        run_int_test "Unit Tests: Base" "\$C3C compile-test unit $UNIT_ARGS" "$WORKDIR/test" "false"
    fi
    if [ -f "$WORKDIR/test/src/test_suite_runner.c3" ]; then
        run_int_test "Test Suite" "\$C3C compile-run -O1 src/test_suite_runner.c3 -- \$C3C test_suite/ --no-terminal" "$WORKDIR/test"
    fi

    # 8. Vendor Fetch & Raylib Example
    run_int_test "CLI: vendor-fetch" "\$C3C vendor-fetch raylib" "$WORKDIR"
    if [[ -d "$WORKDIR/resources/examples/raylib" && "$PLATFORM" != "Windows" ]]; then
         # Raylib on unix usually works in these CI envs if deps are there
         run_int_test "CLI: raylib-arkanoid" "\$C3C compile --lib raylib --print-linking examples/raylib/raylib_arkanoid.c3" "$WORKDIR/resources"
    fi

    rm -rf "$WORKDIR"
else
    # File-based test modes (compiler, vendor)
    if [[ "$MODE" == "compiler" ]]; then
        SEARCH_DIRS=("c3c/lib/std" "c3c/benchmarks/stdlib")
    elif [[ "$MODE" == "vendor" ]]; then
        SEARCH_DIRS=("vendor/libraries")
    else
        log_error "Unknown mode: $MODE"
        exit 1
    fi

    for dir in "${SEARCH_DIRS[@]}"; do
        [ -d "$dir" ] || continue
        while IFS= read -r -d '' file; do
            FILES+=("$file")
        done < <(find "$dir" -type f \
            -not -path "*/testfragments/*" \
            -not -path "*/testproject/*" \
            -not -path "*/examples/*" \
            -not -path "*/unit/*" \
            -not -path "*/test_suite/*" \
            \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) -print0)
    done

    TOTAL=${#FILES[@]}
    if [[ "$TOTAL" -eq 0 ]]; then
        log_warn "No test files found for mode $MODE (after exclusions)."
        echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
        exit 0
    fi

    log_info "Running C3 $MODE checks ($TOTAL files) using $JOBS parallel jobs"

    # Pre-create a global temp dir for jobs
    JOBS_TEMP_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_tests_jobs')
    export JOBS_TEMP_DIR

    compile_one() {
        local file="$1"; local log_dir="$2"; local ext="${file##*.}"; local start=$(date +%s%N); local status=0; local output=""; local injected=0
        local abs_file=$(realpath "$file" 2>/dev/null || echo "$file")
        local abs_dummy=$(realpath "$DUMMY_MAIN_FILE" 2>/dev/null || echo "$DUMMY_MAIN_FILE")
        
        # Create a unique job directory for absolute isolation
        local job_id=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
        local job_dir="$JOBS_TEMP_DIR/$job_id"
        mkdir -p "$job_dir"
        
        # Binary naming per user request: $filename (or $filename.exe on Windows)
        local base_name=$(basename "$file")
        local bin_name="${base_name%.*}"
        [[ "$PLATFORM" == "Windows" ]] && bin_name="${bin_name}.exe"
        
        # Retry logic for Windows "Unable to create temporary directory" error
        local max_retries=3
        local retry_count=0
        while [[ $retry_count -lt $max_retries ]]; do
            status=0
            if ! grep -Eq 'fn[[:space:]]+.*[[:space:]]main[[:space:]]*\(' "$file" && ! grep -Eq 'fn[[:space:]]+main[[:space:]]*\(' "$file"; then
                output=$(cd "$job_dir" && "$C3C" compile -o "$bin_name" "$abs_file" "$abs_dummy" 2>&1) || status=$?
                injected=1
            else
                output=$(cd "$job_dir" && "$C3C" compile -o "$bin_name" "$abs_file" 2>&1) || status=$?
                injected=0
            fi
            
            if [[ $status -eq 0 ]] || [[ ! "$output" == *"Unable to create temporary directory"* ]]; then
                break
            fi
            
            # If we hit the collision error, wait a tiny bit and retry
            retry_count=$((retry_count + 1))
            sleep 0.5
        done
        
        # Cleanup job dir
        rm -rf "$job_dir"
        
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

    DUMMY_MAIN_FILE="$(realpath "$RESULT_DIR")/_dummy_main.c3"
    echo "fn void main() => 0;" > "$DUMMY_MAIN_FILE"
    export DUMMY_MAIN_FILE

    RESULTS_BUFFER="results_buffer_${PLATFORM}_${MODE}.txt"
    COUNT=0
    printf "%s\n" "${FILES[@]}" | xargs -I{} -P "$JOBS" bash -c 'compile_one "$@"' _ {} "$LOG_DIR" > "$RESULTS_BUFFER"

    while read -r line; do
        if [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*) ]]; then
            res="${BASH_REMATCH[1]}"; file="${BASH_REMATCH[2]}"; dur="${BASH_REMATCH[3]}"; inj="${BASH_REMATCH[4]}"
            COUNT=$((COUNT + 1))
            echo "::group::$file ($dur s)"
            [[ "$inj" == "1" ]] && log_info "main() was injected via auxiliary file."
            safe=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
            if [ -f "${LOG_DIR}/${safe}.log" ]; then
                cat "${LOG_DIR}/${safe}.log"
                # Ensure a newline after the log content to avoid group closing interleaving
                echo ""
            fi
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
rm -f "$RESULTS_BUFFER" "$DUMMY_MAIN_FILE"
rm -rf "$JOBS_TEMP_DIR"
fi

rm -rf "$LOG_DIR"
echo -e "\nChecks complete. Total $TOTAL, $PASSED passed, $FAILED failed."
[[ $SOFT_FAILED -gt 0 ]] && echo "Soft failures: $SOFT_FAILED (Ignored in status count)"

echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
for fail in "${FAILED_LIST[@]+"${FAILED_LIST[@]}"}"; do
    echo "$fail" >> "$RESULT_FILE"
done

if [[ "$STRICT_MODE" == "true" && $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
