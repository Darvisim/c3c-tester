#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

U="$1"
D="$2"

echo "::group::Syncing $D"

if [ -d "$D/.git" ]; then
    log_info "Updating $D"
    git -C "$D" fetch origin && git -C "$D" reset --hard origin/HEAD
else
    [ -d "$D" ] && { log_warn "Recreating $D"; rm -rf "$D"; }
    log_info "Cloning $U"
    git clone --depth 1 "$U" "$D"
fi

log_success "$D synced (commit: $(git -C "$D" rev-parse --short HEAD 2>/dev/null || echo "??"))"
echo "::endgroup::"
