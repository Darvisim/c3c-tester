#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Generating test summary..."

echo "## C3 Test Results ($PLATFORM)" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "| OS | Target | Total | Passed | Failed |" >> "$GITHUB_STEP_SUMMARY"
echo "|----|--------|-------|--------|--------|" >> "$GITHUB_STEP_SUMMARY"

TOTAL_SUM=0
PASSED_SUM=0
FAILED_SUM=0
rows=()

while IFS= read -r file; do
    log_info "Processing $file"
    IFS="|" read -r OS MODE TOTAL PASSED FAILED < "$file"
    rows+=("$OS|$MODE|$TOTAL|$PASSED|$FAILED")
    TOTAL_SUM=$((TOTAL_SUM + TOTAL))
    PASSED_SUM=$((PASSED_SUM + PASSED))
    FAILED_SUM=$((FAILED_SUM + FAILED))
done < <(find results -name "test_results.txt" 2>/dev/null || true)

if [[ ${#rows[@]} -eq 0 ]]; then
    log_warn "No test result files found."
else
    IFS=$'\n' sorted=($(printf "%s\n" "${rows[@]}" | sort))
    unset IFS
    for row in "${sorted[@]}"; do
        IFS="|" read -r OS MODE TOTAL PASSED FAILED <<< "$row"
        echo "| $OS | $MODE | $TOTAL | $PASSED | $FAILED |" >> "$GITHUB_STEP_SUMMARY"
    done
fi

echo "| **TOTAL** | **ALL** | **$TOTAL_SUM** | **$PASSED_SUM** | **$FAILED_SUM** |" >> "$GITHUB_STEP_SUMMARY"
log_success "Summary generated."
