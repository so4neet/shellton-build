#!/usr/bin/env bash

init_timestamp=$(date +%s)

grab_final_time() {
    elapsed_time=$(( final_timestamp - init_timestamp ))
    elapsed_mins=$(( elapsed_time / 60 ))
    elapsed_secs=$(( elapsed_time % 60 ))
    final_time="${elapsed_mins}:${elapsed_secs}"
}

err_msg() {
    echo -e "\033[31m[ X ]\033[0m $1"
}

yes_msg() {
    echo -e "\033[0;32m[:::]\033[0m $1"
}

write_log_pass() {
    grab_final_time
    echo "[ $PKG_NAME ]: Build PASS in $final_time" >> "${REPO_POOL}/repobuild.log"
}

write_log_fail() {
    grab_final_time
    echo "[ $PKG_NAME ]: Build FAILED at $final_time during $fail_step" >>"${REPO_POOL}/repobuild.log"
}
    
set -eo pipefail

# Paths

BLDR_ROOT="/srv/shellton"
WORK_DIR="${BLDR_ROOT}/working"
REPO_POOL="${BLDR_ROOT}/repository"
META_POOL="${BLDR_ROOT}/meta"

# This needs a file input, so error if not
if [ "$#" -ne 1 ]; then
    echo "Usage: ./builder.sh <pkg-name>.shellton"
    echo ""
    echo "This script is typically only run standalone for new packages / debugging."
    exit 1
fi

SHELLTON_PATH="$(realpath "$1")"
if [ ! -f "$SHELLTON_PATH" ]; then
    fail_step="Finding Shellton."
    err_msg "Couldn't locate Shellton file at $SHELLTON_PATH"
    final_timestamp=$(date +%s)
    write_log_fail
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
SYSLIB_PATH="${BLDR_ROOT}/syslib"

# Create the working directories

mkdir -p "$PKG_WORK_DIR" "$PKG_DEST_DIR" "$SRC_CACHEDIR" "$REPO_POOL" "$SYSLIB_PATH"

# Copy over the Shellton file so the sandbox can see it

LOCAL_SHELLTON="${PKG_WORK_DIR}/tmp.shellton"
cp "$SHELLTON_PATH" "$LOCAL_SHELLTON"

yes_msg "Starting build for '${PKG_FULLNAME}'..."

# Check if any dependencies need to be installed

#if [ -n "${BUILD_DEPENDS:-}" ]; then
#    yes_msg "Build server requires dependencies:"
#    sudo pacman -Sy --needed --noconfirm ${BUILD_DEPENDS}
#fi

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
	final_timestamp=$(date +%s)
	fail_step="Fetching PKG_URL."
	write_log_fail
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

if [ -f "${REPO_POOL}/${PKG_FULLNAME}.bundle" ] || [ -f "${REPO_POOL}/${PKG_FULLNAME}.syspackage" ]; then
    yes_msg "Package already built/bundled, skipping..."
    exit 0
fi


# If AppImage, then just move to final step

if [ -v FLAG_APPIMAGE ]; then
    yes_msg "Bundling AppImage..."
    cp "$SRC_PATH" "$PKG_WORK_DIR"
    yes_msg "Compressing Bundle..."
    tar -czf "${PKG_WORK_DIR}/${PKG_FULLNAME}.bundle" -C "$(dirname "$SRC_PATH")" "$(basename "$SRC_PATH")"
    echo "PKG_NAME=$PKG_NAME" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_PRETTY=$PKG_PRETTY" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_DESC=$PKG_DESC" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_VER=$PKG_VER" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_CHKSUM=$(sha512sum $SRC_PATH | head -c 128)" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    cp "${PKG_WORK_DIR}/${PKG_FULLNAME}.bundle" "${REPO_POOL}/${PKG_FULLNAME}.bundle"
    cp "${PKG_WORK_DIR}/${PKG_NAME}.bundle" "${META_POOL}/${PKG_NAME}.meta"
    exit 0
fi

# If pre-packaged, extract

