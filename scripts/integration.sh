#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

set -e

C3C=$(get_c3c_path)
ensure_executable "$C3C"

RESULT_DIR="results-${PLATFORM}-integration"
mkdir -p "$RESULT_DIR"
RESULT_FILE="$RESULT_DIR/test_results.txt"

PASSED=0
FAILED=0
TOTAL=0

run_test() {
    local name="$1"
    local cmd="$2"
    local dir="${3:-.}"
    
    TOTAL=$((TOTAL + 1))
    log_info "Running Integration Test: $name"
    
    local start=$(date +%s%N)
    local status=0
    
    echo "::group::$name"
    (cd "$dir" && eval "$cmd") || status=$?
    echo "::endgroup::"
    
    local end=$(date +%s%N)
    local duration=$(awk "BEGIN {printf \"%.3f\", ($end-$start)/1000000000}")
    
    if [[ $status -eq 0 ]]; then
        PASSED=$((PASSED + 1))
        log_success "$name: Passed (${duration}s)"
    else
        FAILED=$((FAILED + 1))
        log_error "$name: Failed (${duration}s)"
        echo "FAIL: $name" >> "$RESULT_FILE.failures"
    fi
}

# --- Preparation ---
WORK_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_int_tests')
log_info "Using workspace: $WORK_DIR"

cleanup() {
    rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Copy resources if they exist
if [ -d "c3c/resources" ]; then
    cp -r c3c/resources "$WORK_DIR/resources"
fi

# --- Integration Scenarios ---

# 1. CLI Basic Tests
run_test "CLI: init" "$C3C init-lib mylib && $C3C init myproject" "$WORK_DIR"

# 2. WASM Compilation
if [ -d "$WORK_DIR/resources/testfragments" ]; then
    run_test "WASM: Compile Check" "$C3C compile --target wasm32 -g0 --no-entry -Os wasm4.c3" "$WORK_DIR/resources/testfragments"
fi

# 3. Static/Dynamic Library Tests (Platform specific)
if [ -d "$WORK_DIR/resources/examples/staticlib-test" ]; then
    if [[ "$PLATFORM" == "Windows" ]]; then
        run_test "Static Lib: Build & Run" "$C3C -vv static-lib add.c3 && $C3C -vv compile-run test.c3 -l ./add.lib" "$WORK_DIR/resources/examples/staticlib-test"
    else
        run_test "Static Lib: Build & Run" "$C3C -vv static-lib add.c3 -o libadd && $C3C -vv compile-run test.c3 -L . -l add" "$WORK_DIR/resources/examples/staticlib-test"
    fi
fi

# 4. Project Tests (c3c run)
if [ -d "$WORK_DIR/resources/testproject" ]; then
    run_test "Project: run" "$C3C run -vv --trust=full" "$WORK_DIR/resources/testproject"
fi

# 5. Vendor Fetch (Smoke test)
run_test "CLI: vendor-fetch" "$C3C vendor-fetch raylib" "$WORK_DIR"

# --- Finalize ---
echo -e "\nIntegration tests complete. $PASSED passed, $FAILED failed."
echo "$PLATFORM|integration|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
if [ -f "$RESULT_FILE.failures" ]; then
    cat "$RESULT_FILE.failures" >> "$RESULT_FILE"
    rm "$RESULT_FILE.failures"
fi
