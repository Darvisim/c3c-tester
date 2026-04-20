#!/usr/bin/env bash
source "$(dirname "$0")/common.sh"

log_info "Setting up $PLATFORM..."

case "$PLATFORM" in
    Linux)   
        check_deps cmake ninja curl || { sudo apt-get update; sudo apt-get install -y cmake ninja-build build-essential curl libtree-sitter-dev; } 
        ;;
    macOS)   
        # Idempotent brew install
        for pkg in cmake ninja tree-sitter; do
            if ! brew list "$pkg" &>/dev/null; then
                log_info "Installing $pkg via Homebrew..."
                brew install "$pkg"
            else
                log_info "$pkg is already installed."
            fi
        done
        ;;
    Windows) 
        check_deps cmake ninja || choco install cmake ninja -y
        if ! command -v vcpkg &> /dev/null; then
            log_warn "vcpkg not found, attempting to use choco for tree-sitter (CLI only)"
            check_deps tree-sitter || choco install tree-sitter -y
        else
            log_info "Using vcpkg to install tree-sitter library..."
            vcpkg install tree-sitter:x64-windows
        fi
        ;;
    *)       log_error "Unsupported: $PLATFORM"; exit 1 ;;
esac

# Download Latest C3 Stable Release
download_c3() {
    local url=""
    local file=""
    case "$PLATFORM" in
        Linux)   url="https://github.com/c3lang/c3c/releases/latest/download/c3-linux.tar.gz"; file="c3-linux.tar.gz" ;;
        macOS)   url="https://github.com/c3lang/c3c/releases/latest/download/c3-macos.zip"; file="c3-macos.zip" ;;
        Windows) url="https://github.com/c3lang/c3c/releases/latest/download/c3-windows.zip"; file="c3-windows.zip" ;;
    esac

    if [ -d "c3" ]; then
        log_info "C3 compiler already exists in ./c3. Skipping download."
        return 0
    fi

    log_info "Downloading C3 compiler from $url..."
    curl -L "$url" -o "$file"
    
    if [[ "$file" == *.tar.gz ]]; then
        tar -xzf "$file"
    else
        # Use portable unzip/tar depending on what's available
        if command -v unzip &>/dev/null; then
            unzip -q "$file"
        else
            tar -xf "$file"
        fi
    fi
    rm -f "$file"
    
    log_success "C3 compiler downloaded and extracted to ./c3"
}

download_c3

log_success "Setup done."
