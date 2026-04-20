#!/usr/bin/env bash
# shellcheck source=scripts/common.sh
source "$(dirname "$0")/common.sh"

log_info "Setting up $PLATFORM..."

case "$PLATFORM" in
    Linux)   
        check_deps cmake ninja curl || { sudo apt-get update; sudo apt-get install -y cmake ninja-build build-essential curl; } 
        ;;
    macOS)   
        # Idempotent brew install
        for pkg in cmake ninja; do
            if ! brew list "$pkg" &>/dev/null; then
                log_info "Installing $pkg via Homebrew..."
                brew install "$pkg"
            else
                log_info "$pkg is already installed."
            fi
        done
        ;;
    Windows) 
        check_deps cmake ninja || choco install cmake ninja -y
        ;;
    *)       log_error "Unsupported: $PLATFORM"; exit 1 ;;
esac

log_success "Setup done."
