#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
log_info "Generating summary..."

[ -z "${GITHUB_STEP_SUMMARY:-}" ] && GITHUB_STEP_SUMMARY="/dev/null"
printf "## Final Results\n\n| OS | Target | Total | Passed | Failed |\n|----|--------|-------|--------|--------|\n" >> "$GITHUB_STEP_SUMMARY"

T_SUM=0; P_SUM=0; F_SUM=0; ROWS=(); FAILS=()

while IFS= read -r f; do
    [ -s "$f" ] || continue
    read -r header < "$f"
    IFS="|" read -r OS MODE TOT PASSED FAILED <<< "$header"
    [[ -n "$OS" && -n "$MODE" ]] || continue
    ROWS+=("| $OS | $MODE | $TOT | $PASSED | $FAILED |")
    ((T_SUM+=TOT, P_SUM+=PASSED, F_SUM+=FAILED)) || true
    while read -r fail; do FAILS+=("[$OS/$MODE] $fail"); done < <(tail -n +2 "$f")
done < <(find results -name "test_results.txt" 2>/dev/null)

if [[ ${#ROWS[@]} -gt 0 ]]; then
    printf "%s\n" "${ROWS[@]}" | sort >> "$GITHUB_STEP_SUMMARY"
fi
printf "| **TOTAL** | **ALL** | **%d** | **%d** | **%d** |\n" "$T_SUM" "$P_SUM" "$F_SUM" >> "$GITHUB_STEP_SUMMARY"

if [[ ${#FAILS[@]} -gt 0 ]]; then
    printf "\n### Failures Detail\n\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
    for fail in "${FAILS[@]}"; do echo "$fail" >> "$GITHUB_STEP_SUMMARY"; done
    printf "\`\`\`\n" >> "$GITHUB_STEP_SUMMARY"
fi
log_success "Summary generated."
