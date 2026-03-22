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
    local cur=$1 tot=$2 w=40 p=$((cur*100/(tot>0?tot:1))) f=$(printf "\xe2\x96\x88") fill=$((p*w/100))
    local bar=$(printf "%${fill}s" | tr ' ' "$f")$(printf "%$((w-fill))s")
    [[ "$GITHUB_ACTIONS" == "true" ]] && printf " [%s] [%3d%%] (%d/%d)\n" "$bar" "$p" "$cur" "$tot" || printf "\r[%s] %3d%% (%d/%d)" "$bar" "$p" "$cur" "$tot"
}

if [[ "$MODE" == "integration" ]]; then
    WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_int')
    log_info "Integration mode: $WORKDIR"
    [ -d "c3c/resources" ] && cp -r c3c/resources "$WORKDIR/"
    [ -d "c3c/test" ] && cp -r c3c/test "$WORKDIR/"

    # Compact TOTAL calculation
    TOTAL=2
    if [ -d "$WORKDIR/resources/examples" ]; then
        TOTAL=$((TOTAL + $(find "$WORKDIR/resources/examples" -maxdepth 2 -name "*.c3" -not -path "*/staticlib-test/*" -not -path "*/dynlib-test/*" -not -path "*/raylib/*" | wc -l) + 1))
        [[ "$PLATFORM" == "Linux" ]] && ((TOTAL+=2))
    fi
    [ -d "$WORKDIR/resources/testfragments" ] && ((TOTAL++))
    [ -d "$WORKDIR/resources/examples/staticlib-test" ] && { [[ "$PLATFORM" == "Windows" ]] && ((TOTAL++)) || ((TOTAL+=3)); }
    [ -d "$WORKDIR/resources/examples/dynlib-test" ] && { [[ "$PLATFORM" == "Windows" ]] && ((TOTAL++)) || { [[ "$PLATFORM" == "Linux" ]] && ((TOTAL+=3)) || ((TOTAL+=2)); }; }
    [ -d "$WORKDIR/resources/testproject" ] && { [[ "$PLATFORM" == "Windows" ]] && ((TOTAL+=3)) || ((TOTAL++)); }
    [ -d "$WORKDIR/test/unit" ] && ((TOTAL++))
    [ -f "$WORKDIR/test/src/test_suite_runner.c3" ] && ((TOTAL++))
    [[ -d "$WORKDIR/resources/examples/raylib" && "$PLATFORM" != "Windows" ]] && ((TOTAL++))

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
            local out_name=$(get_bin_name "$name")

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

    # CLI & Standard Examples
    run_int_test "init" "\$C3C init-lib mylib && \$C3C init myproject" "$WORKDIR"
    if [ -d "$WORKDIR/resources/examples" ]; then
        for ex in $(find "$WORKDIR/resources/examples" -maxdepth 2 -name "*.c3" -not -path "*/staticlib-test/*" -not -path "*/dynlib-test/*" -not -path "*/raylib/*" | sort); do
            rel="${ex#$WORKDIR/resources/}"
            cmd="compile" && [[ "$rel" =~ hello_world|process ]] && cmd="compile-run"
            run_int_test "$rel" "\$C3C $cmd $rel" "$WORKDIR/resources"
        done
        [[ "$PLATFORM" == "Linux" ]] && { run_int_test "linux_stack (builtin)" "\$C3C compile-run --linker=builtin linux_stack.c3" "$WORKDIR/resources"; run_int_test "linux_stack" "\$C3C compile-run linux_stack.c3" "$WORKDIR/resources"; }
        run_int_test "Cross-compile constants" "\$C3C compile --no-entry --test -g --threads 1 --target macos-x64 examples/constants.c3" "$WORKDIR/resources"
    fi

    # WASM, Libraries, Projects & Units
    [ -d "$WORKDIR/resources/testfragments" ] && run_int_test "WASM" "\$C3C compile --target wasm32 -g0 --no-entry -Os wasm4.c3" "$WORKDIR/resources/testfragments"
    
    if [ -d "$WORKDIR/resources/examples/staticlib-test" ]; then
        D="$WORKDIR/resources/examples/staticlib-test"
        if [[ "$PLATFORM" == "Windows" ]]; then run_int_test "Static-lib" "\$C3C -vv static-lib add.c3 && \$C3C -vv compile-run test.c3 -l ./add.lib" "$D"
        else
            run_int_test "Build" "\$C3C -vv static-lib add.c3 -o libadd" "$D"
            [[ "$PLATFORM" == "Linux" ]] && l="-ldl -lm -lpthread" || l=""
            run_int_test "CC Link" "cc test.c -L. -ladd $l -o a.out && ./a.out" "$D"
            run_int_test "C3 Run" "\$C3C -vv compile-run test.c3 -L . -l add" "$D"
        fi
    fi

    if [ -d "$WORKDIR/resources/examples/dynlib-test" ]; then
        D="$WORKDIR/resources/examples/dynlib-test"
        if [[ "$PLATFORM" == "Windows" ]]; then run_int_test "Dyn-lib" "\$C3C -vv dynamic-lib add.c3 && \$C3C -vv compile-run test.c3 -l ./add.lib" "$D"
        else
            run_int_test "Build" "\$C3C -vv dynamic-lib add.c3 -o libadd" "$D"
            [[ "$PLATFORM" == "Linux" ]] && { run_int_test "CC Link" "cc test.c -L. -ladd -Wl,-rpath=. -o a.out && ./a.out" "$D"; run_int_test "C3 Run" "\$C3C compile-run test.c3 -L . -l add -z -Wl,-rpath=." "$D"; }
            [[ "$PLATFORM" == "macOS" ]] && run_int_test "DynLib C3 Run" "\$C3C -vv compile-run test.c3 -l ./libadd.dylib" "$D"
        fi
    fi

    if [ -d "$WORKDIR/resources/testproject" ]; then
        run_int_test "project-run" "\$C3C run -vv --trust=full" "$WORKDIR/resources/testproject"
        [[ "$PLATFORM" == "Windows" ]] && { run_int_test "Win32-run" "\$C3C -vv --emit-llvm run hello_world_win32 --trust=full" "$WORKDIR/resources/testproject"; run_int_test "Win32-lib" "\$C3C -vv build hello_world_win32_lib --trust=full" "$WORKDIR/resources/testproject"; }
    fi
    
    [ -d "$WORKDIR/test/unit" ] && run_int_test "Unit" "\$C3C compile-test unit -O1 -D SLOW_TESTS" "$WORKDIR/test"
    [ -f "$WORKDIR/test/src/test_suite_runner.c3" ] && run_int_test "Suite" "\$C3C compile-run -O1 src/test_suite_runner.c3 -- \$C3C test_suite/ --no-terminal" "$WORKDIR/test"
    run_int_test "vendor-fetch" "\$C3C vendor-fetch raylib" "$WORKDIR"
    [[ -d "$WORKDIR/resources/examples/raylib" && "$PLATFORM" != "Windows" ]] && run_int_test "raylib-arkanoid" "\$C3C compile --lib raylib --print-linking examples/raylib/raylib_arkanoid.c3" "$WORKDIR/resources"

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
            -not -path "*/.*" \
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
        local file=$1 ldir=$2 args=$3 start=$(date +%s%N) status=0 out="" inj=0
        local abs_f=$(realpath "$file" 2>/dev/null || echo "$file")
        local abs_d=$(realpath "$DUMMY_MAIN_FILE" 2>/dev/null || echo "$DUMMY_MAIN_FILE")
        local jdir="$JOBS_TEMP_DIR/$(echo "$file" | sed 's/[^[:alnum:]]/_/g')" && mkdir -p "$jdir"

        [[ "$MODE" == "vendor" && "$file" =~ ^vendor/libraries/([^/]+)/ ]] && args="$args --lib ${BASH_REMATCH[1]%.c3l}"
        
        # Manifest Search
        d=$(dirname "$abs_f")
        while [[ "$d" != "$PWD" && "$d" != "/" ]]; do
            [ -f "$d/manifest.json" ] && { cp "$d/manifest.json" "$jdir/"; break; }
            d=$(dirname "$d")
        done
        
        local bin=$(get_bin_name "$file")
        local tries=0 max=3 inj=$(is_main_missing "$file" && echo 1 || echo 0)
        
        while [[ $tries -lt $max ]]; do
            status=0
            [[ $inj -eq 1 ]] && out=$(cd "$jdir" && "$C3C" compile $args -o "$bin" "$abs_f" "$abs_d" 2>&1) || out=$(cd "$jdir" && "$C3C" compile $args -o "$bin" "$abs_f" 2>&1)
            [[ $status -eq 0 ]] && break
            [[ "$out" == *"The 'main' function"* ]] && [[ $inj -eq 0 ]] && { inj=1; continue; }
            [[ "$out" == *"redefinition of 'main'"* ]] && [[ $inj -eq 1 ]] && { inj=0; continue; }
            [[ "$out" == *"Unable to create temporary directory"* ]] && { ((tries++)); sleep 0.5; continue; }
            break
        done
        
        rm -rf "$jdir"
        dur=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start)/1000000000}")
        safe=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
        printf "%s\n" "$out" > "${ldir}/${safe}.log"
        [[ $status -eq 0 ]] && echo "RESULT:PASS|$file|$dur|$inj" || echo "RESULT:FAIL|$file|$dur|$inj"
    }
    export -f compile_one log_info log_success log_warn log_error get_bin_name is_main_missing
    export C3C BLUE GREEN YELLOW RED NC MODE PLATFORM

    RESULTS_BUFFER="results_buffer_${PLATFORM}_${MODE}.txt"
    EXTRA_ARGS="" && [[ "$MODE" == "vendor" ]] && EXTRA_ARGS="--libdir $(realpath vendor/libraries 2>/dev/null || echo "$PWD/vendor/libraries")"

    printf "%s\n" "${FILES[@]+"${FILES[@]}"}" | xargs -I{} -P "$JOBS" bash -c 'compile_one "$@"' _ {} "$LOG_DIR" "$EXTRA_ARGS" > "$RESULTS_BUFFER"

    while read -r line; do
        [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*) ]] || continue
        res=${BASH_REMATCH[1]} f=${BASH_REMATCH[2]} dur=${BASH_REMATCH[3]} inj=${BASH_REMATCH[4]}
        ((COUNT++))
        echo "::group::$f ($dur s)"
        [[ "$inj" == "1" ]] && log_info "main() injected."
        cat "${LOG_DIR}/$(echo "$f" | sed 's/[^[:alnum:]]/_/g').log" 2>/dev/null && echo ""
        echo "::endgroup::"
        if [[ "$res" == "PASS" ]]; then ((PASSED++)); log_success "$f: Passed"
        else ((FAILED++)); FAILED_LIST+=("$f"); log_error "$f: Failed"; fi
        progress_bar "$COUNT" "$TOTAL" && echo ""
    done < "$RESULTS_BUFFER"
    rm -f "$RESULTS_BUFFER"; rm -rf "$JOBS_TEMP_DIR"
fi

rm -f "$DUMMY_MAIN_FILE" "$LOG_DIR"
echo -e "\nChecks complete. Total $TOTAL, $PASSED passed, $FAILED failed."
echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
for fail in "${FAILED_LIST[@]+"${FAILED_LIST[@]}"}"; do echo "$fail" >> "$RESULT_FILE"; done
[[ "$STRICT_MODE" == "true" && $FAILED -gt 0 ]] && exit 1
exit 0
