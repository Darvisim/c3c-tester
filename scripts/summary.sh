#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Generating test summary..."

# Safely handle missing GITHUB_STEP_SUMMARY
if [[ -z "${GITHUB_STEP_SUMMARY:-}" ]]; then
    GITHUB_STEP_SUMMARY="/dev/null"
fi

echo "## Final Test Results ($PLATFORM)" >> "$GITHUB_STEP_SUMMARY"
echo "" >> "$GITHUB_STEP_SUMMARY"
echo "| OS | Target | Total | Passed | Failed |" >> "$GITHUB_STEP_SUMMARY"
echo "|----|--------|-------|--------|--------|" >> "$GITHUB_STEP_SUMMARY"

TOTAL_SUM=0
PASSED_SUM=0
FAILED_SUM=0
rows=()

FAILED_LIST_ALL=()

while IFS= read -r file; do
    log_info "Processing $file"
    if [ ! -s "$file" ]; then
        log_warn "File $file is empty or missing. Skipping."
        continue
    fi
    {
        if read -r header; then
            IFS="|" read -r OS MODE TOTAL PASSED FAILED <<< "$header"
            if [[ -n "$OS" && -n "$MODE" ]]; then
                rows+=("$OS|$MODE|$TOTAL|$PASSED|$FAILED")
                TOTAL_SUM=$((TOTAL_SUM + TOTAL))
                PASSED_SUM=$((PASSED_SUM + PASSED))
                FAILED_SUM=$((FAILED_SUM + FAILED))
                
                while read -r fail; do
                    FAILED_LIST_ALL+=("[$OS/$MODE] $fail")
                done
            fi
        fi
    } < "$file"
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

if [[ ${#FAILED_LIST_ALL[@]} -gt 0 ]]; then
    echo -e "\n### Failures Detail" >> "$GITHUB_STEP_SUMMARY"
    echo '```' >> "$GITHUB_STEP_SUMMARY"
    
    echo -e "\n${RED}================ GLOBAL FAILURES SUMMARY ================${NC}"
    for fail in "${FAILED_LIST_ALL[@]}"; do
        echo -e "${RED}[FAIL]${NC} $fail"
        echo "$fail" >> "$GITHUB_STEP_SUMMARY"
    done
    echo -e "${RED}========================================================${NC}\n"
    
    echo '```' >> "$GITHUB_STEP_SUMMARY"
fi

log_success "Summary generated."
