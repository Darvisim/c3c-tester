#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Building C3 on $PLATFORM..."

echo "::group::Build"
cmake -S "./c3c" -B "./c3c/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DC3_FETCH_LLVM=ON && cmake --build "./c3c/build"
echo "::endgroup::"

C3C=$(get_c3c_path) && ensure_executable "$C3C"

if "$C3C" --version >/dev/null 2>&1; then
    log_success "Compiler built: $($C3C --version | head -n 1)"
else
    log_error "Build failed."
    exit 1
fi
