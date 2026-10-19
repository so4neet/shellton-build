#!/usr/bin/env bash

err_msg() {
    echo -e "\033[31m[ X ]\033[0m $1"
}

yes_msg() {
    echo -e "\033[0;32m[:::]\033[0m $1"
}


# Grab root perms so we can fetch whatever deps we need from pacman

if [ "$EUID" -ne 0 ]; then
    echo "Escalating to root..."
    exec sudo bash "$(realpath "$0")" "$@"
fi

set -eo pipefail

# Paths

BLDR_ROOT="/srv/shellton"
REPO_DIR="${BLDR_ROOT}/repo"
WORK_DIR="${BLDR_ROOT}/working"
REPO_POOL="${BLDR_ROOT}/repository/final"

# This needs a file input, so error if not
if [ "$#" -ne 1 ]; then
    echo "Usage: ./builder.sh <pkg-name>.shellton"
    echo ""
    echo "This script is typically only run standalone for new packages / debugging."
    exit 1
fi

SHELLTON_PATH="$(realpath "$1")"
if [ ! -f "$SHELLTON_PATH" ]; then
    err_msg "Couldn't locate Shellton file at $SHELLTON_PATH"
    exit 1
fi

yes_msg "Loading Shellton - $SHELLTON_PATH"
source "$SHELLTON_PATH"

# Check that everything is here
: "${PKG_NAME:?Shellton missing PKG_NAME}"
: "${PKG_VER:?Shellton missing PKG_VER}"
: "${PKG_URL:?Shellton missing PKG_URL}"

# Check for critical flags

# Check for debug mode
if [ -v DEV_DEBUG ]; then
    echo "----DEBUG----"
    echo "$PKG_URL"
    echo "$VER"
    echo "$PKG_NAME"
    echo "-------------"
fi
    
if [ -v FLAG_OOD ]; then
    err_msg "Package flagged Out of Date!"
    exit 1
fi

if [ -v FLAG_BROKEN ]; then
    err_msg "Packaged flagged as broken!"
    exit 1
fi

if [ -v FLAG_DEPRICATED ]; then
    err_msg "Package has been depricated. Skipping..."
    exit 1
fi

PKG_FULLNAME="${PKG_NAME}-${PKG_VER}-lira"
PKG_WORK_DIR="${WORK_DIR}/${PKG_FULLNAME}"
PKG_DEST_DIR="${PKG_WORK_DIR}/dest"
SRC_CACHEDIR="${BLDR_ROOT}/source"

# Create the working directories

mkdir -p "$PKG_WORK_DIR" "$PKG_DEST_DIR" "$SRC_CACHEDIR" "$REPO_POOL"

# Copy over the Shellton file so the sandbox can see it

LOCAL_SHELLTON="${PKG_WORK_DIR}/tmp.shellton"
cp "$SHELLTON_PATH" "$LOCAL_SHELLTON"

yes_msg "Starting build for '${PKG_FULLNAME}'..."

# Check if any dependencies need to be installed

if [ -v "${BUILD_DEPENDS:-}" ]; then
    yes_msg "Build server requires dependencies:"
    pacman -S --needed --noconfirm ${BUILD_DEPENDS}
fi

# Fetch source & cache it

SRC_ARCHIVE="$(basename "$PKG_URL")"
SRC_PATH="${SRC_CACHEDIR}/${SRC_ARCHIVE}"

if [ ! -f "$SRC_PATH" ]; then
    # Check what kind of distribution the package comes as
    if [ -v FLAG_APPIMAGE ]; then
	yes_msg "Fetching latest AppImage"
    elif [ -v FLAG_PREPACKAGED ]; then
	yes_msg "Fetching tarball/package..."
    else
	yes_msg "Fetching source..."
    fi
    if ! curl --output /dev/null --silent --head --fail --location "$PKG_URL"; then
	err_msg "Failed to grab from PKG_URL. Please double-check upstream URL."
	exit 1
    fi
    curl -L -o "$SRC_PATH" "$PKG_URL"
else
    yes_msg "Using cached: $SRC_ARCHIVE"
fi

# If AppImage, then just move to final step

if [ -v FLAG_APPIMAGE ]; then
    yes_msg "Bundling AppImage..."
    cp "$SRC_PATH" "$PKG_WORK_DIR"
    echo "PKG_NAME=$PKG_NAME" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_PRETTY=$PKG_PRETTY" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_DESC=$PKG_DESC" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_VER=$PKG_VER" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_CHKSUM=$(sha256sum $SRC_PATH | head -c 64)" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    yes_msg "Compressing Bundle..."
    tar -czf "${REPO_POOL}/${PKG_FULLNAME}.bundle" "$SRC_PATH" "${PKG_NAME}.meta"
    cp "${REPO_POOL}/${PKG_FULLNANME}.bundle" "${REPO_POOL}/${PKG_FULLNAME}.bundle"
    exit 0
fi