if [ -v FLAG_PREPACKAGED ]; then
    if [ -d "$SRC_PATH" ]; then
	yes_msg "Skipping extraction due to cached source..."
    elif [ -f "$SRC_PATH" ]; then
	yes_msg "Extracting packaged source..."    
	tar -xf "$SRC_PATH" --one-top-level="${SRC_PATH}.tmp" --strip-components 1
	rm -f "$SRC_PATH"
	mv "${SRC_PATH}.tmp" "$SRC_PATH"
    fi
fi



# If COREPACKAGE, build

if [ -v FLAG_COREPACKAGE ]; then
    yes_msg "Building $PKG_NAME..."
    cd "$SRC_PATH"
    build
    BLD_PASS=$?
    if [ $BLD_PASS -ne 0 ]; then
	err_msg "Build failed!"
	fail_step="Bulding Package."
	final_timestamp=$(date +%s)
	write_log_fail
	exit 1
    else
	yes_msg "Build succeeded!"
    fi

    if [ -v FLAG_LIRA_LOWLEVEL ]; then
	cp "${PKG_DEST_DIR}/${PKG_NAME}.syspackage" "${REPO_POOL}/"
	exit 0
    fi
   
    yes_msg "Compressing Corepackage..."
    env -u LD_LIBRARY_PATH
    tar -czf "${PKG_WORK_DIR}/${PKG_FULLNAME}.corepackage" -C "$PKG_DEST_DIR" . 
    echo "PKG_NAME=$PKG_NAME" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_PRETTY=$PKG_PRETTY" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_DESC=$PKG_DESC" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_VER=$PKG_VER" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_CHKSUM=$(sha512sum ${PKG_WORK_DIR}/${PKG_FULLNAME}.corepackage | head -c 128)" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    cp "${PKG_WORK_DIR}/${PKG_FULLNAME}.corepackage" "${REPO_POOL}/${PKG_FULLNAME}.syspackage"
    cp "${PKG_WORK_DIR}/${PKG_NAME}.meta" "${META_POOL}/${PKG_NAME}.meta"
    yes_msg "Sucessfully built corepackage for $PKG_NAME! Cleaning up..."
    final_timestamp=$(date +%s)
    write_log_pass
    sudo rm -rf "${SRC_PATH}" "${PKG_WORK_DIR}"
    exit 0
fi

    
# If SYSPACKAGE, build

