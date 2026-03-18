#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

BUILD_DIR="c3c/build"

log_info "Building C3 Compiler on $PLATFORM..."

echo "::group::CMake Configuration"
cmake -S c3c \
      -B "$BUILD_DIR" \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DC3_FETCH_LLVM=ON
echo "::endgroup::"

echo "::group::Build Process"
cmake --build "$BUILD_DIR"
echo "::endgroup::"

log_info "Verifying build..."
C3C=$(get_c3c_path)
ensure_executable "$C3C"

# Run once and capture version
if VERSION=$("$C3C" --version 2>/dev/null | head -n 1); then
    log_success "Compiler built successfully: $VERSION"
else
    log_error "Compiler build validation failed."
    exit 1
fi