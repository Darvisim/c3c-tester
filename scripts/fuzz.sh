#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"
set +e

C3C=$(get_c3c_path)
ensure_executable "$C3C"

FUZZ_REPO="https://github.com/ManuLinares/c3fuzz"
FUZZ_DIR="c3fuzz"

if [ ! -d "$FUZZ_DIR" ]; then
    log_info "Cloning c3fuzz..."
    git clone --depth 1 "$FUZZ_REPO" "$FUZZ_DIR"
fi

pushd "$FUZZ_DIR" > /dev/null || exit 1

log_info "Building c3fuzz..."
# Build the fuzzer using the current c3c
BUILD_CMD=("$C3C" build)

# On Windows, we might need to point to vcpkg libraries if tree-sitter was installed there
if [[ "$PLATFORM" == "Windows" ]]; then
    if [[ -n "$VCPKG_INSTALLATION_ROOT" ]]; then
        VCPKG_LIB_PATH="$VCPKG_INSTALLATION_ROOT/installed/x64-windows/lib"
        if [ -d "$VCPKG_LIB_PATH" ]; then
            log_info "Adding vcpkg lib path: $VCPKG_LIB_PATH"
            BUILD_CMD+=("-L" "$VCPKG_LIB_PATH")
        fi
    fi
fi

"${BUILD_CMD[@]}"

if [ ! -f "build/c3fuzz" ] && [ ! -f "build/c3fuzz.exe" ]; then
    log_error "Failed to build c3fuzz"
    popd > /dev/null
    exit 1
fi

FUZZ_BIN="./build/c3fuzz"
[[ "$PLATFORM" == "Windows" ]] && FUZZ_BIN="./build/c3fuzz.exe"

log_info "Running c3fuzz for ${FUZZ_TIME:-300} seconds..."
mkdir -p crash segfault timeout
# Running the fuzzer. -t is time in seconds, -s is seed directory.
# We use the stdlib of the cloned c3c repo as seed.
"$FUZZ_BIN" -t "${FUZZ_TIME:-300}" -s ../c3c/lib/std -s crash -s segfault -s timeout

CRASHES=$(ls crash 2>/dev/null | wc -l)
SEGFAULTS=$(ls segfault 2>/dev/null | wc -l)
TIMEOUTS=$(ls timeout 2>/dev/null | wc -l)

log_info "Fuzzing Result -> Crashes: $CRASHES, Segfaults: $SEGFAULTS, Timeouts: $TIMEOUTS"

popd > /dev/null

if [ "$CRASHES" -gt 0 ] || [ "$SEGFAULTS" -gt 0 ]; then
    log_error "Fuzzer found critical issues!"
    exit 1
fi

exit 0
