#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
URL="$1"; DIR="$2"
echo "::group::Syncing $DIR"
if [ -d "$DIR/.git" ]; then
    log_info "Updating $DIR"
    git -C "$DIR" fetch origin && git -C "$DIR" reset --hard origin/HEAD
else
    [ -d "$DIR" ] && { log_warn "Recreating $DIR"; rm -rf "$DIR"; }
    log_info "Cloning $URL"
    git clone --depth 1 "$URL" "$DIR"
fi
log_success "$DIR synced (commit: $(git -C "$DIR" rev-parse --short HEAD 2>/dev/null || echo "??"))"
echo "::endgroup::"
