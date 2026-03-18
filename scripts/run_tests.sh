#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

set +e
set +o pipefail

MODE="${1:-compiler}"
RESULT_DIR="results-${PLATFORM}-${MODE}"
mkdir -p "$RESULT_DIR"

RESULT_FILE="$RESULT_DIR/test_results.txt"
LOG_DIR="test_logs_${PLATFORM}_${MODE}"
mkdir -p "$LOG_DIR"

DUMMY_MAIN_FILE="$(abspath "$RESULT_DIR")/_dummy_main.c3"
echo "fn void main() => 0;" > "$DUMMY_MAIN_FILE"
export DUMMY_MAIN_FILE

# Helpers
has_dir() { [[ -d "$1" ]]; }
add() { TOTAL=$((TOTAL + $1)); }
sanitize() { sed 's/[^[:alnum:]]/_/g'; }

PASSED=0
FAILED=0
COUNT=0
TOTAL=0
FILES=()
FAILED_LIST=()
EXAMPLES=()

STRICT_MODE="${STRICT_MODE:-false}"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)

C3C=$(get_c3c_path)
ensure_executable "$C3C"

if [[ ! -f "$C3C" ]]; then
    log_warn "C3 Compiler not found at: $C3C. Skipping tests."
    echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"
    exit 0
fi

progress_bar() {
    local current=$1 total=$2 width=40
    local percent=$(( current * 100 / (total > 0 ? total : 1) ))
    local full_char=$(printf "\xe2\x96\x88")
    local filled=$((percent * width / 100))
    local prefix=$([[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "" || echo "\r")

    printf "%s[" "$prefix"
    for ((i=0;i<filled;i++)); do printf "%s" "$full_char"; done
    for ((i=filled;i<width;i++)); do printf " "; done
    printf "] %3d%% (%d/%d)%s" "$percent" "$current" "$total" \
        "$([[ "${GITHUB_ACTIONS:-}" == "true" ]] && echo "\n")"
}

# -------------------------
# Integration Mode
# -------------------------
if [[ "$MODE" == "integration" ]]; then
    WORKDIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_int_tests')
    log_info "Integration mode: using workspace $WORKDIR"

    has_dir "c3c/resources" && cp -r c3c/resources "$WORKDIR/"
    has_dir "c3c/test" && cp -r c3c/test "$WORKDIR/"

    TOTAL=2

    if has_dir "$WORKDIR/resources/examples"; then
        EX_COUNT=$(find "$WORKDIR/resources/examples" -maxdepth 2 -name "*.c3" \
            -not -path "*/staticlib-test/*" \
            -not -path "*/dynlib-test/*" \
            -not -path "*/raylib/*" | wc -l)
        add "$EX_COUNT"
        [[ "$PLATFORM" == "Linux" ]] && add 2
        add 1
    fi

    has_dir "$WORKDIR/resources/testfragments" && add 1

    run_int_test() {
        local name="$1" cmd="$2" dir="${3:-.}"
        local start=$(date +%s%N) status=0

        echo "::group::$name"
        local resolved="${cmd//\$C3C/$(printf '%q' "$C3C")}"

        local output
        output=$(cd "$dir" && eval "$resolved" 2>&1) || status=$?

        case "$output" in
            *"main function for the executable could not found"*)
                local retry="$resolved $(abspath "$DUMMY_MAIN_FILE")"
                output=$(cd "$dir" && eval "$retry" 2>&1) || status=$?
                ;;
        esac

        printf "%s\n" "$output"
        echo "::endgroup::"

        local dur=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start)/1000000000}")
        COUNT=$((COUNT + 1))

        if [[ $status -eq 0 ]]; then
            PASSED=$((PASSED + 1))
            log_success "$name: Passed ($dur s)"
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("$name")
            log_error "$name: Failed ($dur s)"
        fi

        progress_bar "$COUNT" "$TOTAL"
        echo ""
    }

    run_int_test "init" "\$C3C init-lib mylib && \$C3C init myproject" "$WORKDIR"

    rm -rf "$WORKDIR"

# -------------------------
# File-based Mode
# -------------------------
else
    [[ "$MODE" == "compiler" ]] && SEARCH_DIRS=("c3c/lib/std" "c3c/benchmarks/stdlib")
    [[ "$MODE" == "vendor" ]] && SEARCH_DIRS=("vendor/libraries")

    for dir in "${SEARCH_DIRS[@]}"; do
        has_dir "$dir" || continue
        while IFS= read -r -d '' f; do FILES+=("$f"); done < <(
            find "$dir" -type f \
            -not -path "*/testfragments/*" \
            -not -path "*/examples/*" \
            \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) -print0
        )
    done

    IFS=$'\n' FILES=($(printf "%s\n" "${FILES[@]}" | sort)); unset IFS
    TOTAL=${#FILES[@]}

    log_info "Running $TOTAL files using $JOBS jobs"

    compile_one() {
        local file="$1" log_dir="$2"
        local abs_file=$(abspath "$file")
        local job_dir="$JOBS_TEMP_DIR/$(echo "$file" | sanitize)"
        mkdir -p "$job_dir"

        local bin="${file##*/}"; bin="${bin%.*}$EXE_EXT"

        local output status=0
        output=$(cd "$job_dir" && "$C3C" compile -o "$bin" "$abs_file" 2>&1) || status=$?

        printf "%s\n" "$output" > "$log_dir/$(echo "$file" | sanitize).log"

        echo "RESULT:$([[ $status -eq 0 ]] && echo PASS || echo FAIL)|$file"
        rm -rf "$job_dir"
    }

    export -f compile_one sanitize abspath
    export C3C EXE_EXT JOBS_TEMP_DIR

    JOBS_TEMP_DIR=$(mktemp -d)
    RESULTS_BUFFER="results_buffer.txt"

    printf "%s\n" "${FILES[@]}" | xargs -I{} -P "$JOBS" bash -c 'compile_one "$@"' _ {} "$LOG_DIR" > "$RESULTS_BUFFER"

    while read -r line; do
        [[ "$line" =~ RESULT:(PASS|FAIL)\|(.*) ]] || continue
        res="${BASH_REMATCH[1]}" file="${BASH_REMATCH[2]}"

        COUNT=$((COUNT + 1))
        safe=$(echo "$file" | sanitize)

        echo "::group::$file"
        cat "$LOG_DIR/$safe.log"
        echo "::endgroup::"

        if [[ "$res" == "PASS" ]]; then
            PASSED=$((PASSED + 1))
        else
            FAILED=$((FAILED + 1))
            FAILED_LIST+=("$file")
        fi

        progress_bar "$COUNT" "$TOTAL"
        echo ""
    done

    rm -rf "$JOBS_TEMP_DIR" "$RESULTS_BUFFER"
fi

rm -f "$DUMMY_MAIN_FILE"
rm -rf "$LOG_DIR"

echo -e "\nChecks complete. Total $TOTAL, $PASSED passed, $FAILED failed."

echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
printf "%s\n" "${FAILED_LIST[@]}" >> "$RESULT_FILE"

[[ "$STRICT_MODE" == "true" && $FAILED -gt 0 ]] && exit 1
exit 0