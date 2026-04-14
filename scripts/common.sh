#!/usr/bin/env bash

# Shared CI logic
set -euo pipefail

# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

# Detect OS/Platform
OS="${RUNNER_OS:-}"
[[ -z "$OS" ]] && OS=$(uname -s)
case "$OS" in
    Linux*)   PLATFORM="Linux" ;;
    Darwin*|macOS*)  PLATFORM="macOS" ;;
    Windows*|MINGW*|MSYS*) PLATFORM="Windows" ;;
    *)        PLATFORM="Unknown" ;;
esac

# Check if commands exist
check_deps() {
    for cmd in "$@"; do command -v "$cmd" &>/dev/null || return 1; done
    return 0
}

# Compiler path discovery
get_c3c_path() {
    local bin="c3c$([[ "$PLATFORM" == "Windows" ]] && echo ".exe")"
    local paths=("./c3c/build/$bin" "./c3c/build/Release/$bin" "./c3c/build/bin/$bin")
    for p in "${paths[@]}"; do [[ -f "$p" ]] && { realpath "$p"; return; }; done
    local found=$(find ./c3c/build -name "$bin" -type f 2>/dev/null | head -n 1)
    [[ -n "$found" ]] && { realpath "$found"; return; }
    realpath "./c3c/build/$bin" 2>/dev/null || echo "./c3c/build/$bin"
}

# Permissions
ensure_executable() { [[ "$PLATFORM" != "Windows" && -f "$1" ]] && chmod +x "$1"; }

# Binary name
get_bin_name() {
    local b=$(basename "${1:-}")
    echo "${b%.*}"
}

# Robust main check
is_main_missing() {
    local f="${1:-}"
    [[ ! -f "$f" ]] && return 0
    # Match fn main( outside of line comments
    ! grep -v '^[[:space:]]*//' "$f" | grep -Eq 'fn\s+([a-zA-Z0-9_]+\s+)?main\s*\('
}
