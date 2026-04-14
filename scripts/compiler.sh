#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
log_info "Building C3 Compiler on $PLATFORM..."

SRC_DIR="./c3c"
BUILD_DIR="./c3c/build"

if [[ "$PLATFORM" == "Windows" ]]; then
    # Use a very short path to avoid Windows 8192 character limit for command lines
    SHORT_ROOT="/c/c3"
    mkdir -p "$SHORT_ROOT"
    log_info "Moving build to $SHORT_ROOT to bypass Windows CLI limit"
    rm -rf "$SHORT_ROOT/c3c" && cp -r "$SRC_DIR" "$SHORT_ROOT/"
    SRC_DIR="$SHORT_ROOT/c3c"
    BUILD_DIR="$SRC_DIR/build"
fi

echo "::group::Build"
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release -DC3_FETCH_LLVM=ON && cmake --build "$BUILD_DIR"
echo "::endgroup::"

if [[ "$PLATFORM" == "Windows" ]]; then
    # Synchronize back to workspace for artifact upload
    log_info "Syncing build results back to workspace..."
    mkdir -p ./c3c/build
    cp -r "$BUILD_DIR/"* ./c3c/build/
fi

C3C=$(get_c3c_path) && ensure_executable "$C3C"
if "$C3C" --version >/dev/null 2>&1; then
    log_success "Compiler built: $($C3C --version | head -n 1)"
else
    log_error "Build validation failed."; exit 1
fi
