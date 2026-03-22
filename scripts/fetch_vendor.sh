#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
C3C=$(get_c3c_path) && ensure_executable "$C3C"
[ -d "vendor/libraries" ] || { log_warn "vendor/libraries missing."; exit 0; }

log_info "Fetching vendor libraries..."
find vendor/libraries -maxdepth 1 -mindepth 1 -type d | while read -r d; do
    lib=$(basename "$d") && [[ "$lib" == .* ]] && continue
    lib="${lib%.c3l}"
    log_info "Fetching $lib..."
    (cd "$d" && "$C3C" vendor-fetch "$lib") && log_success "Fetched $lib" || log_warn "Failed $lib"
done
log_success "Fetch complete."
