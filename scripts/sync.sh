#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/c3lang/c3c.git"
CLONE_DIR="./c3c"

echo "::group::Syncing c3c repository"

if [ -d "$CLONE_DIR" ]; then
    echo "Repository exists. Pulling latest changes..."
    cd "$CLONE_DIR"
    git fetch origin
    git reset --hard origin/master
    cd ..
else
    echo "Cloning c3c repository..."
    git clone "$REPO_URL" "$CLONE_DIR"
fi

echo "::endgroup::"
