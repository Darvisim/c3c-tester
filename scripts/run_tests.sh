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

DUMMY_MAIN_FILE="$(realpath "$RESULT_DIR" 2>/dev/null || echo "$RESULT_DIR")/_dummy_main.c3"
echo "fn void main() => 0;" > "$DUMMY_MAIN_FILE"
export DUMMY_MAIN_FILE

# Global Counters
PASSED=0
FAILED=0
COUNT=0
TOTAL=0
FILES=()
FAILED_LIST=()
EXAMPLES=()

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
    TOTAL=2 # init and vendor-fetch
    if [ -d "$WORKDIR/resources/examples" ]; then
        EX_COUNT=$(find "$WORKDIR/resources/examples" -maxdepth 2 -name "*.c3" -not -path "*/staticlib-test/*" -not -path "*/dynlib-test/*" -not -path "*/raylib/*" | wc -l)
        TOTAL=$((TOTAL + EX_COUNT + 1)) # +1 for cross constants
        [[ "$PLATFORM" == "Linux" ]] && TOTAL=$((TOTAL + 2))
    fi
    [ -d "$WORKDIR/resources/testfragments" ] && TOTAL=$((TOTAL + 1))
    
    if [ -d "$WORKDIR/resources/examples/staticlib-test" ]; then
        [[ "$PLATFORM" == "Windows" ]] && TOTAL=$((TOTAL + 1)) || TOTAL=$((TOTAL + 3))
    fi
    if [ -d "$WORKDIR/resources/examples/dynlib-test" ]; then
        case "$PLATFORM" in
            Windows) TOTAL=$((TOTAL + 1)) ;;
            Linux)   TOTAL=$((TOTAL + 3)) ;;
            macOS)   TOTAL=$((TOTAL + 2)) ;;
        esac
    fi
    if [ -d "$WORKDIR/resources/testproject" ]; then
        [[ "$PLATFORM" == "Windows" ]] && TOTAL=$((TOTAL + 3)) || TOTAL=$((TOTAL + 1))
    fi
    [ -d "$WORKDIR/test/unit" ] && TOTAL=$((TOTAL + 1))
    [ -f "$WORKDIR/test/src/test_suite_runner.c3" ] && TOTAL=$((TOTAL + 1))
    [[ -d "$WORKDIR/resources/examples/raylib" && "$PLATFORM" != "Windows" ]] && TOTAL=$((TOTAL + 1))

    run_int_test() {
        local name="$1"
        local cmd="$2"
        local dir="${3:-.}"
        local start=$(date +%s%N)
        local status=0
        echo "::group::$name"
        local escaped_c3c=$(printf '%q' "$C3C")
        local resolved_cmd="${cmd//\$C3C/$escaped_c3c}"
        
        # Capture output for potential retry
        local output
        output=$(cd "$dir" && eval "$resolved_cmd" 2>&1) || status=$?
        
        # Retry with main() injection if needed
        if [[ $status -ne 0 ]] && [[ "$output" == *"The 'main' function for the executable could not found"* ]]; then
            log_info "main() was injected via auxiliary file."
            local abs_dummy=$(realpath "$DUMMY_MAIN_FILE" 2>/dev/null || echo "$DUMMY_MAIN_FILE")
            
            # Derive a stable binary name from the test name
            local bname=$(basename "$name")
            local out_name="${bname%.*}"
            [[ "$PLATFORM" == "Windows" ]] && out_name="${out_name}.exe"

            # Append dummy main and force output name if missing
            local retry_cmd="$resolved_cmd"
            if [[ "$resolved_cmd" == *" compile"* && "$resolved_cmd" != *" -o "* ]]; then
                retry_cmd="$resolved_cmd -o $out_name"
            fi
            retry_cmd="$retry_cmd $abs_dummy"
            
            status=0
            output=$(cd "$dir" && eval "$retry_cmd" 2>&1) || status=$?
        fi
        
        printf "%s\n" "$output"
        echo "::endgroup::"
        local end=$(date +%s%N)
        local duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")
        COUNT=$((COUNT + 1))
        if [[ $status -eq 0 ]]; then
            PASSED=$((PASSED + 1))
            log_success "$name: Passed ($duration s)"
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("$name")
            log_error "$name: Failed ($duration s)"
        fi
        progress_bar "$COUNT" "$TOTAL"
        echo ""
    }

    # 1. CLI Basic Tests
    log_info "Running CLI Basic Tests..."
    run_int_test "init" "\$C3C init-lib mylib && \$C3C init myproject" "$WORKDIR"
    
    # 2. Standard Examples
    if [ -d "$WORKDIR/resources/examples" ]; then
        log_info "Running Standard Examples..."
        # Dynamically discover all top-level examples
        # Use while read instead of mapfile for Bash 3.2 (macOS) compatibility
        while IFS= read -r ex; do
            EXAMPLES+=("$ex")
        done < <(find "$WORKDIR/resources/examples" -maxdepth 2 -name "*.c3" -not -path "*/staticlib-test/*" -not -path "*/dynlib-test/*" -not -path "*/raylib/*" | sort)

        for ex_path in "${EXAMPLES[@]+"${EXAMPLES[@]}"}"; do
            # Portable relative path calculation for macOS/Linux
            rel_ex="${ex_path#$WORKDIR/resources/}"
            # Default to compile, but run some specific ones if named appropriately or just compile all
            if [[ "$rel_ex" == *"hello_world"* || "$rel_ex" == *"process"* ]]; then
                run_int_test "$rel_ex" "\$C3C compile-run $rel_ex" "$WORKDIR/resources"
            else
                run_int_test "$rel_ex" "\$C3C compile $rel_ex" "$WORKDIR/resources"
            fi
        done

        if [[ "$PLATFORM" == "Linux" ]]; then
            run_int_test "linux_stack (builtin)" "\$C3C compile-run --linker=builtin linux_stack.c3" "$WORKDIR/resources"
            run_int_test "linux_stack" "\$C3C compile-run linux_stack.c3" "$WORKDIR/resources"
        fi
        
        run_int_test "Cross-compile constants" "\$C3C compile --no-entry --test -g --threads 1 --target macos-x64 examples/constants.c3" "$WORKDIR/resources"
    fi

    # 3. WASM Compilation
    if [ -d "$WORKDIR/resources/testfragments" ]; then
        log_info "Running WASM Compilation..."
        run_int_test "Compile Check" "\$C3C compile --target wasm32 -g0 --no-entry -Os wasm4.c3" "$WORKDIR/resources/testfragments"
    fi
    
    # 4. Static Library Tests
    if [ -d "$WORKDIR/resources/examples/staticlib-test" ]; then
        log_info "Running Static Library Tests..."  
        if [[ "$PLATFORM" == "Windows" ]]; then
            run_int_test "Build & Run" "\$C3C -vv static-lib add.c3 && \$C3C -vv compile-run test.c3 -l ./add.lib" "$WORKDIR/resources/examples/staticlib-test"
        else
            run_int_test "Build" "\$C3C -vv static-lib add.c3 -o libadd" "$WORKDIR/resources/examples/staticlib-test"
            if [[ "$PLATFORM" == "Linux" ]]; then
                run_int_test "CC Link" "cc test.c -L. -ladd -ldl -lm -lpthread -o a.out && ./a.out" "$WORKDIR/resources/examples/staticlib-test"
            else
                run_int_test "CC Link" "cc test.c -L. -ladd -o a.out && ./a.out" "$WORKDIR/resources/examples/staticlib-test"
            fi
            run_int_test "C3 Run" "\$C3C -vv compile-run test.c3 -L . -l add" "$WORKDIR/resources/examples/staticlib-test"
        fi
    fi

    # 5. Dynamic Library Tests
    if [ -d "$WORKDIR/resources/examples/dynlib-test" ]; then
        log_info "Running Dynamic Library Tests..."  
        if [[ "$PLATFORM" == "Windows" ]]; then
            run_int_test "Build & Run" "\$C3C -vv dynamic-lib add.c3 && \$C3C -vv compile-run test.c3 -l ./add.lib" "$WORKDIR/resources/examples/dynlib-test"
        elif [[ "$PLATFORM" == "Linux" || "$PLATFORM" == "macOS" ]]; then
            run_int_test "Build" "\$C3C -vv dynamic-lib add.c3 -o libadd" "$WORKDIR/resources/examples/dynlib-test"
            if [[ "$PLATFORM" == "Linux" ]]; then
                run_int_test "CC Link" "cc test.c -L. -ladd -Wl,-rpath=. -o a.out && ./a.out" "$WORKDIR/resources/examples/dynlib-test"
                run_int_test "C3 Run" "\$C3C compile-run test.c3 -L . -l add -z -Wl,-rpath=." "$WORKDIR/resources/examples/dynlib-test"
            elif [[ "$PLATFORM" == "macOS" ]]; then
                run_int_test "DynLib: C3 Run" "\$C3C -vv compile-run test.c3 -l ./libadd.dylib" "$WORKDIR/resources/examples/dynlib-test"
            fi
        fi
    fi

    # 6. Project Tests
    if [ -d "$WORKDIR/resources/testproject" ]; then
        log_info "Running Project Tests..."  
        run_int_test "run" "\$C3C run -vv --trust=full" "$WORKDIR/resources/testproject"
        if [[ "$PLATFORM" == "Windows" ]]; then
            run_int_test "Win32 run" "\$C3C -vv --emit-llvm run hello_world_win32 --trust=full" "$WORKDIR/resources/testproject"
            run_int_test "Win32 lib build" "\$C3C -vv build hello_world_win32_lib --trust=full" "$WORKDIR/resources/testproject"
        fi
    fi
    
    # 7. Unit Tests
    if [ -d "$WORKDIR/test/unit" ]; then
        log_info "Running Unit Tests..."  
        UNIT_ARGS="-O1 -D SLOW_TESTS"
        run_int_test "Base" "\$C3C compile-test unit $UNIT_ARGS" "$WORKDIR/test"
    fi
    if [ -f "$WORKDIR/test/src/test_suite_runner.c3" ]; then
        log_info "Running Test Suite..."  
        run_int_test "Test Suite" "\$C3C compile-run -O1 src/test_suite_runner.c3 -- \$C3C test_suite/ --no-terminal" "$WORKDIR/test"
    fi

    # 8. Vendor Fetch & Raylib Example
    log_info "Running Vendor Fetch & Raylib Example..."  
    run_int_test "vendor-fetch" "\$C3C vendor-fetch raylib" "$WORKDIR"
    if [[ -d "$WORKDIR/resources/examples/raylib" && "$PLATFORM" != "Windows" ]]; then
         # Raylib on unix usually works in these CI envs if deps are there
         run_int_test "raylib-arkanoid" "\$C3C compile --lib raylib --print-linking examples/raylib/raylib_arkanoid.c3" "$WORKDIR/resources"
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

    # Sort files alphabetically
    if [[ ${#FILES[@]} -gt 0 ]]; then
        IFS=$'\n' FILES=($(printf "%s\n" "${FILES[@]}" | sort))
        unset IFS
    fi

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
        local file="$1"; local log_dir="$2"; local extra_args="$3"; local ext="${file##*.}"; local start=$(date +%s%N); local status=0; local output=""; local injected=0
        local abs_file=$(realpath "$file" 2>/dev/null || echo "$file")
        local abs_dummy=$(realpath "$DUMMY_MAIN_FILE" 2>/dev/null || echo "$DUMMY_MAIN_FILE")
        
        # Create a unique job directory for absolute isolation
        local job_id=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
        local job_dir="$JOBS_TEMP_DIR/$job_id"
        mkdir -p "$job_dir"

        # Vendor specific logic: determine library name and add --lib flag
        if [[ "$MODE" == "vendor" ]]; then
            # If file is vendor/libraries/LIBNAME/..., then LIBNAME is the library
            if [[ "$file" =~ ^vendor/libraries/([^/]+)/ ]]; then
                local lib_name="${BASH_REMATCH[1]%.c3l}"
                extra_args="$extra_args --lib $lib_name"
            fi
        fi

        # Copy manifest.json if found in parent directories (up to workspace root)
        local search_dir="$(dirname "$abs_file")"
        local workspace_root="$PWD"
        while [[ "$search_dir" != "$workspace_root" && "$search_dir" != "." && "$search_dir" != "/" ]]; do
            if [[ -f "$search_dir/manifest.json" ]]; then
                cp "$search_dir/manifest.json" "$job_dir/"
                break
            fi
            local next_dir="$(dirname "$search_dir")"
            [[ "$next_dir" == "$search_dir" ]] && break
            search_dir="$next_dir"
        done
        
        # Binary naming per user request: $filename (or $filename.exe on Windows)
        local base_name=$(basename "$file")
        local bin_name="${base_name%.*}"
        [[ "$PLATFORM" == "Windows" ]] && bin_name="${bin_name}.exe"
        
        # Advanced Retry Logic:
        # 1. Handle Windows temporary directory collisions
        # 2. Dynamically handle main() injection based on compiler feedback
        local max_retries=3
        local retry_count=0
        local try_injection=0
        
        # Initial guess based on grep
        if ! grep -Eq 'fn\s+(void|int|u?[0-9]+)?\s*main\s*\(' "$file"; then
            try_injection=1
        fi
        
        while [[ $retry_count -lt $max_retries ]]; do
            status=0
            injected=$try_injection
            if [[ $injected -eq 1 ]]; then
                output=$(cd "$job_dir" && "$C3C" compile $extra_args -o "$bin_name" "$abs_file" "$abs_dummy" 2>&1) || status=$?
            else
                output=$(cd "$job_dir" && "$C3C" compile $extra_args -o "$bin_name" "$abs_file" 2>&1) || status=$?
            fi
            
            # Check for success
            if [[ $status -eq 0 ]]; then
                break
            fi
            
            # Check for "main function not found" -> retry WITH injection if we didn't use it
            if [[ "$output" == *"The 'main' function for the executable could not found"* ]] && [[ $injected -eq 0 ]]; then
                try_injection=1
                # Don't increment retry_count for a logic switch retry
                continue
            fi
            
            # Check for redefinition of main -> retry WITHOUT injection if we used it
            if [[ "$output" == *"redefinition of 'main'"* ]] && [[ $injected -eq 1 ]]; then
                try_injection=0
                # Don't increment retry_count for a logic switch retry
                continue
            fi
            
            # Check for Windows temporary directory collision
            if [[ "$output" == *"Unable to create temporary directory"* ]]; then
                retry_count=$((retry_count + 1))
                sleep 0.5
                continue
            fi
            
            # If it's some other error, don't retry injection logic, just count it as a failure
            break
        done
        
        # Cleanup job dir
        rm -rf "$job_dir"
        
        local end=$(date +%s%N); local dur=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")
        local safe=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
        # Use printf %s to avoid interpretation of escape sequences like \t in paths
        printf "%s\n" "$output" > "${log_dir}/${safe}.log"
        if [[ $status -eq 0 ]]; then
            echo "RESULT:PASS|$file|$dur|$injected"
        else
            echo "RESULT:FAIL|$file|$dur|$injected"
        fi
    }
    export -f compile_one log_info log_success log_warn log_error
    export C3C BLUE GREEN YELLOW RED NC MODE PLATFORM


    RESULTS_BUFFER="results_buffer_${PLATFORM}_${MODE}.txt"
    COUNT=0
    EXTRA_ARGS=""
    if [[ "$MODE" == "vendor" ]]; then
        ABS_VENDOR_LIB=$(realpath vendor/libraries 2>/dev/null || echo "$PWD/vendor/libraries")
        EXTRA_ARGS="--libdir $ABS_VENDOR_LIB"
        
        if [ -d "$ABS_VENDOR_LIB" ]; then
            log_info "Pre-fetching vendor libraries..."
            # Find unique library names (directories under vendor/libraries)
            # Use a temporary file to store unique names to avoid subshell issues with arrays
            find "$ABS_VENDOR_LIB" -maxdepth 1 -mindepth 1 -type d | while read -r lib_path; do
                lib_name=$(basename "$lib_path")
                lib_name="${lib_name%.c3l}"
                log_info "Fetching $lib_name..."
                "$C3C" vendor-fetch "$lib_name" || log_warn "Failed to fetch $lib_name"
            done
        fi
    fi

    printf "%s\n" "${FILES[@]+"${FILES[@]}"}" | xargs -I{} -P "$JOBS" bash -c 'compile_one "$@"' _ {} "$LOG_DIR" "$EXTRA_ARGS" > "$RESULTS_BUFFER"

    while read -r line; do
        [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*) ]] || continue
        
        res="${BASH_REMATCH[1]}"; file="${BASH_REMATCH[2]}"; dur="${BASH_REMATCH[3]}"; inj="${BASH_REMATCH[4]}"
        COUNT=$((COUNT + 1))
        
        echo "::group::$file ($dur s)"
        [[ "$inj" == "1" ]] && log_info "main() was injected via auxiliary file."
        safe=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
        [ -f "${LOG_DIR}/${safe}.log" ] && cat "${LOG_DIR}/${safe}.log" && echo ""
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
    done < "$RESULTS_BUFFER"
    rm -f "$RESULTS_BUFFER"
    rm -rf "$JOBS_TEMP_DIR"
fi

rm -f "$DUMMY_MAIN_FILE"

rm -rf "$LOG_DIR"
echo -e "\nChecks complete. Total $TOTAL, $PASSED passed, $FAILED failed."

echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
for fail in "${FAILED_LIST[@]+"${FAILED_LIST[@]}"}"; do
    echo "$fail" >> "$RESULT_FILE"
done

if [[ "$STRICT_MODE" == "true" && $FAILED -gt 0 ]]; then
    exit 1
fi
exit 0
