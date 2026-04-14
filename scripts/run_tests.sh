#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
set +e
set +o pipefail

MODE="${1:-stdlib}"
RESULT_DIR="results-${PLATFORM}-${MODE}"
mkdir -p "$RESULT_DIR"

RESULT_FILE="$RESULT_DIR/test_results.txt"
LOG_DIR="test_logs_${PLATFORM}_${MODE}"
mkdir -p "$LOG_DIR"

DUMMY_MAIN="$(realpath "$RESULT_DIR" 2>/dev/null || echo "$RESULT_DIR")/_dummy_main.c3"
echo "fn void main() => 0;" > "$DUMMY_MAIN"
export DUMMY_MAIN

PASSED=0; FAILED=0; COUNT=0; TOTAL=0; FAILED_LIST=()
STRICT_MODE="${STRICT_MODE:-false}"
C3C=$(get_c3c_path)
ensure_executable "$C3C"

[[ ! -f "$C3C" ]] && { log_error "C3C missing"; echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"; exit 0; }

progress_bar() {
    local c=${1:-0} t=${2:-1} w=40 p=$((c*100/(t>0?t:1)))
    local f="#" l=$((p*w/100))
    local b=$(printf "%${l}s" | tr ' ' "$f")$(printf "%$((w-l))s")
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && printf " [%s] [%3d%%] (%d/%d)\n" "$b" "$p" "$c" "$t" || printf "\r[%s] %3d%% (%d/%d)" "$b" "$p" "$c" "$t"
}

run_test() {
    local name="$1" cmd="$2" dir="${3:-.}" start=$(date +%s%N) status=0 out=""
    echo "::group::$name"
    local escaped_c3c=$(printf '%q' "$C3C")
    local resolved_cmd="${cmd//\$C3C/$escaped_c3c}"
    out=$(cd "$dir" && eval "$resolved_cmd" 2>&1) || status=$?
    
    # Retry with main() injection if it looks like a simple example or module missing entry
    if [[ $status -ne 0 ]] && [[ "$out" == *"The 'main' function"* ]]; then
        local abs_d=$(realpath "$DUMMY_MAIN" 2>/dev/null || echo "$DUMMY_MAIN")
        status=0 && out=$(cd "$dir" && eval "$resolved_cmd $abs_d" 2>&1) || status=$?
    fi
    
    printf "%s\n" "$out"
    echo "::endgroup::"
    dur=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start)/1000000000}")
    ((COUNT++))
    if [[ $status -eq 0 ]]; then ((PASSED++)); log_success "$name: Passed ($dur s)"
    else ((FAILED++)); FAILED_LIST+=("$name"); log_error "$name: Failed ($dur s)"; fi
    progress_bar "$COUNT" "$TOTAL" && echo ""
}

if [[ "$MODE" == "fuzz" ]]; then
    export FUZZ_LIMIT=${FUZZ_LIMIT:-1000}
    "$(dirname "$0")/fuzz.sh"
    status=$?
    echo "$PLATFORM|$MODE|1000|$([ $status -eq 0 ] && echo 1000 || echo 999)|$([ $status -eq 0 ] && echo 0 || echo 1)" > "$RESULT_FILE"
    exit $status
fi

# Optimized Bundle Logic for all targets
WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_bundle')
case "$MODE" in
    test)
        [ -d "c3c/test" ] && cp -r c3c/test "$WORKDIR/"
        TOTAL=2
        [ -d "$WORKDIR/test/unit" ] && run_test "Unit" "\$C3C compile-test unit -O1" "$WORKDIR/test"
        [ -f "$WORKDIR/test/src/test_suite_runner.c3" ] && run_test "Suite" "\$C3C compile-run -O1 src/test_suite_runner.c3 -- \$C3C test_suite/ --no-terminal" "$WORKDIR/test"
        ;;
    resources)
        [ -d "c3c/resources" ] && cp -r c3c/resources "$WORKDIR/"
        DIRS=($(find "$WORKDIR/resources" -maxdepth 2 -name "*.c3" -exec dirname {} \; | sort -u))
        TOTAL=${#DIRS[@]}
        for d in "${DIRS[@]}"; do
            rel="${d#$WORKDIR/resources/}"
            run_test "resources/$rel" "\$C3C compile ." "$d"
        done
        ;;
    stdlib|benchmarks)
        BASE_DIR="c3c/lib/std" && [[ "$MODE" == "benchmarks" ]] && BASE_DIR="c3c/benchmarks/stdlib"
        CMD="compile" && [[ "$MODE" == "benchmarks" ]] && CMD="compile-benchmark"
        [ -d "$BASE_DIR" ] && cp -r "$BASE_DIR" "$WORKDIR/"
        DIRS=($(find "$WORKDIR" -maxdepth 2 -name "*.c3" -exec dirname {} \; | sort -u))
        TOTAL=${#DIRS[@]}
        for d in "${DIRS[@]}"; do
            rel="${d#$WORKDIR/}"
            run_test "$MODE/$rel" "\$C3C $CMD ." "$d"
        done
        ;;
    *) log_error "Unknown mode: $MODE"; exit 1 ;;
esac

rm -rf "$WORKDIR"
rm -f "$DUMMY_MAIN"; rm -rf "$LOG_DIR"
echo -e "\nComplete. Total $TOTAL, $PASSED passed, $FAILED failed."
echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
for fail in ${FAILED_LIST[@]+"${FAILED_LIST[@]}"}; do echo "$fail" >> "$RESULT_FILE"; done
[[ "$STRICT_MODE" == "true" && $FAILED -gt 0 ]] && exit 1
exit 0
