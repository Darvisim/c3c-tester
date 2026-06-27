#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
set +e +o pipefail

MODE="${1:-stdlib}"
RES_DIR="results-${PLATFORM}-${MODE}"
mkdir -p "$RES_DIR"

RES_FILE="$RES_DIR/test_results.txt"
LOG_DIR="test_logs_${PLATFORM}_${MODE}"
mkdir -p "$LOG_DIR"

DUMMY="$(realpath "$RES_DIR" 2>/dev/null || echo "$RES_DIR")/_dummy.c3"
echo "fn void main() => 0;" > "$DUMMY"
export DUMMY

PASSED=0; FAILED=0; COUNT=0; TOTAL=0; FAILS=()
STRICT="${STRICT_MODE:-false}"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
C3C=$(get_c3c_path)
ensure_executable "$C3C"

[[ ! -f "$C3C" ]] && { log_error "C3C missing"; echo "$PLATFORM|$MODE|0|0|0" > "$RES_FILE"; exit 0; }

progress() {
    local c=${1:-0}; local t=${2:-1}; local w=40
    local p=$((c*100/(t>0?t:1))); local f="#"
    local l=$((p*w/100))
    local b
    b=$(printf "%${l}s" | tr ' ' "$f")$(printf "%$((w-l))s")
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && printf " [%s] [%3d%%] (%d/%d)\n" "$b" "$p" "$c" "$t" || printf "\r[%s] %3d%% (%d/%d)" "$b" "$p" "$c" "$t"
}

run_test_bundle() {
    local n="$1" cmd="$2" d="${3:-.}" status=0 out=""
    local start
    start=$(date +%s%N)
    echo "::group::$n"
    local c3_q
    c3_q=$(printf '%q' "$C3C")
    local r_cmd="${cmd//\$C3C/$c3_q}"
    out=$(cd "$d" && eval "$r_cmd" 2>&1) || status=$?
    if [[ $status -ne 0 ]] && [[ "$out" == *"The 'main' function"* ]]; then
        status=0 && out=$(cd "$d" && eval "$r_cmd $DUMMY" 2>&1) || status=$?
    fi
    printf "%s\n" "$out"; echo "::endgroup::"
    dur=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start)/1000000000}")
    ((COUNT++))
    if [[ $status -eq 0 ]]; then ((PASSED++)); log_success "$n: Passed ($dur s)"
    else ((FAILED++)); FAILS+=("$n"); log_error "$n: Failed ($dur s)"; fi
    progress "$COUNT" "$TOTAL" && echo ""
}

# shellcheck disable=SC2329
compile_file() {
    local f=$1 m=$2 ld=$3 status=0 out="" inj=0
    local start af ad jd bin
    start=$(date +%s%N)
    af=$(realpath "$f" 2>/dev/null || echo "$f")
    ad=$(realpath "$DUMMY" 2>/dev/null || echo "$DUMMY")
    jd=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3j')
    bin=$(get_bin_name "$f")
    local c="compile" && [[ "$m" == "benchmarks" ]] && c="compile-benchmark"
    [[ "$m" == "resources" ]] && { (cd "$jd" && "$C3C" init >/dev/null 2>&1); }
    while :; do
        status=0
        [[ $inj -eq 1 ]] && out=$(cd "$jd" && "$C3C" "$c" -o "$bin" "$af" "$ad" 2>&1) || out=$(cd "$jd" && "$C3C" "$c" -o "$bin" "$af" 2>&1)
        [[ $status -eq 0 ]] && break
        [[ "$out" == *"The 'main' function"* ]] && [[ $inj -eq 0 ]] && { inj=1; continue; }
        break
    done
    rm -rf "$jd"
    dur=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start)/1000000000}")
    printf "%s\n" "$out" > "${ld}/${f//[^[:alnum:]]/_}.log"
    echo "RESULT:$([[ $status -eq 0 ]] && echo "PASS" || echo "FAIL")|$f|$dur|$inj"
}

get_target_directory() {
    case "$1" in
        stdlib)
            echo "c3c/lib/std"
            ;;
        benchmarks)
            echo "c3c/benchmarks/stdlib"
            ;;
        resources)
            echo "c3c/resources"
            ;;
        *)
            return 1
            ;;
    esac
}

collect_files() {
    local base
    base=$(get_target_directory "$1") || return 1

    if [[ ! -d "$base" ]]; then
        log_warn "Target directory '$base' not found."
        return 1
    fi

    find "$base" \
        -type f \
        \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) \
        -not -path "*/.*"
}

run_compile_suite() {
    local mode="$1"

    local base
    base=$(get_target_directory "$mode") || {
        log_error "Unknown mode '$mode'"
        exit 1
    }

    mapfile -t FILES < <(collect_files "$mode")

    TOTAL=${#FILES[@]}

    if [[ "$TOTAL" -eq 0 ]]; then
        log_warn "No files found for $mode"
        echo "$PLATFORM|$mode|0|0|0" > "$RES_FILE"
        return
    fi

    log_info "Running granular $mode ($TOTAL files) on $JOBS jobs"

    export -f compile_file log_info log_success log_warn log_error get_bin_name
    export C3C BLUE GREEN YELLOW RED NC PLATFORM DUMMY

    local buffer="buf_${PLATFORM}_${mode}.txt"

    printf "%s\n" "${FILES[@]}" |
        xargs -I{} -P "$JOBS" \
        bash -c 'compile_file "$@"' _ {} "$mode" "$LOG_DIR" \
        > "$buffer"

    while read -r line; do

        [[ "$line" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*) ]] || continue

        local result="${BASH_REMATCH[1]}"
        local file="${BASH_REMATCH[2]}"
        local duration="${BASH_REMATCH[3]}"

        ((COUNT++))

        echo "::group::$file ($duration s)"
        cat "${LOG_DIR}/${file//[^[:alnum:]]/_}.log" 2>/dev/null
        echo "::endgroup::"

        if [[ "$result" == PASS ]]; then
            ((PASSED++))
            log_success "$file: Passed"
        else
            ((FAILED++))
            FAILS+=("$file")
            log_error "$file: Failed"
        fi

        progress "$COUNT" "$TOTAL"
        echo

    done < "$buffer"

    rm -f "$buffer"
}

run_test_suite() {

    local workspace

    workspace=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3b')

    cp -r "c3c/test" "$workspace/" 2>/dev/null || true

    TOTAL=2

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

case "$MODE" in
    test)
        run_test_suite
        ;;

    stdlib)
        run_compile_suite stdlib
        ;;

    benchmarks)
        run_compile_suite benchmarks
        ;;

    resources)
        run_compile_suite resources
        ;;
esac