if [ -v FLAG_SYSPACKAGE ]; then
    yes_msg "Building $PKG_NAME..."
    cd "$SRC_PATH"
    export CFLAGS="-I${SYSLIB_PATH}/include"
    export LDFLAGS="-L${SYSLIB_PATH}/lib"
    build
    BLD_PASS=$?
    if [ $BLD_PASS -ne 0 ]; then
	err_msg "Build failed!"
	fail_step="Building package"
	final_timestamp=$(date +%s)
	write_log_fail
	exit 1
    else
	yes_msg "Build succeeded!"
    fi
    
    yes_msg "Fetching dependencies..."
    dest_bin="${PKG_DEST_DIR}/opt/syspackages/${PKG_NAME}-${PKG_VER}/bin"
    dest_lib="${PKG_DEST_DIR}/opt/syspackages/${PKG_NAME}-${PKG_VER}/lib"
    dest_libexec="${PKG_DEST_DIR}/opt/syspackages/${PKG_NAME}-${PKG_VER}/lib/${PKG_NAME}"

    mkdir -p "$dest_lib"

    find "$dest_bin" "$dest_libexec" -type f 2>/dev/null | while read -r binary; do
	if ! readelf -h "$binary" >/dev/null 2>&1; then continue; fi
	yes_msg "    > Checking $(basename "$binary")"

	readelf -d "$binary" 2>/dev/null | grep NEEDED | awk -F'[' '{print $2}' | tr -d ']' | while read -r lib; do
	    case "$lib" in
		libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|ld-linux*.so*) continue ;; # Skip all system level libs
	    esac
	    lib_path=$(find "$SYSLIB_PATH/lib" -name "$lib" \( -type f -o -type l \) | head -n 1)

	    if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
	        if [ ! -f "$dest_lib/$(basename "$lib_path")" ]; then
		    yes_msg "    * Bundling $lib ($lib_path)"
		    cp -P "$lib_path" "$dest_lib/"
		    [ -L "$lib_path" ] && cp -P "$(readlink -f "$lib_path")" "$dest_lib/"
		fi
	    else
		err_msg "    [ X ] Couldn't find dependency '$lib' in syslib"
		fail_step="Fetch dependency from syslib"
		final_timestamp=$(date +%s)
		write_log_fail
		exit 1
	    fi
	done
	yes_msg "Patching binary..."
	case "$binary" in
	    "$dest_bin"/*)      rpath='$ORIGIN/../lib' ;;
	    "$dest_libexec"/*)  rpath='$ORIGIN/../..' ;;
	    *) continue ;;
	esac
	patchelf --force-rpath --set-rpath "$rpath" "$binary"
    done
    # Patch libs as well so they can locate each other locally (if needed)
    if [ -d "$dest_lib" ]; then
	find "$dest_lib" -name "*.so" -type f | while read -r so_file; do
	    if ! readelf -h "$binary" >/dev/null 2>&1; then continue; fi
	    patchelf --force-rpath --set-rpath '$ORIGIN' "$so_file" 2>/dev/null || true
	done
    fi  
    yes_msg "Compressing Syspackage..."
    env -u LD_LIBRARY_PATH
    tar -I 'zstd --ultra -22' -cf "${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage" -C "$PKG_DEST_DIR" .
    echo "PKG_NAME=$PKG_NAME" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_PRETTY=$PKG_PRETTY" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_DESC=$PKG_DESC" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_VER=$PKG_VER" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    echo "PKG_CHKSUM=$(sha512sum ${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage | head -c 128)" >> ${PKG_WORK_DIR}/${PKG_NAME}.meta
    cp "${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage" "${REPO_POOL}/${PKG_FULLNAME}.syspackage"
    cp "${PKG_WORK_DIR}/${PKG_NAME}.meta" "${META_POOL}/${PKG_NAME}.meta"
    yes_msg "Sucessfully built syspackage for ${PKG_NAME}! Cleaning up..."
    final_timestamp=$(date +%s)
    write_log_pass
    sudo rm -rf "${SRC_PATH}" "${PKG_WORK_DIR}"
    exit 0
fi

if [ -v FLAG_LIB ]; then
    yes_msg "Building library $PKG_NAME..."
    if [ -f "${SYSLIB_PATH}/.${PKG_NAME}" ]; then
	alr_built=$(cat "${SYSLIB_PATH}/.${PKG_NAME}")
	if [ "$alr_built" = "$PKG_VER" ]; then
	    yes_msg "Already built dependency and no updates found, skipping..."
	    exit 0
	fi
    fi
    cd "$SRC_PATH"
    build
    BLD_PASS=$?
    if [ $BLD_PASS -ne 0 ]; then
	err_msg "Build failed!"
	fail_step="Building Library"
	final_timestamp=$(date +%s)
	write_log_fail
	exit 1
    else
	yes_msg "Build succeeded!"
    fi

    mkdir -p "${SYSLIB_PATH}/lib" "${SYSLIB_PATH}/include"

    find "$PKG_DEST_DIR" -type d \( -name "include" -o -name "lib" -o -name "lib64" \) | while read -r dir; do
	if [[ "$dir" == */include ]]; then
	    cp -a "$dir"/.* "${SYSLIB_PATH}/include/" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/include/" 2>/dev/null || true
	elif [[ "$dir" == */lib ]]; then
	    cp -a "$dir"/.* "${SYSLIB_PATH}/lib/" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/lib/" 2>/dev/null || true
	elif [[ "$dir" == */lib64 ]]; then
	    cp -a "$dir"/.* "${SYSLIB_PATH}/lib64/" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/lib64" 2>/dev/null || true
	fi
    done
    echo "$PKG_VER" > "${SYSLIB_PATH}/.${PKG_NAME}"
    yes_msg "Registered $PKG_NAME into syslibs, cleaning up..."
    final_timestamp=$(date +%s)
    write_log_pass
    sudo rm -rf "${SRC_PATH}" "${PKG_WORK_DIR}"
    exit 0
fi

