#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
set +e +o pipefail

RES_DIR="results-${PLATFORM}"
mkdir -p "$RES_DIR"

RES_FILE="$RES_DIR/test_results.txt"
LOG_DIR="test_logs_${PLATFORM}"
mkdir -p "$LOG_DIR"

PASSED=0
FAILED=0
COUNT=0
TOTAL=0
SUITE_TOTAL=0

declare -a FAILS=()
TOTAL_TIME=0

STRICT="${STRICT_MODE:-false}"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
C3C=$(get_c3c_path)
ensure_executable "$C3C"

[[ ! -f "$C3C" ]] && { log_error "C3C missing"; echo "$PLATFORM|0|0|0" > "$RES_FILE"; exit 0; }

print_result() {
    local status="$1"
    local name="$2"
    local duration="$3"

    ((COUNT++))

    printf "[%4d/%4d] %-5s %-50s (%6ss)\n" \
        "$COUNT" \
        "$SUITE_TOTAL" \
        "$status" \
        "$name" \
        "$duration"
}

create_dummy_main() {
    DUMMY_FILE="${RES_DIR}/_dummy.c3"
    printf "fn void main() => 0;\n" > "$DUMMY_FILE"
    export DUMMY_FILE
}

cleanup() {
    rm -f "$DUMMY_FILE"
    rm -rf "$LOG_DIR"
}

run_test_bundle() {
    local name="$1"
    local command="$2"
    local working_dir="${3:-.}"

    local status=0
    local output=""
    local start_time
    local duration

    start_time=$(date +%s%N)

    echo "::group::$name"

    local quoted_c3
    quoted_c3=$(printf '%q' "$C3C")

    local resolved_command="${command//\$C3C/$quoted_c3}"

    output=$(cd "$working_dir" && eval "$resolved_command" 2>&1) || status=$?

    if [[ $status -ne 0 && "$output" == *"The 'main' function"* ]]; then
        status=0
        output=$(cd "$working_dir" && eval "$resolved_command $DUMMY_FILE" 2>&1) || status=$?
    fi

    printf "%s\n" "$output"
    echo "::endgroup::"

    duration=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start_time)/1000000000}")

    if [[ $status -eq 0 ]]; then
        ((PASSED++))
        print_result PASS "$name" "$duration"
    else
        ((FAILED++))
        FAILS+=("$name")
        print_result FAIL "$name" "$duration"
    fi

    TOTAL_TIME=$(awk "BEGIN {printf \"%.3f\", $TOTAL_TIME + $duration}")
}

# shellcheck disable=SC2329
compile_file() {
    local file="$1"
    local command="$2"
    local init_project="$3"
    local log_dir="$4"

    local status=0
    local output=""

    local start_time
    local duration
    local abs_file
    local temp_dir
    local binary_name

    start_time=$(date +%s%N)

    abs_file=$(realpath "$file" 2>/dev/null || echo "$file")
    temp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3j')
    binary_name=$(get_bin_name "$file")

    if [[ "$init_project" == "true" ]]; then
        (cd "$temp_dir" && "$C3C" init >/dev/null 2>&1)
    fi

    if output=$(cd "$temp_dir" && \
        "$C3C" "$command" -o "$binary_name" "$abs_file" 2>&1); then
        status=0
    else
        status=$?
    fi

    rm -rf "$temp_dir"

    duration=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start_time)/1000000000}")

    printf "%s\n" "$output" > "${log_dir}/${file//[^[:alnum:]]/_}.log"

    echo "RESULT:$([[ $status -eq 0 ]] && echo PASS || echo FAIL)|$file|$duration"
}

collect_files() {
    local directory="$1"

    if [[ ! -d "$directory" ]]; then
        log_warn "Target directory '$directory' not found."
        return 1
    fi

    find "$directory" \
        -type f \
        \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) \
        -not -path "*/.*"
}

run_compile_suite() {
    local name="$1"
    local directory="$2"
    local command="$3"
    local init_project="$4"

    COUNT=0

    mapfile -t FILES < <(collect_files "$directory")

    SUITE_TOTAL=${#FILES[@]}
    TOTAL=$((TOTAL + SUITE_TOTAL))

    if (( SUITE_TOTAL == 0 )); then
        log_warn "No files found for $name"
        return
    fi

    log_info "Running $name ($SUITE_TOTAL files) on $JOBS jobs"

    export -f compile_file get_bin_name
    export C3C DUMMY_FILE

    local buffer
    buffer=$(mktemp)

    printf "%s\n" "${FILES[@]}" |
        xargs -P "$JOBS" -I{} \
        bash -c 'compile_file "$@"' \
        _ {} "$command" "$init_project" "$LOG_DIR" \
        > "$buffer"

    while read -r line; do

        [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)$ ]] || continue
    
        local result="${BASH_REMATCH[1]}"
        local file="${BASH_REMATCH[2]}"
        local duration="${BASH_REMATCH[3]}"

        if [[ "$result" == PASS ]]; then
            ((PASSED++))
            print_result PASS "$file" "$duration"
        else
            ((FAILED++))
            FAILS+=("$file")
            print_result FAIL "$file" "$duration"
        fi

        TOTAL_TIME=$(awk "BEGIN {printf \"%.3f\", $TOTAL_TIME + $duration}")

    done < "$buffer"

    rm -f "$buffer"
}

run_test_suite() {

    local workspace

    workspace=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3b')

    cp -r "c3c/test" "$workspace/" 2>/dev/null || true

    COUNT=0
    SUITE_TOTAL=2
    TOTAL=$((TOTAL + SUITE_TOTAL))

    if [[ -d "$workspace/test/unit" ]]; then
        run_test_bundle \
            "Unit" \
            "\$C3C compile-test unit -O1" \
            "$workspace/test"
    fi

    if [[ -f "$workspace/test/src/test_suite_runner.c3" ]]; then
        run_test_bundle \
            "Suite" \
            "\$C3C compile-run -O1 src/test_suite_runner.c3 -- \$C3C test_suite/ --no-terminal" \
            "$workspace/test"
    fi

    rm -rf "$workspace"
}

print_summary() {
    echo

    echo "==========================================="
    echo "            C3C Tester Summary"
    echo "==========================================="

    printf "Platform : %s\n" "$PLATFORM"
    printf "\n"

    printf "Total    : %d\n" "$TOTAL"
    printf "Passed   : %d\n" "$PASSED"
    printf "Failed   : %d\n" "$FAILED"

    echo

    printf "Compile Time : %.3fs\n" "$TOTAL_TIME"

    if (( TOTAL > 0 )); then
        AVG=$(awk "BEGIN {printf \"%.3f\", $TOTAL_TIME/$TOTAL}")
        printf "Average      : %.3fs/file\n" "$AVG"
    fi

    echo "==========================================="
}

write_results() {
    echo "$PLATFORM|$TOTAL|$PASSED|$FAILED" > "$RES_FILE"
    
    for f in "${FAILS[@]}"; do
        echo "$f" >> "$RES_FILE"
    done
}

create_dummy_main
trap cleanup EXIT

run_compile_suite \
    "Standard Library" \
    "c3c/lib/std" \
    "compile" \
    false

run_compile_suite \
    "Benchmarks" \
    "c3c/benchmarks/stdlib" \
    "compile-benchmark" \
    false

run_compile_suite \
    "Resources" \
    "c3c/resources" \
    "compile" \
    true

run_test_suite

print_summary
write_results

[[ "$STRICT" == "true" && $FAILED -gt 0 ]] && exit 1
exit 0
