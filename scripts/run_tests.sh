#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
set +e +o pipefail

RES_DIR="results-${PLATFORM}"
RES_FILE="$RES_DIR/test_results.txt"
FAIL_LOG="$RES_DIR/failed_tests.log"

mkdir -p "$RES_DIR"

PASSED=0
FAILED=0
COUNT=0
TOTAL=0
SUITE_TOTAL=0
TOTAL_TIME_NS=0
NAME_WIDTH=75

declare -a FAILS=()

STRICT="${STRICT_MODE:-false}"

CPU=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
JOBS=$(( CPU > 2 ? 2 : CPU ))

C3C=$(get_c3c_path)
ensure_executable "$C3C"

if [[ ! -f "$C3C" ]]; then
    log_error "C3C missing"
    echo "$PLATFORM|0|0|0|0.000|0.000" > "$RES_FILE"
    exit 0
fi

: > "$FAIL_LOG"

format_duration() {
    local start_ns="$1"
    local end_ns elapsed_ns secs millis

    end_ns=$(date +%s%N)
    elapsed_ns=$((end_ns - start_ns))

    secs=$((elapsed_ns / 1000000000))
    millis=$(((elapsed_ns % 1000000000) / 1000000))

    printf "%d.%03d|%d\n" \
        "$secs" \
        "$millis" \
        "$elapsed_ns"
}

print_result() {
    local status="$1"
    local name="$2"
    local duration="$3"

    ((COUNT++))

    printf "[%4d/%4d] %-5s %-*s (%6ss)\n" \
        "$COUNT" \
        "$SUITE_TOTAL" \
        "$status" \
        "$NAME_WIDTH" \
        "$name" \
        "$duration"
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

compile_file() {
    local file="$1"
    local command="$2"
    local init_project="$3"
    local fail_log="$4"

    local status=0
    local output=""
    local start_time
    local duration
    local abs_file
    local temp_dir

    start_time=$(date +%s%N)

    abs_file=$(realpath "$file" 2>/dev/null || echo "$file")
    temp_dir=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3j')

    if [[ "$init_project" == "true" ]]; then
        (
            cd "$temp_dir" &&
            "$C3C" init >/dev/null 2>&1
        )
    fi

    local -a args=("$command" -q --stdlib "$(realpath c3c/lib)")

    case "$command" in
        compile-only)
            args+=(--no-entry)
            ;;
        compile-benchmark)
            args+=(--suppress-run)
            ;;
    esac

    args+=("$abs_file")

    if output=$(
        cd "$temp_dir" &&
        "$C3C" "${args[@]}" 2>&1
    ); then
        status=0
    else
        status=$?
    fi

    rm -rf "$temp_dir"

    local elapsed_ns

    IFS='|' read -r duration elapsed_ns \
        <<< "$(format_duration "$start_time")"
    
    if (( status != 0 )); then
        {
            echo "------------------------------------------------------------"
            echo "$file"
            echo "------------------------------------------------------------"
            printf "%s\n" "$output"
            echo
        } >> "$fail_log"
    fi

    echo "RESULT:$([[ $status -eq 0 ]] && echo PASS || echo FAIL)|$file|$duration|$elapsed_ns"
}

