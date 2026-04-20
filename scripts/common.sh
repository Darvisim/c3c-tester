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

check_deps() {
    for cmd in "$@"; do
        if ! command -v "$cmd" &>/dev/null; then return 1; fi
    done
    return 0
}

get_c3c_path() {
    local bin="c3c$([[ "$PLATFORM" == "Windows" ]] && echo ".exe" || echo "")"
    local base="./c3c/build/$bin"
    local paths=("$base" "./c3c/build/Release/$bin" "./c3c/build/Debug/$bin" "./c3c/build/bin/$bin")
    for p in "${paths[@]}"; do
        if [[ -f "$p" ]]; then echo "$(realpath "$p")"; return; fi
    done
    local found=$(find ./c3c/build -name "$bin" -type f 2>/dev/null | head -n 1)
    if [[ -n "$found" ]]; then echo "$(realpath "$found")"; return; fi
    realpath "$base" 2>/dev/null || echo "$base"
}

ensure_executable() {
    if [[ "$PLATFORM" != "Windows" && -f "$1" ]]; then chmod +x "$1"; fi
}

get_bin_name() {
    local f="${1:-}"
    local b=$(basename "$f")
    local n="${b%.*}"
    [[ "${PLATFORM:-}" == "Windows" ]] && n="${n}.exe"
    echo "$n"
}

is_main_missing() {
    local f="${1:-}"
    if [[ ! -f "$f" ]]; then return 0; fi
    ! grep -Eq 'fn\s+(void|int|u?[0-9]+)?\s*main\s*\(' "$f"
}