#!/usr/bin/env bash
set -euo pipefail

echo "::group::Generating unified summary"

echo "## C3 CI Test Summary" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

echo "| OS | Target | Total | Passed | Failed |" >> "$GITHUB_STEP_SUMMARY"
echo "|----|--------|------:|------:|------:|" >> "$GITHUB_STEP_SUMMARY"

shopt -s nullglob

FILES=(results-*/*)

if [ ${#FILES[@]} -eq 0 ]; then
    echo "No test results found."
    echo "| - | - | 0 | 0 | 0 |" >> "$GITHUB_STEP_SUMMARY"
    echo "::endgroup::"
    exit 0
fi

for f in "${FILES[@]}"; do
    dir=$(basename "$(dirname "$f")")

    OS=$(echo "$dir" | cut -d- -f2)
    TARGET=$(echo "$dir" | cut -d- -f3)

    IFS="|" read -r TOTAL PASSED FAILED < "$f"

    echo "| $OS | $TARGET | $TOTAL | $PASSED | $FAILED |" >> "$GITHUB_STEP_SUMMARY"
done

echo "::endgroup::"
