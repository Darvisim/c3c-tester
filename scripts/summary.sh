#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Generating summary..."

[ -z "${GITHUB_STEP_SUMMARY:-}" ] && GITHUB_STEP_SUMMARY="/dev/null"

printf "## Results\n\n| OS | Target | Total | Passed | Failed |\n|----|--------|-------|--------|--------|\n" >> "$GITHUB_STEP_SUMMARY"

T_SUM=0; P_SUM=0; F_SUM=0; ROWS=(); FAILS=()

while IFS= read -r f; do
    [ -s "$f" ] || continue
    read -r h < "$f"
    IFS="|" read -r OS MOD TOT PAS FAL <<< "$h"
    [[ -n "$OS" && -n "$MOD" ]] || continue
    ROWS+=("| $OS | $MOD | $TOT | $PAS | $FAL |")
    ((T_SUM+=TOT, P_SUM+=PAS, F_SUM+=FAL)) || true
    while read -r fail; do FAILS+=("[$OS/$MOD] $fail"); done < <(tail -n +2 "$f")
done < <(find results -name "test_results.txt" 2>/dev/null)

if [[ ${#ROWS[@]} -gt 0 ]]; then printf "%s\n" "${ROWS[@]}" | sort >> "$GITHUB_STEP_SUMMARY" ; fi

printf "| **TOTAL** | **ALL** | **%d** | **%d** | **%d** |\n" "$T_SUM" "$P_SUM" "$F_SUM" >> "$GITHUB_STEP_SUMMARY"

if [[ ${#FAILS[@]} -gt 0 ]]; then
    printf "\n### Failures\n\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
    for f in "${FAILS[@]}"; do echo "$f" >> "$GITHUB_STEP_SUMMARY"; done
    printf "\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
fi

log_success "Done."
