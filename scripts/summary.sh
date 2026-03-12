#!/usr/bin/env bash
set -euo pipefail

echo "## C3 Test Results" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

echo "| OS | Target | Total | Passed | Failed |" >> "$GITHUB_STEP_SUMMARY"
echo "|----|--------|-------|--------|--------|" >> "$GITHUB_STEP_SUMMARY"

for file in results-*/.test_results; do
    [ -f "$file" ] || continue

    IFS="|" read -r OS MODE TOTAL PASSED FAILED < "$file"

    echo "| $OS | $MODE | $TOTAL | $PASSED | $FAILED |" >> "$GITHUB_STEP_SUMMARY"
done
