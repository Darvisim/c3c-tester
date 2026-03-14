#!/usr/bin/env bash
set -euo pipefail

C3_DIR="./c3c"
BUILD_DIR="$C3_DIR/build"

echo "::group::Building C3 Compiler"

cmake -S "$C3_DIR" \
      -B "$BUILD_DIR" \
      -G Ninja \
      -DCMAKE_BUILD_TYPE=Release \
      -DC3_FETCH_LLVM=ON

cmake --build "$BUILD_DIR"

echo "Verifying c3c build..."
C3C_EXE="$BUILD_DIR/c3c"
[ -f "${C3C_EXE}.exe" ] && C3C_EXE="${C3C_EXE}.exe"
"$C3C_EXE" --version

echo "::endgroup::"
