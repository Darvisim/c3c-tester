#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
log_info "Generating matrix summary..."
[ -z "${GITHUB_STEP_SUMMARY:-}" ] && GITHUB_STEP_SUMMARY="/dev/null"

T_SUM=0; P_SUM=0; F_SUM=0; FAILS=()
declare -A DATA
OSS=()
TARGETS=()

while IFS= read -r f; do
    [ -s "$f" ] || continue
    read -r h < "$f"
    IFS="|" read -r OS MOD TOT PAS FAL <<< "$h"
    [[ -n "$OS" && -n "$MOD" ]] || continue
    
    DATA["$MOD,$OS"]="$PAS/$TOT"
    [[ ! " ${OSS[*]} " =~ " ${OS} " ]] && OSS+=("$OS")
    [[ ! " ${TARGETS[*]} " =~ " ${MOD} " ]] && TARGETS+=("$MOD")
    
    ((T_SUM+=TOT, P_SUM+=PAS, F_SUM+=FAL)) || true
    while read -r fail; do FAILS+=("[$OS/$MOD] $fail"); done < <(tail -n +2 "$f")
done < <(find results -name "test_results.txt" 2>/dev/null)

OSS=($(printf "%s\n" "${OSS[@]}" | sort))
TARGETS=($(printf "%s\n" "${TARGETS[@]}" | sort))

printf "### Test Results Matrix\n\n| Target | %s |\n| :--- | %s |\n" "$(IFS=' | '; echo "${OSS[*]}")" "$(printf ' :---: |%.0s' "${OSS[@]}")" >> "$GITHUB_STEP_SUMMARY"

for t in "${TARGETS[@]}"; do
    row="| **$t** "
    for os in "${OSS[@]}"; do
        val="${DATA["$t,$os"]:-N/A}"
        if [[ "$val" != "N/A" ]]; then
            IFS="/" read -r p tot <<< "$val"
            color=$([ "$p" -eq "$tot" ] && echo "green" || echo "red")
            row+="| $\color{$color}{\textsf{$val}}$ "
        else
            row+="| - "
        fi
    done
    echo "$row |" >> "$GITHUB_STEP_SUMMARY"
done

printf "\n**Total Progress: %d/%d Passes (%d Failures)**\n\n" "$P_SUM" "$T_SUM" "$F_SUM" >> "$GITHUB_STEP_SUMMARY"

if [[ $F_SUM -eq 0 && $T_SUM -gt 0 ]]; then
    echo "### All Tests Passed! 🥳🎉🍾" >> "$GITHUB_STEP_SUMMARY"
fi

if [[ ${#FAILS[@]} -gt 0 ]]; then
    printf "### Failures Detail\n\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
    for f in "${FAILS[@]}"; do echo "$f" >> "$GITHUB_STEP_SUMMARY"; done
    printf "\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
fi

log_success "Matrix dashboard generated."
