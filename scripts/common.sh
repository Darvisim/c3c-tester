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
OS="${RUNNER_OS:-$(uname -s)}"
case "$OS" in
    Linux*)     PLATFORM="Linux" ;;
    Darwin*|macOS*)    PLATFORM="macOS" ;;
    Windows*|MINGW*|MSYS*) PLATFORM="Windows" ;;
    *)          PLATFORM="Unknown" ;;
esac

# Check if commands exist
check_deps() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then return 1; fi
    done
    return 0
}

# Compiler path normalization with robust absolute discovery
get_c3c_path() {
    local bin_name="c3c$([[ "$PLATFORM" == "Windows" ]] && echo ".exe" || echo "")"
    local base_path="./c3c/build/$bin_name"

    local search_paths=(
        "$base_path"
        "./c3c/build/Release/$bin_name"
        "./c3c/build/Debug/$bin_name"
        "./c3c/build/bin/$bin_name"
    )
    
    # 1. Try known paths
    for p in "${search_paths[@]}"; do
        if [[ -f "$p" ]]; then
            echo "$(realpath "$p")"
            return
        fi
    done
    
    # 2. Try generic search in build dir
    local found=$(find ./c3c/build -name "$bin_name" -type f | head -n 1)
    if [[ -n "$found" ]]; then
        echo "$(realpath "$found")"
        return
    fi
    
    # 3. Fallback
    realpath "$base_path" 2>/dev/null || echo "$base_path"
}

# Ensure execution permissions on Unix
ensure_executable() {
    local file="$1"
    if [[ "$PLATFORM" != "Windows" && -f "$file" ]]; then
        chmod +x "$file"
    fi
}
