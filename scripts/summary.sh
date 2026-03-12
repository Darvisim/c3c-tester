#!/usr/bin/env bash
set -euo pipefail

echo "::group::Generating unified summary"

echo "## C3 CI Test Summary" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"

echo "| OS | Total | Passed | Failed |" >> "$GITHUB_STEP_SUMMARY"
echo "|----|------:|------:|------:|" >> "$GITHUB_STEP_SUMMARY"

for f in results-*/*; do
    OS=$(basename "$(dirname "$f")" | sed 's/results-//')

    IFS="|" read -r TOTAL PASSED FAILED < "$f"

    echo "| $OS | $TOTAL | $PASSED | $FAILED |" >> "$GITHUB_STEP_SUMMARY"
done

echo "::endgroup::"
