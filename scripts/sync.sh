#!/usr/bin/env bash
set -euo pipefail

REPO_URL="${1}"
CLONE_DIR="${2}"

echo "::group::Cloning $(basename "$REPO_URL" .git)"

echo "Repository: $REPO_URL"
echo "Directory:  $CLONE_DIR"

git clone --depth 1 "$REPO_URL" "$CLONE_DIR"

cd "$CLONE_DIR"

COMMIT=$(git rev-parse --short HEAD)

echo "Checked out commit $COMMIT"

cd ..

echo "::endgroup::"
