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

ARCH="${RUNNER_ARCH:-$(uname -m)}"
case "$ARCH" in
    X64|x86_64|amd64) ARCH="x64" ;;
    ARM64|aarch64)    ARCH="arm64" ;;
    ARM|armv7*|armv6*) ARCH="arm" ;;
    i386|i686|x86)    ARCH="x86" ;;
esac

get_c3c_path() {
    local bin="c3c"
    [[ "$PLATFORM" == "Windows" ]] && bin+=".exe"

    if command -v "$bin" >/dev/null 2>&1; then
        realpath "$(command -v "$bin")"
        return
    fi

    local paths=(
        "./build/$bin"
        "./build/bin/$bin"
        "./build/Debug/$bin"
        "./build/Release/$bin"

        "./c3c/build/$bin"
        "./c3c/build/bin/$bin"
        "./c3c/build/Debug/$bin"
        "./c3c/build/Release/$bin"
    )

    local p
    for p in "${paths[@]}"; do
        [[ -f "$p" ]] && {
            realpath "$p"
            return
        }
    done

    local found
    found=$(
        find ./build ./c3c/build \
            -type f \
            -name "$bin" 2>/dev/null |
        head -n1
    )

    if [[ -n "$found" ]]; then
        realpath "$found"
        return
    fi

    echo "./build/$bin"
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
