#!/usr/bin/env bash
set -euo pipefail

if [ ! -f .test_results ]; then
    echo "No test results found!"
    exit 1
fi

IFS="|" read -r TOTAL PASSED FAILED < .test_results

echo "::group::Generating Test Summary"

SUMMARY="## C3 CI Test Summary

| Total Tests | Passed | Failed |
|------------:|-------:|-------:|
| $TOTAL | $PASSED | $FAILED |"

echo "$SUMMARY" >> "$GITHUB_STEP_SUMMARY"
echo "$SUMMARY"

echo "::endgroup::"
