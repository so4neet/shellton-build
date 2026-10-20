#!/usr/bin/env bash

err_msg() {
    echo -e "\033[31m[ X ]\033[0m $1"
}

yes_msg() {
    echo -e "\033[0;32m[:::]\033[0m $1"
}


# Grab root perms so we can fetch whatever deps we need from pacman

#if [ "$EUID" -ne 0 ]; then
#    PREV_USER="$(whoami)"
#    echo "Escalating to root..."
#    exec sudo bash "$(realpath "$0")" "$@"
#fi

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

if [ -n "${BUILD_DEPENDS:-}" ]; then
    yes_msg "Build server requires dependencies:"
    sudo pacman -Sy --needed --noconfirm ${BUILD_DEPENDS}
fi

# Fetch source & cache it

SRC_ARCHIVE="$(basename "$PKG_URL")"
SRC_PATH="${SRC_CACHEDIR}/${SRC_ARCHIVE}"

if [ ! -d "$SRC_PATH" ]; then
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
    if [ -v FLAG_APPIMAGE ] || [ -v FLAG_PREPACKAGED ]; then
	curl -L -o "$SRC_PATH" "$PKG_URL"
    elif [ -v FLAG_GIT ] || [ -v FLAG_NOT_BUNDLEABLE ]; then
	git clone "$PKG_URL" "$SRC_PATH"
    elif [ -v FLAG_BROKEN ]; then
	err_msg "This package has been marked as broken. Please investigate."
    elif [ -v FLAG_DEPRICATED ]; then
	err_msg "This package has been marked as depricated. Shellton can be maintained as long as package is safe and can be built."
    fi    
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
    tar -czf "${PKG_WORK_DIR}/${PKG_FULLNAME}.bundle" -C "$(dirname "$SRC_PATH")" "$(basename "$SRC_PATH")" -C "$PKG_WORK_DIR" "${PKG_NAME}.meta"
    cp "${PKG_WORK_DIR}/${PKG_FULLNAME}.bundle" "${REPO_POOL}/${PKG_FULLNAME}.bundle"
    exit 0
fi

# If pre-packaged, extract

if [ -v FLAG_PREPACKAGED ]; then
    yes_msg "Extracting packaged source..."    
    tar -xf "$SRC_PATH" --one-top-level="${SRC_PATH}.tmp" --strip-components 1
    rm -f "$SRC_PATH"
    mv "${SRC_PATH}.tmp" "$SRC_PATH"
fi


# If SYSPACKAGE, build

if [ -v FLAG_SYSPACKAGE ]; then
    yes_msg "Building $PKG_NAME..."
    cd "$SRC_PATH"
    build
    BLD_PASS=$?
    if [ $BLD_PASS -ne 0 ]; then
	err_msg "Build failed! Adding to fail_reports.txt"
	echo "[ X ] - $PKG_NAME - $(date '+$Y/%m/%d %-I:%M%P %Z')"
    else
	yes_msg "Build succeeded!"
    fi

    # If FLAG_SYSPACKAGE_INSTALL_ROOT, then package as such
    if [ -v FLAG_SYSPACKAGE_INSTALL_ROOT ]; then
	echo "FLAG_SYSPACKAGE_INSTALL_ROOT" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    fi
    
    echo "PKG_NAME=$PKG_NAME" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_PRETTY=$PKG_PRETTY" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_DESC=$PKG_DESC" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_VER=$PKG_VER" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_CHKSUM=WIP" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    yes_msg "Compressing Syspackage..."
    tar -czf "${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage" -C "$(dirname "$PKG_WORK_DIR")" "${PKG_DEST_DIR}" -C "$PKG_WORK_DIR" "${PKG_NAME}.meta"
    cp "${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage" "${REPO_POOL}/${PKG_FULLNAME}.syspackage"
    exit 0
fi

    
