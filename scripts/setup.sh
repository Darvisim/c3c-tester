#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up dependencies for $PLATFORM..."

case "$PLATFORM" in
    Linux)
        sudo apt-get update
        sudo apt-get install -y cmake ninja-build build-essential curl
        ;;
    macOS)
        for pkg in cmake ninja; do
            if ! brew list "$pkg" &>/dev/null; then
                brew install "$pkg"
            fi
        done
        ;;
    Windows)
        choco install cmake ninja -y
        ;;
    *)
        log_error "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

log_success "Dependencies installed."
