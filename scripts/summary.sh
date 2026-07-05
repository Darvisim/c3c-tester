#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

log_info "Generating matrix summary..."

: "${GITHUB_STEP_SUMMARY:=/dev/null}"

T_SUM=0
P_SUM=0
F_SUM=0

declare -a TARGETS=()
declare -a SUITES=(
    "Standard Library"
    "Benchmarks"
    "Resources"
)

declare -A TOTALS
declare -A PASSEDS
declare -A FAILEDS
declare -A TIMES
declare -A AVERAGES

declare -A SUITE_TOTALS
declare -A SUITE_PASSED
declare -A SUITE_FAILED
declare -A SUITE_FAIL_LIST

while IFS= read -r file; do
    [[ -s "$file" ]] || continue

    current_os=""

    while IFS='|' read -r type a b c d e f; do
        case "$type" in

        HEADER)
            current_os="$a"

            TOTALS["$current_os"]="$b"
            PASSEDS["$current_os"]="$c"
            FAILEDS["$current_os"]="$d"
            TIMES["$current_os"]="$e"
            AVERAGES["$current_os"]="$f"

            ((T_SUM += b))
            ((P_SUM += c))
            ((F_SUM += d))

            TARGETS+=("$current_os")
            ;;

        SUITE)
            SUITE_TOTALS["$current_os|$a"]="$b"
            SUITE_PASSED["$current_os|$a"]="$c"
            SUITE_FAILED["$current_os|$a"]="$d"
            ;;

        FAIL)
            SUITE_FAIL_LIST["$current_os|$a"]+="$b"$'\n'
            ;;

        esac
    done < "$file"

done < <(find results -name test_results.txt 2>/dev/null)

IFS=$'\n'
TARGETS=($(printf "%s\n" "${TARGETS[@]}" | sort -u))
unset IFS

for os in "${TARGETS[@]}"; do

{
echo "## $os"
echo
echo '```text'
echo "==========================================="
echo "            C3C Tester Summary"
echo "==========================================="
echo

printf "Platform     : %s\n" "$os"
printf "Compile Time : %ss\n" "${TIMES[$os]}"
printf "Average      : %ss/file\n" "${AVERAGES[$os]}"
echo

for suite in "${SUITES[@]}"; do
    total="${SUITE_TOTALS[$os|$suite]}"
    [[ -z "$total" ]] && continue

    passed="${SUITE_PASSED[$os|$suite]}"
    failed="${SUITE_FAILED[$os|$suite]}"

    if (( failed == 0 )); then
        printf "✓ %-20s %4d / %-4d passed\n" \
            "$suite" \
            "$passed" \
            "$total"
    else
        printf "✗ %-20s %4d / %-4d passed\n" \
            "$suite" \
            "$passed" \
            "$total"
    fi
done

echo
echo "-------------------------------------------"

printf "Total  : %s\n" "${TOTALS[$os]}"
printf "Passed : %s\n" "${PASSEDS[$os]}"
printf "Failed : %s\n" "${FAILEDS[$os]}"

echo "==========================================="
echo '```'
echo

for suite in "${SUITES[@]}"; do
    failed="${SUITE_FAILED[$os|$suite]}"
    (( failed > 0 )) || continue

    echo "<details>"
    echo "<summary>$suite ($failed failures)</summary>"
    echo
    echo '```text'
    printf "%s" "${SUITE_FAIL_LIST[$os|$suite]}"
    echo '```'
    echo "</details>"
    echo
done

} >> "$GITHUB_STEP_SUMMARY"

done

{
echo "## Overall"
echo
echo '```text'
echo "==========================================="
echo "          Overall Test Summary"
echo "==========================================="

printf "Total Tests : %d\n" "$T_SUM"
printf "Passed      : %d\n" "$P_SUM"
printf "Failed      : %d\n" "$F_SUM"

echo "==========================================="
echo '```'

if (( F_SUM == 0 && T_SUM > 0 )); then
    echo
    echo "### 🎉 All Tests Passed!"
fi

} >> "$GITHUB_STEP_SUMMARY"

log_success "Matrix generated."
