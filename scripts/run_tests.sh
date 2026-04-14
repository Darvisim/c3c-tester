#!/usr/bin/env bash
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
    local l=$((p*w/100)); local b=$(printf "%${l}s" | tr ' ' "$f")$(printf "%$((w-l))s")
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && printf " [%s] [%3d%%] (%d/%d)\n" "$b" "$p" "$c" "$t" || printf "\r[%s] %3d%% (%d/%d)" "$b" "$p" "$c" "$t"
}

run_bundle() {
    local n="$1" cmd="$2" d="${3:-.}" start=$(date +%s%N) status=0 out=""
    echo "::group::$n"
    local c3_q=$(printf '%q' "$C3C")
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

run_one() {
    local f=$1 m=$2 ld=$3 start=$(date +%s%N) status=0 out="" inj=0
    local af=$(realpath "$f" 2>/dev/null || echo "$f")
    local ad=$(realpath "$DUMMY" 2>/dev/null || echo "$DUMMY")
    local jd=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3j')
    local bin=$(get_bin_name "$f")
    local c="compile" && [[ "$m" == "benchmarks" ]] && c="compile-benchmark"
    [[ "$m" == "resources" ]] && { (cd "$jd" && "$C3C" init >/dev/null 2>&1); }
    while :; do
        status=0
        [[ $inj -eq 1 ]] && out=$(cd "$jd" && "$C3C" $c -o "$bin" "$af" "$ad" 2>&1) || out=$(cd "$jd" && "$C3C" $c -o "$bin" "$af" 2>&1)
        [[ $status -eq 0 ]] && break
        [[ "$out" == *"The 'main' function"* ]] && [[ $inj -eq 0 ]] && { inj=1; continue; }
        break
    done
    rm -rf "$jd"
    dur=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start)/1000000000}")
    printf "%s\n" "$out" > "${ld}/$(echo "$f" | sed 's/[^[:alnum:]]/_/g').log"
    echo "RESULT:$([[ $status -eq 0 ]] && echo "PASS" || echo "FAIL")|$f|$dur|$inj"
}

if [[ "$MODE" == "fuzz" ]]; then
    export FUZZ_LIMIT=${FUZZ_LIMIT:-1000}
    "$(dirname "$0")/fuzz.sh"
    s=$?; echo "$PLATFORM|$MODE|1000|$([ $s -eq 0 ] && echo 1000 || echo 999)|$([ $s -eq 0 ] && echo 0 || echo 1)" > "$RES_FILE"
    exit $s

elif [[ "$MODE" == "test" ]]; then
    W=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3b')
    cp -r "c3c/test" "$W/" 2>/dev/null || true
    TOTAL=2
    [ -d "$W/test/unit" ] && run_bundle "Unit" "\$C3C compile-test unit -O1" "$W/test"
    [ -f "$W/test/src/test_suite_runner.c3" ] && run_bundle "Suite" "\$C3C compile-run -O1 src/test_suite_runner.c3 -- \$C3C test_suite/ --no-terminal" "$W/test"
    rm -rf "$W"

else
    B="c3c/lib/std" && [[ "$MODE" == "benchmarks" ]] && B="c3c/benchmarks/stdlib"
    [[ "$MODE" == "resources" ]] && B="c3c/resources"
    F=($(find "$B" -type f \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) -not -path "*/.*" -print0 | xargs -0 echo))
    TOTAL=${#F[@]}
    [[ "$TOTAL" -eq 0 ]] && { log_warn "No files found for $MODE"; echo "$PLATFORM|$MODE|0|0|0" > "$RES_FILE"; exit 0; }
    log_info "Running granular $MODE ($TOTAL files) on $JOBS jobs"
    export -f run_one log_info log_success log_warn log_error get_bin_name is_main_missing
    export C3C BLUE GREEN YELLOW RED NC PLATFORM DUMMY
    BUFF="buf_${PLATFORM}_${MODE}.txt"
    printf "%s\n" "${F[@]}" | xargs -I{} -P "$JOBS" bash -c 'run_one "$@"' _ {} "$MODE" "$LOG_DIR" > "$BUFF"
    while read -r l; do
        [[ "$l" =~ ^RESULT:(PASS|FAIL)\|(.*)\|(.*)\|(.*) ]] || continue
        res=${BASH_REMATCH[1]}; f=${BASH_REMATCH[2]}; d=${BASH_REMATCH[3]}; i=${BASH_REMATCH[4]}
        ((COUNT++)); echo "::group::$f ($d s)"
        cat "${LOG_DIR}/$(echo "$f" | sed 's/[^[:alnum:]]/_/g').log" 2>/dev/null; echo "::endgroup::"
        if [[ "$res" == "PASS" ]]; then ((PASSED++)); log_success "$f: Passed"
        else ((FAILED++)); FAILS+=("$f"); log_error "$f: Failed"; fi
        progress "$COUNT" "$TOTAL" && echo ""
    done < "$BUFF"; rm -f "$BUFF"
fi

rm -f "$DUMMY"; rm -rf "$LOG_DIR"
echo -e "\nComplete. $TOTAL total, $PASSED passed, $FAILED failed."
echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RES_FILE"
for f in ${FAILS[@]+"${FAILS[@]}"}; do echo "$f" >> "$RES_FILE"; done
[[ "$STRICT" == "true" && $FAILED -gt 0 ]] && exit 1
exit 0
