#!/usr/bin/env bash
set -euo pipefail

echo "## C3 Test Results" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

echo "| OS | Target | Total | Passed | Failed |" >> "$GITHUB_STEP_SUMMARY"
echo "|----|--------|-------|--------|--------|" >> "$GITHUB_STEP_SUMMARY"

TOTAL_SUM=0
PASSED_SUM=0
FAILED_SUM=0

rows=()

while IFS= read -r file; do

    IFS="|" read -r OS MODE TOTAL PASSED FAILED < "$file"

    rows+=("$OS|$MODE|$TOTAL|$PASSED|$FAILED")

    TOTAL_SUM=$((TOTAL_SUM + TOTAL))
    PASSED_SUM=$((PASSED_SUM + PASSED))
    FAILED_SUM=$((FAILED_SUM + FAILED))

done < <(find results -name ".test_results" 2>/dev/null || true)

IFS=$'\n' sorted=($(printf "%s\n" "${rows[@]}" | sort))
unset IFS

for row in "${sorted[@]}"; do
    IFS="|" read -r OS MODE TOTAL PASSED FAILED <<< "$row"

    echo "| $OS | $MODE | $TOTAL | $PASSED | $FAILED |" >> "$GITHUB_STEP_SUMMARY"
done

echo "| **TOTAL** | **ALL** | **$TOTAL_SUM** | **$PASSED_SUM** | **$FAILED_SUM** |" >> "$GITHUB_STEP_SUMMARY"
