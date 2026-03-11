#!/usr/bin/env bash
set -euo pipefail

REPO_URL="https://github.com/c3lang/c3c.git"
CLONE_DIR="./c3c"

echo "::group::Syncing c3c repository"

if [ -d "$CLONE_DIR/.git" ]; then
    echo "Repository exists. Checking for updates..."

    cd "$CLONE_DIR"

    OLD_HASH=$(git rev-parse --short HEAD)

    git fetch origin master

    NEW_HASH=$(git rev-parse --short origin/master)

    if [ "$OLD_HASH" = "$NEW_HASH" ]; then
        echo "Already up to date ($OLD_HASH)"
    else
        echo "Updates detected:"
        echo

        # Show commits merged into upstream/master since last sync
        git log --pretty=format:'%h -> %h : %s' HEAD..origin/master

        echo
        echo "Updating repository..."

        git reset --hard origin/master
    fi

    cd ..

else
    echo "Cloning c3c repository..."
    git clone "$REPO_URL" "$CLONE_DIR"

    cd "$CLONE_DIR"

    NEW_HASH=$(git rev-parse --short HEAD)

    echo "Initial clone at commit $NEW_HASH"

    cd ..
fi

echo "::endgroup::"
