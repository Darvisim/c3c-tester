#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up dependencies for $PLATFORM..."

case "$PLATFORM" in
    Linux)   check_deps cmake ninja curl || { sudo apt-get update; sudo apt-get install -y cmake ninja-build build-essential curl; } ;;
    macOS)   check_deps cmake ninja || brew install cmake ninja ;;
    Windows) check_deps cmake ninja || choco install cmake ninja zstd -y ;;
    *)       log_error "Unsupported platform: $PLATFORM"; exit 1 ;;
esac

log_success "Dependencies installed."
