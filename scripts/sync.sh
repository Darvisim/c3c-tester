#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
set -euo pipefail

REPO_URL="$1"
DIR="$2"

echo "::group::Syncing $DIR"

if [[ -d "$DIR/.git" ]]; then
    log_info "Updating existing repo in $DIR"
    git -C "$DIR" fetch origin
    git -C "$DIR" reset --hard origin/HEAD
else
    [[ -d "$DIR" ]] && { 
        log_warn "Directory $DIR exists but is not a git repo. Recreating..."
        rm -rf "$DIR"
    }
    log_info "Cloning $REPO_URL into $DIR"
    git clone --depth 1 "$REPO_URL" "$DIR"
fi

COMMIT=$(git -C "$DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
log_success "$DIR sync complete (commit: $COMMIT)"

echo "::endgroup::"