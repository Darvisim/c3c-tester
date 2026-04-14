#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up $PLATFORM..."

case "$PLATFORM" in
    Linux)   check_deps cmake ninja curl || { sudo apt-get update; sudo apt-get install -y cmake ninja-build build-essential curl; } ;;
    macOS)   check_deps cmake ninja || brew install cmake ninja ;;
    Windows) check_deps cmake ninja || choco install cmake ninja -y ;;
    *)       log_error "Unsupported: $PLATFORM"; exit 1 ;;
esac

log_success "Setup done."
