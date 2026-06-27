#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { printf "${BLUE}[INFO]${NC} %s\n" "$1"; }
log_success() { printf "${GREEN}[SUCCESS]${NC} %s\n" "$1"; }
log_warn() { printf "${YELLOW}[WARN]${NC} %s\n" "$1"; }
log_error() { printf "${RED}[ERROR]${NC} %s\n" "$1"; }

OS="${RUNNER_OS:-$(uname -s)}"
case "$OS" in
    Linux*)                PLATFORM="Linux" ;;
    Darwin*|macOS*)        PLATFORM="macOS" ;;
    Windows*|MINGW*|MSYS*) PLATFORM="Windows" ;;
    *)                     PLATFORM="Unknown" ;;
esac

get_c3c_path() {
    if command -v c3c >/dev/null 2>&1; then
        command -v c3c
        return
    fi
    
    local bin="c3c"

    [[ "$PLATFORM" == "Windows" ]] && bin+=".exe"
    
    local default_path="./c3c/build/$bin"
    local paths=(
        "$default_path"
        "./c3c/build/Release/$bin"
        "./c3c/build/Debug/$bin"
        "./c3c/build/bin/$bin"
    )
    for p in "${paths[@]}"; do
        [[ -f "$p" ]] && {
            realpath "$p"
            return
        }
    done
    local found
    found=$(find ./c3c/build -name "$bin" -type f 2>/dev/null | head -n 1)
    if [[ -n "$found" ]]; then realpath "$found"; return; fi
    realpath "$default_path" 2>/dev/null || echo "$default_path"
}

ensure_executable() {
    [[ "$PLATFORM" == "Windows" ]] && return
    [[ -f "$1" ]] && chmod +x "$1"
}

get_bin_name() {
    local file="${1:-}"
    local n
    n=$(basename "${file%.*}")
    [[ "$PLATFORM" == "Windows" ]] && n+=".exe"
    echo "$n"
}
