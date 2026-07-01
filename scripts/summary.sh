#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

log_info "Generating matrix summary..."

: "${GITHUB_STEP_SUMMARY:=/dev/null}"

T_SUM=0
P_SUM=0
F_SUM=0

declare -A DATA
declare -a FAILS=()
declare -a TARGETS=()

while IFS= read -r f; do
    [[ -s "$f" ]] || continue

    read -r header < "$f"

    IFS="|" read -r OS TOT PAS FAL <<< "$header"
    [[ -n "$OS" ]] || continue

    DATA["$OS"]="$PAS/$TOT"

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

{
    echo
    echo "| Platform | Result |"
    echo "| :------- | :----: |"
} >> "$GITHUB_STEP_SUMMARY"

for os in "${TARGETS[@]}"; do
    value="${DATA[$os]:-N/A}"

    if [[ "$value" == "N/A" ]]; then
        echo "| **$os** | - |" >> "$GITHUB_STEP_SUMMARY"
        continue
    fi

    IFS="/" read -r passed total <<< "$value"

    if (( passed == total )); then
        color="brightgreen"
    else
        color="red"
    fi

    badge="${value//\//%2F}"

    echo "| **$os** | ![$value](https://img.shields.io/badge/-${badge}-${color}?style=flat-square) |" \
        >> "$GITHUB_STEP_SUMMARY"
done

{
    echo
    printf "**Total Progress: %d/%d Passes (%d Failures)**\n" \
        "$P_SUM" "$T_SUM" "$F_SUM"
    echo
} >> "$GITHUB_STEP_SUMMARY"

if (( F_SUM == 0 && T_SUM > 0 )); then
    echo "### All Tests Passed! 🥳🎉🍾" >> "$GITHUB_STEP_SUMMARY"
fi

if (( ${#FAILS[@]} > 0 )); then
    {
        echo "### Failure Details"
        echo '```'
        printf "%s\n" "${FAILS[@]}"
        echo '```'
    } >> "$GITHUB_STEP_SUMMARY"
fi

log_success "Matrix generated."