run_compile_suite() {
    local name="$1"
    local directory="$2"
    local command="$3"
    local init_project="$4"

    COUNT=0

    local -a FILES=()

    while IFS= read -r file; do
        FILES+=("$file")
    done < <(collect_files "$directory")

    SUITE_TOTAL=${#FILES[@]}
    TOTAL=$((TOTAL + SUITE_TOTAL))

    if (( SUITE_TOTAL == 0 )); then
        log_warn "No files found for $name"
        return
    fi

    log_info "Running $name ($SUITE_TOTAL files) on $JOBS jobs"

    export -f compile_file format_duration
    export C3C

    local buffer
    buffer=$(mktemp)

    printf "%s\n" "${FILES[@]}" |
        xargs -P "$JOBS" -I{} \
        bash -c 'compile_file "$@"' \
        _ {} "$command" "$init_project" "$FAIL_LOG" \
        > "$buffer"

    while IFS= read -r line; do

        [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*)$ ]] || continue

        local result="${BASH_REMATCH[1]}"
        local file="${BASH_REMATCH[2]}"
        local duration="${BASH_REMATCH[3]}"
        local elapsed_ns="${BASH_REMATCH[4]}"

        TOTAL_TIME_NS=$((TOTAL_TIME_NS + elapsed_ns))
        
        if [[ "$result" == PASS ]]; then
            ((PASSED++))
            print_result PASS "$file" "$duration"
        else
            ((FAILED++))
            FAILS+=("$file")
            print_result FAIL "$file" "$duration"
        fi

    done < "$buffer"

    rm -f "$buffer"
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

    printf "%s\n" "$output"
    echo "::endgroup::"

    duration=$(format_duration "$start_time")
    
    local elapsed_ns
    IFS='|' read -r duration elapsed_ns \
        <<< "$(format_duration "$start_time")"
    
    TOTAL_TIME_NS=$((TOTAL_TIME_NS + elapsed_ns))

    if (( status == 0 )); then
        ((PASSED++))
        print_result PASS "$name" "$duration"
    else
        ((FAILED++))
        FAILS+=("$name")
        print_result FAIL "$name" "$duration"

        {
            echo "------------------------------------------------------------"
            echo "$name"
            echo "------------------------------------------------------------"
            printf "%s\n" "$output"
            echo
        } >> "$FAIL_LOG"
    fi
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
    echo

    printf "Total    : %d\n" "$TOTAL"
    printf "Passed   : %d\n" "$PASSED"
    printf "Failed   : %d\n" "$FAILED"

    echo

    local secs millis
    secs=$((TOTAL_TIME_NS / 1000000000))
    millis=$(((TOTAL_TIME_NS % 1000000000) / 1000000))
    
    printf "Compile Time : %d.%03ds\n" "$secs" "$millis"
    
    if (( TOTAL > 0 )); then
        local avg_ns avg_secs avg_millis
    
        avg_ns=$((TOTAL_TIME_NS / TOTAL))
        avg_secs=$((avg_ns / 1000000000))
        avg_millis=$(((avg_ns % 1000000000) / 1000000))
    
        printf "Average      : %d.%03ds/file\n" \
            "$avg_secs" \
            "$avg_millis"
    fi

    echo "==========================================="
}

write_results() {

    local secs millis
    local avg_secs=0
    local avg_millis=0

    secs=$((TOTAL_TIME_NS / 1000000000))
    millis=$(((TOTAL_TIME_NS % 1000000000) / 1000000))

    if (( TOTAL > 0 )); then
        local avg_ns

        avg_ns=$((TOTAL_TIME_NS / TOTAL))
        avg_secs=$((avg_ns / 1000000000))
        avg_millis=$(((avg_ns % 1000000000) / 1000000))
    fi

    printf "%s|%d|%d|%d|%d.%03d|%d.%03d\n" \
        "$PLATFORM" \
        "$TOTAL" \
        "$PASSED" \
        "$FAILED" \
        "$secs" \
        "$millis" \
        "$avg_secs" \
        "$avg_millis" \
        > "$RES_FILE"

    for f in "${FAILS[@]}"; do
        echo "$f" >> "$RES_FILE"
    done

    if (( FAILED == 0 )); then
        rm -f "$FAIL_LOG"
    fi
}
run_compile_suite \
    "Standard Library" \
    "c3c/lib/std" \
    "compile-only" \
    false

run_compile_suite \
    "Benchmarks" \
    "c3c/benchmarks/stdlib" \
    "compile-benchmark" \
    false

run_compile_suite \
    "Resources" \
    "c3c/resources" \
    "compile-only" \
    true

run_test_suite

print_summary
write_results

[[ "$STRICT" == "true" && $FAILED -gt 0 ]] && exit 1
exit 0
