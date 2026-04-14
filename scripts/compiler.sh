#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
log_info "Building C3 Compiler on $PLATFORM..."

if [[ "$PLATFORM" == "Windows" ]]; then
    # Workaround for missing ASAN libs in fetched LLVM artifact
    ASAN_SRC_DIR="./c3c/build/_deps/llvm_artifact-src/lib/windows"
    mkdir -p "$ASAN_SRC_DIR"
    # Search for clang_rt.asan in system (Enterprise is default on GHA windows-latest)
    MSVC_LIB=$(find "/c/Program Files/Microsoft Visual Studio/2022/Enterprise/VC/Tools/MSVC" -name "clang_rt.asan_dynamic-x86_64.lib" | head -n 1)
    if [[ -n "$MSVC_LIB" ]]; then
        log_info "Found system ASAN lib: $MSVC_LIB"
        cp "$MSVC_LIB" "$ASAN_SRC_DIR/"
        cp "${MSVC_LIB%.lib}.dll" "$ASAN_SRC_DIR/" 2>/dev/null || true
    fi
fi

echo "::group::Build"
cmake -S ./c3c -B ./c3c/build -G Ninja -DCMAKE_BUILD_TYPE=Release -DC3_FETCH_LLVM=ON && cmake --build ./c3c/build --verbose
echo "::endgroup::"

C3C=$(get_c3c_path) && ensure_executable "$C3C"
if "$C3C" --version >/dev/null 2>&1; then
    log_success "Compiler built: $($C3C --version | head -n 1)"
else
    log_error "Build validation failed."; exit 1
fi
