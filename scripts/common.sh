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
    local bin="c3c"
    [[ "$PLATFORM" == "Windows" ]] && bin+=".exe"

    if command -v "$bin" >/dev/null 2>&1; then
        realpath "$(command -v "$bin")"
        return
    fi

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

    local found=$(
        find ./c3c/build \
            -type f \
            -name "$bin" 2>/dev/null |
        head -n1
    )

    if [[ -n "$found" ]]; then
        realpath "$found"
        return
    fi

    realpath "$default_path" 2>/dev/null || echo "$default_path"
}

ensure_executable() {
    [[ "$PLATFORM" == "Windows" ]] && return
    [[ -f "$1" ]] && chmod +x "$1"
}

format_duration() {
    local start_ns="$1"
    local end_ns elapsed_ns secs millis

    end_ns=$(date +%s%N)
    elapsed_ns=$((end_ns - start_ns))

    secs=$((elapsed_ns / 1000000000))
    millis=$(((elapsed_ns % 1000000000) / 1000000))

    printf "%d.%03d|%d\n" \
        "$secs" \
        "$millis" \
        "$elapsed_ns"
}

shorten_path() {
    local path="$1"

    path="${path#c3c/lib/std/}"
    path="${path#c3c/benchmarks/stdlib/}"
    path="${path#c3c/resources/}"
    path="${path#c3c/test/}"

    printf "%s" "$path"
}
