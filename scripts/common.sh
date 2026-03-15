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

# Detect OS
OS="${RUNNER_OS:-$(uname -s)}"
case "$OS" in
    Linux*)     PLATFORM="Linux" ;;
    Darwin*|macOS*)    PLATFORM="macOS" ;;
    Windows*|MINGW*|MSYS*) PLATFORM="Windows" ;;
    *)          PLATFORM="Unknown" ;;
esac

# Compiler path normalization with robust discovery
get_c3c_path() {
    local base_path="./c3c/build/c3c"
    local bin_name="c3c"
    if [[ "$PLATFORM" == "Windows" ]]; then
        bin_name="c3c.exe"
    fi

    local default_path="${base_path}${bin_name#c3c}"
    
    # 1. Try default path
    if [[ -f "$default_path" ]]; then
        echo "$default_path"
        return
    fi
    
    # 2. Try searching in the build directory (handles Release/, bin/, etc.)
    local found=$(find ./c3c/build -name "$bin_name" -type f | head -n 1)
    if [[ -n "$found" ]]; then
        echo "$found"
        return
    fi
    
    # 3. Fallback to default path (for error reporting later)
    echo "$default_path"
}

# Ensure execution permissions on Unix
ensure_executable() {
    local file="$1"
    if [[ "$PLATFORM" != "Windows" && -f "$file" ]]; then
        chmod +x "$file"
    fi
}
