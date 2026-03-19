#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up dependencies for $PLATFORM..."

case "$PLATFORM" in
    Linux)
        if ! check_deps cmake ninja curl; then
            sudo apt-get update
            sudo apt-get install -y cmake ninja-build build-essential curl
        fi
        ;;
    macOS)
        if ! check_deps cmake ninja; then
            brew install cmake ninja
        fi
        ;;
    Windows)
        if ! check_deps cmake ninja; then
            choco install cmake ninja -y
        fi
        ;;
    *)
        log_error "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

log_success "Dependencies installed."
