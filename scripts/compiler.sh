#!/usr/bin/env bash
set -euo pipefail

C3_DIR="./c3c"
BUILD_DIR="$C3_DIR/build"

echo "::group::Building C3 Compiler"

mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

cmake .. -G Ninja -DCMAKE_BUILD_TYPE=Release -DC3_LLVM_FETCH=ON
ninja

echo "Verifying c3c build..."
"$BUILD_DIR/c3c" --version

cd ../..
echo "::endgroup::"
