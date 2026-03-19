#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

C3_DIR="./c3c"
BUILD_DIR="$C3_DIR/build"

log_info "Building C3 Compiler on $PLATFORM..."

echo "::group::CMake Configuration"
cmake -S "$C3_DIR" \
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

if "$C3C" --version >/dev/null 2>&1; then
    VERSION=$("$C3C" --version | head -n 1)
    log_success "Compiler built successfully: $VERSION"
else
    log_error "Compiler build validation failed."
    exit 1
fi
