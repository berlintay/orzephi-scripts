#!/bin/bash

# PowerShell Installation Script for Linux
# Description: Detects system type and installs PowerShell appropriately
# Author: Microsoft Corporation
# License: MIT

set -e

# Constants
TEMP_DIR="/tmp"
LOG_PREFIX="[PowerShell Install]"

# Logging function with standardized format
log() {
    local level="$1"
    local message="$2"
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] ${LOG_PREFIX} ${level}: ${message}"
}

# Error handling function
handle_error() {
    local exit_code=$?
    log "ERROR" "An error occurred on line $1"
    exit "$exit_code"
}

# Set up error handling
trap 'handle_error $LINENO' ERR

# System detection functions
get_os_info() {
    if [ -f /etc/os-release ]; then
        # Load OS information
        . /etc/os-release
        OS_NAME="${ID}"
        OS_VERSION="${VERSION_ID}"
        OS_PRETTY_NAME="${PRETTY_NAME}"
    else
        log "ERROR" "Cannot detect OS information"
        exit 1
    fi
}

get_architecture() {
    local arch
    arch=$(uname -m)
    case $arch in
        x86_64)
            ARCH="amd64"
            ;;
        aarch64)
            ARCH="arm64"
            ;;
        *)
            log "ERROR" "Unsupported architecture: $arch"
            exit 1
            ;;
    esac
}

setup_package_manager() {
    case $OS_NAME in
        ubuntu|debian)
            PKG_MGR="apt"
            PKG_FORMAT="deb"
            INSTALL_CMD="sudo dpkg -i"
            DEP_CMD="sudo apt-get install -f -y"
            ;;
        rhel|centos|fedora)
            PKG_MGR="dnf"
            PKG_FORMAT="rpm"
            INSTALL_CMD="sudo rpm -i"
            DEP_CMD="sudo dnf install -y"
            ;;
        *)
            log "ERROR" "Unsupported distribution: $OS_NAME"
            exit 1
            ;;
    esac
}

get_download_url() {
    local ps_version_url
    local pattern
    
    case $OS_NAME in
        ubuntu|debian)
            pattern="powershell_.*${ARCH}.deb$"
            ;;
        rhel|centos|fedora)
            pattern="powershell-.*${ARCH}.rpm$"
            ;;
    esac

    # Modified JQ query to better filter assets
    ps_version_url=$(curl -s https://api.github.com/repos/PowerShell/PowerShell/releases |
        jq -r --arg pattern "$pattern" '
        [.[] | select(.prerelease == false)] |
        sort_by(.published_at) |
        reverse |
        .[0].assets[] |
        select(.name | test($pattern)) |
        .browser_download_url' |
        head -n 1)

    if [ -z "$ps_version_url" ] || [[ "$ps_version_url" == *"hashes.sha256"* ]]; then
        log "ERROR" "Failed to find PowerShell package for $OS_NAME ($ARCH)"
        log "DEBUG" "Pattern used: $pattern"
        exit 1
    fi

    echo "$ps_version_url"
}

# Main installation logic
main() {
    log "INFO" "Starting PowerShell installation"

    # Detect system information
    log "INFO" "Detecting system information"
    get_os_info
    get_architecture
    setup_package_manager

    log "INFO" "Detected: $OS_PRETTY_NAME ($ARCH)"

    # Check for sudo privileges
    if ! sudo -v; then
        log "ERROR" "This script requires sudo privileges"
        exit 1
    fi

    # Update and install dependencies
    log "INFO" "Installing prerequisites"
    case $PKG_MGR in
        apt)
            sudo apt-get update
            sudo apt-get install -y curl jq wget
            ;;
        dnf)
            sudo dnf check-update
            sudo dnf install -y curl jq wget
            ;;
    esac

    # Check existing installation
    if command -v pwsh &>/dev/null; then
        log "INFO" "PowerShell is already installed:"
        pwsh --version
        read -p "Continue with new installation? (y/n) " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log "INFO" "Installation cancelled by user"
            exit 0
        fi
    fi

    # Get appropriate download URL
    PS_VERSION_URL=$(get_download_url)
    if [[ "$PS_VERSION_URL" == "" ]]; then
        log "ERROR" "Could not determine download URL"
        exit 1
    fi
    
    VERSION=$(echo "$PS_VERSION_URL" | grep -Po '(?<=v)[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")

    # Display version information
    log "INFO" "Found PowerShell version: $VERSION"
    printf "\n%-50s %-15s\n" "URL" "VERSION"
    printf "%-50s %-15s\n" "$PS_VERSION_URL" "$VERSION"

    # Confirm installation
    read -p "Continue with this version? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "INFO" "Installation cancelled by user"
        exit 0
    fi

    # Download and install
    local temp_pkg="${TEMP_DIR}/powershell_${VERSION}_${ARCH}.${PKG_FORMAT}"
    log "INFO" "Downloading PowerShell package"
    if ! curl -L -o "$temp_pkg" "$PS_VERSION_URL" --progress-bar; then
        log "ERROR" "Download failed"
        exit 1
    fi

    log "INFO" "Installing PowerShell"
    if ! $INSTALL_CMD "$temp_pkg"; then
        log "INFO" "Attempting to fix dependencies"
        $DEP_CMD
    fi

    # Cleanup
    log "INFO" "Cleaning up temporary files"
    rm -f "$temp_pkg"

    # Verify installation
    if command -v pwsh &>/dev/null; then
        log "INFO" "PowerShell installation successful!"
        pwsh --version
        log "INFO" "You can now start PowerShell by typing 'pwsh'"
    else
        log "ERROR" "PowerShell installation verification failed"
        exit 1
    fi
}

# Execute main function
main
