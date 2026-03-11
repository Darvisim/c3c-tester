#!/usr/bin/env bash
set -euo pipefail

C3_DIR="./c3c"
BUILD_DIR="$C3_DIR/build"

echo "::group::Building C3 Compiler"

cmake -B "$BUILD_DIR" \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DC3_FETCH_LLVM=ON \
  "$C3_DIR"

cmake --build "$BUILD_DIR"

echo "Verifying c3c build..."
"$BUILD_DIR/c3c" --version

echo "::endgroup::"
