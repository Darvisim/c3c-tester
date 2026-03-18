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

# Detect OS (simplified)
case "${RUNNER_OS:-$(uname -s)}" in
    Linux*) PLATFORM="Linux" ;;
    Darwin*) PLATFORM="macOS" ;;
    Windows*|MINGW*|MSYS*) PLATFORM="Windows" ;;
    *) PLATFORM="Unknown" ;;
esac

# Unified executable extension
EXE_EXT=$([[ "$PLATFORM" == "Windows" ]] && echo ".exe")

# Helper: safe absolute path
abspath() { realpath "$1" 2>/dev/null || echo "$1"; }

# Compiler path normalization with reduced duplication
get_c3c_path() {
    local bin="c3c$EXE_EXT"
    local paths=(
        "./c3c/build/$bin"
        "./c3c/build/Release/$bin"
        "./c3c/build/Debug/$bin"
        "./c3c/build/bin/$bin"
    )

    # 1. Try known paths
    for p in "${paths[@]}"; do
        [[ -f "$p" ]] && abspath "$p" && return
    done

    # 2. Try generic search in build dir
    local found
    found=$(find ./c3c/build -name "$bin" -type f -print -quit)
    [[ -n "$found" ]] && abspath "$found" && return

    # 3. Fallback
    echo "./c3c/build/$bin"
}

# Ensure execution permissions on Unix
ensure_executable() {
    local file="$1"
    [[ "$PLATFORM" != "Windows" && -f "$file" ]] && chmod +x "$file"
}