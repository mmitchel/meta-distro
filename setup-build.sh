#!/bin/bash
# Setup script for Yocto build environment using repo tool

# Check if script is being sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "Error: This script must be sourced, not executed."
    echo "Usage: source $0"
    exit 1
fi

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_URL="file://${PROJECT_ROOT}/manifests"
BUILD_DIR="${PROJECT_ROOT}/build"

echo "==================================="
echo "Yocto Poky Build Setup - Demo"
echo "==================================="

# Check if repo is installed
if ! command -v repo &> /dev/null; then
    echo "Error: 'repo' tool is not installed."
    echo "Please install it first:"
    echo "  mkdir -p ~/.bin"
    echo "  curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo"
    echo "  chmod a+rx ~/.bin/repo"
    echo "  export PATH=~/.bin:\$PATH"
    exit 1
fi

# Initialize repo if not already done
if [ ! -d "${PROJECT_ROOT}/.repo" ]; then
    echo "Initializing repo..."
    cd "${PROJECT_ROOT}"
    repo init -u file://$(pwd) -b main -m manifests/default.xml
    echo "Syncing repositories..."
    repo sync
else
    echo "Repo already initialized. Syncing..."
    cd "${PROJECT_ROOT}"
    repo sync
fi

# Create build directory if it doesn't exist
if [ ! -d "${BUILD_DIR}" ]; then
    echo "Creating build directory..."
    mkdir -p "${BUILD_DIR}"
fi

# Setup build environment with TEMPLATECONF
echo "Setting up build environment..."
cd "${PROJECT_ROOT}"
TEMPLATECONF="${PROJECT_ROOT}/layers/meta-distro/conf/templates/default" source layers/poky/oe-init-build-env "${BUILD_DIR}"

echo ""
echo "==================================="
echo "Setup complete!"
echo "==================================="
echo ""
echo "Build environment is now active."
echo "To start building, run:"
echo "  bitbake core-image-minimal"
echo ""
