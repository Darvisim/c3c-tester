#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up dependencies for $PLATFORM..."

case "$PLATFORM" in
    Linux)
        if ! command -v cmake &>/dev/null || ! command -v ninja &>/dev/null || ! command -v curl &>/dev/null; then
            sudo apt-get update
            sudo apt-get install -y cmake ninja-build build-essential curl
        fi
        ;;
    macOS)
        for pkg in cmake ninja; do
            if ! command -v "$pkg" &>/dev/null; then
                if ! brew list "$pkg" &>/dev/null; then
                    brew install "$pkg"
                fi
            fi
        done
        ;;
    Windows)
        if ! command -v cmake &>/dev/null || ! command -v ninja &>/dev/null; then
            choco install cmake ninja -y
        fi
        ;;
    *)
        log_error "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

log_success "Dependencies installed."
