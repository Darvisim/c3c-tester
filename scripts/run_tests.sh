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

PASSED=0; FAILED=0; COUNT=0; TOTAL=0; FILES=(); FAILED_LIST=()
STRICT_MODE="${STRICT_MODE:-false}"
JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)
C3C=$(get_c3c_path)
ensure_executable "$C3C"

[[ ! -f "$C3C" ]] && { log_error "C3C missing"; echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"; exit 0; }

progress_bar() {
    local c=${1:-0} t=${2:-1} w=40 p=$((c*100/(t>0?t:1)))
    local f=$([[ "$PLATFORM" == "Windows" ]] && echo "#" || printf "\xe2\x96\x88")
    local l=$((p*w/100))
    local b=$(printf "%${l}s" | tr ' ' "$f")$(printf "%$((w-l))s")
    [[ "${GITHUB_ACTIONS:-}" == "true" ]] && printf " [%s] [%3d%%] (%d/%d)\n" "$b" "$p" "$c" "$t" || printf "\r[%s] %3d%% (%d/%d)" "$b" "$p" "$c" "$t"
}

case "$MODE" in
    stdlib)     SEARCH_DIRS=("c3c/lib/std") ;;
    benchmarks) SEARCH_DIRS=("c3c/benchmarks/stdlib") ;;
    test)       SEARCH_DIRS=("c3c/test") ;;
    resources)  SEARCH_DIRS=("c3c/resources") ;;
    fuzz)
        export FUZZ_LIMIT=${FUZZ_LIMIT:-1000}
        "$(dirname "$0")/fuzz.sh"
        status=$?
        echo "$PLATFORM|$MODE|1000|$([ $status -eq 0 ] && echo 1000 || echo 999)|$([ $status -eq 0 ] && echo 0 || echo 1)" > "$RESULT_FILE"
        exit $status
        ;;
    *)          log_error "Unknown mode: $MODE"; exit 1 ;;
esac


for dir in "${SEARCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r -d '' file; do FILES+=("$file"); done < <(find "$dir" -type f \( -name "*.c3" -o -name "*.c3t" -o -name "*.c3i" \) -not -path "*/.*" -print0)
done
TOTAL=${#FILES[@]}

[[ "$TOTAL" -eq 0 ]] && { log_warn "No files found for $MODE"; echo "$PLATFORM|$MODE|0|0|0" > "$RESULT_FILE"; exit 0; }
log_info "Running $MODE checks ($TOTAL files) on $JOBS jobs"

run_one() {
    local file=$1 mode=$2 ldir=$3 start=$(date +%s%N) status=0 out="" inj=0
    local abs_f=$(realpath "$file" 2>/dev/null || echo "$file")
    local abs_d=$(realpath "$DUMMY_MAIN" 2>/dev/null || echo "$DUMMY_MAIN")
    local jdir=$(mktemp -d 2>/dev/null || mktemp -d -t 'c3_job')
    local bin=$(get_bin_name "$file")
    
    local cmd="compile"
    [[ "$mode" == "test" ]] && cmd="compile-test"
    [[ "$mode" == "resources" ]] && { (cd "$jdir" && "$C3C" init >/dev/null 2>&1); }

    local tries=0 max=2 inj=$(is_main_missing "$file" && echo 1 || echo 0)
    while [[ $tries -lt $max ]]; do
        if [[ $inj -eq 1 ]]; then
            out=$(cd "$jdir" && "$C3C" $cmd -o "$bin" "$abs_f" "$abs_d" 2>&1)
        else
            out=$(cd "$jdir" && "$C3C" $cmd -o "$bin" "$abs_f" 2>&1)
        fi
        status=$?
        [[ $status -eq 0 ]] && break
        [[ "$out" == *"The 'main' function"* ]] && [[ $inj -eq 0 ]] && { inj=1; ((tries++)); continue; }
        [[ "$out" == *"redefinition of 'main'"* ]] && [[ $inj -eq 1 ]] && { inj=0; ((tries++)); continue; }
        break
    done
    
    rm -rf "$jdir"
    dur=$(awk "BEGIN {printf \"%.3f\", ($(date +%s%N)-$start)/1000000000}")
    safe=$(echo "$file" | sed 's/[^[:alnum:]]/_/g')
    printf "%s\n" "$out" > "${ldir}/${safe}.log"
    echo "RESULT:$([[ $status -eq 0 ]] && echo "PASS" || echo "FAIL")|$file|$dur|$inj"
}

export -f run_one log_info log_success log_warn log_error get_bin_name is_main_missing
export C3C BLUE GREEN YELLOW RED NC PLATFORM DUMMY_MAIN

RESULTS_BUFFER="results_${PLATFORM}_${MODE}.txt"
printf "%s\n" "${FILES[@]}" | xargs -I{} -P "$JOBS" bash -c 'run_one "$@"' _ {} "$MODE" "$LOG_DIR" > "$RESULTS_BUFFER"

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

rm -f "$RESULTS_BUFFER"; rm -f "$DUMMY_MAIN"; rm -rf "$LOG_DIR"
echo -e "\nComplete. Total $TOTAL, $PASSED passed, $FAILED failed."
echo "$PLATFORM|$MODE|$TOTAL|$PASSED|$FAILED" > "$RESULT_FILE"
for fail in ${FAILED_LIST[@]+"${FAILED_LIST[@]}"}; do echo "$fail" >> "$RESULT_FILE"; done
[[ "$STRICT_MODE" == "true" && $FAILED -gt 0 ]] && exit 1
exit 0
