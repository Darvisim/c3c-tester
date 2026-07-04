#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

log_info "Generating matrix summary..."

: "${GITHUB_STEP_SUMMARY:=/dev/null}"

T_SUM=0
P_SUM=0
F_SUM=0

declare -a TARGETS=()

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

    CURRENT_OS=""

    while IFS='|' read -r TYPE A B C D E F; do
        case "$TYPE" in

        HEADER)
            CURRENT_OS="$A"

            TOTALS["$CURRENT_OS"]="$B"
            PASSEDS["$CURRENT_OS"]="$C"
            FAILEDS["$CURRENT_OS"]="$D"
            TIMES["$CURRENT_OS"]="$E"
            AVERAGES["$CURRENT_OS"]="$F"

            ((T_SUM += B))
            ((P_SUM += C))
            ((F_SUM += D))

            TARGETS+=("$CURRENT_OS")
            ;;

        SUITE)
            SUITE_TOTALS["$CURRENT_OS|$A"]="$B"
            SUITE_PASSED["$CURRENT_OS|$A"]="$C"
            SUITE_FAILED["$CURRENT_OS|$A"]="$D"
            ;;

        FAIL)
            SUITE_FAIL_LIST["$CURRENT_OS|$A"]+="$B"$'\n'
            ;;

        esac
    done < "$file"

done < <(find results -name test_results.txt)

IFS=$'\n'
TARGETS=($(printf "%s\n" "${TARGETS[@]}" | sort -u))
unset IFS

for os in "${TARGETS[@]}"; do

{
echo "# $os"
echo

echo "==========================================="
echo "            C3C Tester Summary"
echo "==========================================="
echo

printf "Platform     : %s\n" "$os"
printf "Compile Time : %ss\n" "${TIMES[$os]}"
printf "Average      : %ss/file\n" "${AVERAGES[$os]}"
echo

for suite in \
    "Standard Library" \
    "Benchmarks" \
    "Resources" \
    "Unit Tests" \
    "Test Suite"
do

    total="${SUITE_TOTALS[$os|$suite]}"
    passed="${SUITE_PASSED[$os|$suite]}"
    failed="${SUITE_FAILED[$os|$suite]}"

    [[ -z "$total" ]] && continue

    if (( failed == 0 )); then
        echo "✓ $suite"
    else
        echo "✗ $suite"
    fi

    echo "-------------------------------------------"
    echo "$passed / $total passed"

    if (( failed > 0 )); then

        echo
        echo "<details>"
        echo "<summary>$failed failed files</summary>"
        echo

        printf "%s" "${SUITE_FAIL_LIST[$os|$suite]}"

        echo
        echo "</details>"

    fi

    echo
done

echo "==========================================="
echo "Overall"
echo "==========================================="
echo

printf "Total  : %s\n" "${TOTALS[$os]}"
printf "Passed : %s\n" "${PASSEDS[$os]}"
printf "Failed : %s\n" "${FAILEDS[$os]}"

echo
echo

} >> "$GITHUB_STEP_SUMMARY"

done

{
echo "# Overall"
echo

printf "Total Tests : %d\n" "$T_SUM"
printf "Passed      : %d\n" "$P_SUM"
printf "Failed      : %d\n" "$F_SUM"

} >> "$GITHUB_STEP_SUMMARY"

if ((F_SUM==0)); then
    echo >> "$GITHUB_STEP_SUMMARY"
    echo "### 🎉 All Tests Passed!" >> "$GITHUB_STEP_SUMMARY"
fi

log_success "Matrix generated."
