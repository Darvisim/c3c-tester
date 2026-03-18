#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up dependencies for $PLATFORM..."

# Helper: check if any command is missing
need_cmds() {
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null || return 0
    done
    return 1
}

case "$PLATFORM" in
    Linux)
        if need_cmds cmake ninja curl; then
            sudo apt-get update
            sudo apt-get install -y cmake ninja-build build-essential curl
        fi
        ;;

    macOS)
        for pkg in cmake ninja; do
            command -v "$pkg" &>/dev/null || brew install "$pkg"
        done
        ;;

    Windows)
        if need_cmds cmake ninja; then
            choco install cmake ninja -y
        fi
        ;;

    *)
        log_error "Unsupported platform: $PLATFORM"
        exit 1
        ;;
esac

log_success "Dependencies installed."