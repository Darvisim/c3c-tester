#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"
log_info "Generating matrix summary..."
[ -z "${GITHUB_STEP_SUMMARY:-}" ] && GITHUB_STEP_SUMMARY="/dev/null"

T_SUM=0; P_SUM=0; F_SUM=0;
declare -A DATA
declare -a FAILS=()
declare -a OSS=()

while IFS= read -r f; do
    [[ -s "$f" ]] || continue
    read -r h < "$f"
    
    IFS="|" read -r OS TOT PAS FAL <<< "$h"
    [[ -n "$OS" ]] || continue
    
    DATA["$OS"]="$PAS/$TOT"
    [[ ! " ${OSS[*]} " == *" ${OS} "* ]] && OSS+=("$OS")
    
    ((T_SUM+=${TOT:-0}, P_SUM+=${PAS:-0}, F_SUM+=${FAL:-0})) || true
    while read -r fail; do
        FAILS+=("[$OS] $fail")
    done < <(tail -n +2 "$f")
done < <(find results -name "test_results.txt" 2>/dev/null)

mapfile -t OSS < <(printf "%s\n" "${OSS[@]}" | sort)

{
    echo
    echo "| Platform | Result |"
    echo "| :------- | :----: |"
} >> "$GITHUB_STEP_SUMMARY"

for os in "${OSS[@]}"; do
    v="${DATA[$os]:-N/A}"

    if [[ "$v" != "N/A" ]]; then
        IFS="/" read -r p tot <<< "$v"
        if (( p == tot )); then
            col="brightgreen"
        else
            col="red"
        fi
        tag=${v//\//%2F}

        echo "| **$os** | ![$v](https://img.shields.io/badge/-${tag}-${col}?style=flat-square) |" \
            >> "$GITHUB_STEP_SUMMARY"
    else
        echo "| **$os** | - |" >> "$GITHUB_STEP_SUMMARY"
    fi
done

{
    echo
    printf "**Total Progress: %d/%d Passes (%d Failures)**\n" \
        "$P_SUM" "$T_SUM" "$F_SUM"
    echo
} >> "$GITHUB_STEP_SUMMARY"

if [[ $F_SUM -eq 0 && $T_SUM -gt 0 ]]; then
    echo "### All Tests Passed! 🥳🎉🍾" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ ${#FAILS[@]} -gt 0 ]]; then
    printf "### Failures Detail\n\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
    for f in "${FAILS[@]}"; do echo "$f" >> "$GITHUB_STEP_SUMMARY"; done
    printf "\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
fi

log_success "Matrix generated."
