#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up $PLATFORM..."

case "$PLATFORM" in
    Linux)   check_deps cmake ninja curl || { sudo apt-get update; sudo apt-get install -y cmake ninja-build build-essential curl libtree-sitter-dev; } ;;
    macOS)   check_deps cmake ninja tree-sitter || brew install cmake ninja tree-sitter ;;
    Windows) 
        check_deps cmake ninja || choco install cmake ninja -y
        if ! command -v vcpkg &> /dev/null; then
            log_warn "vcpkg not found, attempting to use choco for tree-sitter (CLI only)"
            check_deps tree-sitter || choco install tree-sitter -y
        else
            log_info "Using vcpkg to install tree-sitter library..."
            vcpkg install tree-sitter:x64-windows
        fi
        ;;
    *)       log_error "Unsupported: $PLATFORM"; exit 1 ;;
esac

log_success "Setup done."
