#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

log_info "Generating matrix summary..."

: "${GITHUB_STEP_SUMMARY:=/dev/null}"

T_SUM=0
P_SUM=0
F_SUM=0

declare -A TOTALS
declare -A PASSEDS
declare -A FAILEDS
declare -A TIMES
declare -A AVERAGES
declare -a FAILS=()
declare -a TARGETS=()

while IFS= read -r f; do
    [[ -s "$f" ]] || continue

    read -r header < "$f"

    IFS="|" read -r OS TOT PAS FAL TIME AVG <<< "$header"
    [[ -n "$OS" ]] || continue

    TOTALS["$OS"]="$TOT"
    PASSEDS["$OS"]="$PAS"
    FAILEDS["$OS"]="$FAL"
    TIMES["$OS"]="$TIME"
    AVERAGES["$OS"]="$AVG"

    if [[ ! " ${TARGETS[*]} " =~ " ${OS} " ]]; then
        TARGETS+=("$OS")
    fi

    ((T_SUM += TOT, P_SUM += PAS, F_SUM += FAL))

    while IFS= read -r fail; do
        [[ -n "$fail" ]] && FAILS+=("[$OS] $fail")
    done < <(tail -n +2 "$f")

done < <(find results -name "test_results.txt" 2>/dev/null)

IFS=$'\n'
TARGETS=($(printf "%s\n" "${TARGETS[@]}" | sort))
unset IFS

echo >> "$GITHUB_STEP_SUMMARY"

for os in "${TARGETS[@]}"; do
    total="${TOTALS[$os]}"
    passed="${PASSEDS[$os]}"
    failed="${FAILEDS[$os]}"
    time="${TIMES[$os]}"
    avg="${AVERAGES[$os]}"

    {
        echo "## $os"
        echo '```text'
        echo "==========================================="
        echo "            C3C Tester Summary"
        echo "==========================================="
        printf "Platform : %s\n" "$os"
        echo
        printf "Total    : %d\n" "$total"
        printf "Passed   : %d\n" "$passed"
        printf "Failed   : %d\n" "$failed"
        echo
        printf "Compile Time : %ss\n" "$time"
        printf "Average      : %ss/file\n" "$avg"
        echo "==========================================="
        echo '```'
        echo
    } >> "$GITHUB_STEP_SUMMARY"
done

{
    echo "## Overall"
    echo '```text'
    echo "==========================================="
    echo "          Overall Test Summary"
    echo "==========================================="
    printf "Total Tests : %d\n" "$T_SUM"
    printf "Passed      : %d\n" "$P_SUM"
    printf "Failed      : %d\n" "$F_SUM"
    echo "==========================================="
    echo '```'
    echo
} >> "$GITHUB_STEP_SUMMARY"

if (( F_SUM == 0 && T_SUM > 0 )); then
    echo "### All Tests Passed! 🥳🎉🍾" >> "$GITHUB_STEP_SUMMARY"
fi

if (( ${#FAILS[@]} > 0 )); then
    {
        echo
        echo "### Failure Details"
        echo '```'
        printf "%s\n" "${FAILS[@]}"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi

log_success "Matrix generated."
