#!/usr/bin/env bash
set -euo pipefail

REPO_URL="$1"
DIR="$2"

echo "::group::Syncing $DIR"

if [ -d "$DIR/.git" ]; then
    echo "Updating existing repo"
    git -C "$DIR" fetch origin
    git -C "$DIR" reset --hard origin/HEAD
else
    echo "Cloning $REPO_URL"
    git clone --depth 1 "$REPO_URL" "$DIR"
fi

COMMIT=$(git -C "$DIR" rev-parse --short HEAD)

echo "$DIR commit: $COMMIT"

echo "::endgroup::"
