#!/usr/bin/env bash

# Builder rewrite following updated outlines.

source shellton_config

# Functions

stamp_time() {
    elapsed_time=$(( end_timestamp - init_timestamp ))
    elapsed_mins=$(( elapsed_time / 60 ))
    elapsed_secs=$(( elapsed_time % 60 ))
    final_time=$(printf "%02d:%02d" "$elapsed_mins" "$elapsed_secs")
}

err_msg() {
    echo -e "\033[31m[!!!]\033[0m $1"
}

info_msg() {
    echo -e "\033[0;32m[:::]\033[0m $1"
}

write_log_pass() {
    end_timestamp=$(date +%s)
    stamp_time
    echo "[ PASS ]: ' $PKG_NAME ' took [ $final_time ]" >> "$SHELLTON_LOG_DIR/build.log"
}

write_log_fail() {
    end_timestamp=$(date +%s)
    stamp_time
    echo "[ FAIL ]: ' $PKG_NAME ' failed at [ $fail_step ] and took [ $final_time ]" >> "$SHELLTON_LOG_DIR/build.log"
}

# If run without a shellton, error
if [ "$#" -ne 1 ]; then
    echo "Usage: builder.sh <pkg-name>.shellton"
    echo "If you're seeing this, you should probably be running Shellton.sh"
    exit 1
fi

SHELLTON_PATH="$(realpath "$1")"
if [ ! -f "$SHELLTON_PATH" ]; then
    fail_step="Locating Shellton"
    write_log_fail
    exit 1
fi

info_msg "Loading Shellton - $SHELLTON_PATH"
source "$SHELLTON_PATH"

# Check that everything's here
: "${PKG_NAME:?Shellton missing PKG_NAME}"
: "${PKG_VER:?Shellton missing PKG_VER}"
: "${PKG_URL:?Shellton missing PKG_URL}"

PKG_FULLNAME="${PKG_NAME}-${PKG_VER}"
PKG_WORK_DIR="${SHELLTON_WORK_DIR}/${PKG_FULLNAME}"
PKG_DEST_DIR="${PKG_WORK_DIR}/dest"

# Create all the directories (specific to the package)
mkdir -p "$PKG_WORK_DIR" "$PKG_DEST_DIR"

info_msg "Starting build for '${PKG_FULLNAME}'..."

# Fetch source

SRC_ARCHIVE="$(basename "$PKG_URL")"
SRC_PATH="${SHELLTON_CACHE_DIR}/${SRC_ARCHIVE}"

if [ ! -d "$SRC_PATH" ]; then
    # Check upstream distribution

    if [ -v FLAG_APPIMAGE ]; then
	info_msg "Fetching latest AppImage..."
    elif [ -v FLAG_PREPACKAGED ]; then
	info_msg "Fetching latest tarball..."
    else
	info_msg "Fetching latest source..."
    fi

    if ! curl --output /dev/null --silent --head --fail --location "$PKG_URL"; then
	err_msg "Failed to fetch PKG_URL."
	fail_step="Fetching PKG_URL"
	write_log_fail
	exit 1
    fi

    if [ -v FLAG_APPIMAGE ] || [ -v FLAG_PREPACKAGED ]; then
	curl -L -o "$SRC_PATH" "$PKG_URL"
    elif [ -v FLAG_GIT ]; then
	git clone "$PKG_URL" "$SRC_PATH"
    fi
else
    info_msg "Found in cache: $SRC_ARCHIVE"
fi

if [ -f "${SHELLTON_PKG_DIR}/${PKG_FULLNAME}.syspackage" ] && [ ! -f "${SHELLTON_UPDATES_DIR}/.${PKG_NAME}" ]; then
    info_msg "Package already built and has no updates. Skipping..."
    # Don't need to log this
    exit 0
fi

if [ -f "${SHELLTON_UPDATES_DIR}/.${PKG_NAME}" ]; then
    UPDATE_REQUIRED=1
    info_msg "Update being forced for $PKG_NAME..."
fi

if [ -v FLAG_APPIMAGE ]; then
    err_msg "Not yet implemented"
    exit 1
fi

# Extract tarball

if [ -v FLAG_PREPACKAGED ]; then
    if [ -d "$SRC_PATH" ]; then
	info_msg "Skipping extraction"
    elif [ -f "$SRC_PATH" ]; then
	info_msg "Extracting..."
	tar -xf "$SRC_PATH" --one-top-level="${SRC_PATH}.tmp" --strip-components 1
	rm -f "$SRC_PATH"
	mv "${SRC_PATH}.tmp" "$SRC_PATH"
    fi
fi

if [ -v FLAG_COREPACKAGE ]; then
    info_msg "Building $PKG_NAME as Corepackage..."
    cd "$SRC_PATH"
    build
    BLD_PASS=$?
    if [ $BLD_PASS -ne 0 ]; then
	err_msg "Build failed!"
	fail_step="Building package"
	write_log_fail
	exit 1
    else
	info_msg "Build OK"
    fi

    if [ -v FLAG_LIRA_LOWLEVEL ]; then
	cp "${PKG_DEST_DIR}/${PKG_NAME}.syspackage" "${SHELLTON_PKG_DIR}/"
	write_log_pass
	exit 0
    fi
    
    unset LD_LIBRARY_PATH # Do this so things don't break

    info_msg "Sanitizing package directories..."

    for stray in lib lib64 bin sbin; do
	if [ -d "${PKG_DEST_DIR}/$stray" ]; then
	    echo "  -> Moving /$stray to /usr/$stray"
	    mkdir -p "${PKG_DEST_DIR}/usr/$stray"
	    cp -a "${PKG_DEST_DIR}/$stray/." "${PKG_DEST_DIR}/usr/$stray/"
	    rm -rf "${PKG_DEST_DIR}/$stray"
	fi
    done

    info_msg "Compressing corepackage"
    tar -I 'zstd --ultra -22' -cf "${PKG_WORK_DIR}/${PKG_FULLNAME}.corepackage" -C "$PKG_DEST_DIR" .

    # Create meta and remove if it already exists
    rm -f "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_NAME=$PKG_NAME" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_PRETTY=$PKG_PRETTY" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_DESC=$PKG_DESC" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_VER=$PKG_VER" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_CHKSUM=$(sha512sum ${PKG_WORK_DIR}/${PKG_FULLNAME}.corepackage | head -c 128)" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    cp "${PKG_WORK_DIR}/${PKG_FULLNAME}.corepackage" "${SHELLTON_PKG_DIR}/${PKG_FULLNAME}.corepackage"

    info_msg "Sucessfully built corepackage for $PKG_NAME. Cleaning up..."
    write_log_pass
    rm -rf "${SRC_PATH}" "${PKG_WORK_DIR}"
    if [ -v UPDATE_REQUIRED ]; then
	rm -f "${SHELLTON_UPDATES_DIR}/.${PKG_NAME}"
    fi
    exit 0
fi

if [ -v FLAG_SYSPACKAGE ]; then
    info_msg "Building $PKG_NAME as Syspackage..."
    cd "$SRC_PATH"
    export CFLAGS="-I${SHELLTON_SYSLIB_DIR}/include"
    export LDFLAGS="-L${SHELLTON_SYSLIB_DIR}/lib"
    build
    BLD_PASS=$?
    if [ $BLD_PASS -ne 0 ]; then
	err_msg "Build failed!"
	fail_step="Building package"
	write_log_fail
	exit 1
    else
	info_msg "Build OK"
    fi

    info_msg "Fetching dependencies..."
    dest_bin="${PKG_DEST_DIR}/opt/syspackages/${PKG_NAME}-${PKG_VER}/bin"
    dest_lib="${PKG_DEST_DIR}/opt/syspackages/${PKG_NAME}-${PKG_VER}/lib"
    dest_libexec="${dest_lib}/${PKG_NAME}"

    mkdir -p "$dest_lib"

    find "$dest_bin" "$dest_libexec" -type f 2>/dev/null | while read -r binary; do
	if ! readelf -h "$binary" >/dev/null 2>&1; then continue; fi
	info_msg "  -> Checking $(basename "$binary")"
	readelf -d "$binary" 2>/dev/null | grep NEEDED | awk -F'[' '{print $2}' | tr -d ']' | while read -r lib; do
	    case "$lib" in
		libc.so*|libm.so*|libdl.so*|libpthread.so*|librt.so*|ld-linux*.so*) continue ;;
	    esac
	    lib_path=$(find "$SHELLTON_SYSLIB_DIR" -name "$lib" \( -type f -o -type 1 \) | head -n 1)

	    if [ -n "$lib_path" ] && [ -f "$lib_path" ]; then
		if [ ! -f "$dest_lib/$(basename "$lib_path")" ]; then
		    info_msg "  -* Bundling $lib ($lib_path)"
		    cp -P "$lib_path" "$dest_lib/"
		    [ -L "$lib_path" ] && cp -P "$(readlink -f "$lib_path")" "$dest_lib/"
		fi
	    else
		err_msg "  -* Couldn't locate dependency '$lib' in SYSLIB"
		fail_step="Bundling dependencies"
		write_log_fail
		exit 1
	    fi
	done
	info_msg "Patching binary(s)..."
	case "$binary" in
	    "$dest_bin"/*)      rpath='$ORIGIN/../lib' ;;
	    "$dest_libexec"/*)  rpath='$ORIGIN/../..'  ;;
	    *) continue ;;
	esac
	patchelf --force-rpath --set-rpath "$rpath" "$binary"
    done
    info_msg "Compressing Syspackage..."
    unset LD_LIBRARY_PATH
    tar -I 'zstd --ultra -22' -cf "${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage" -C "$PKG_DEST_DIR" .

    # Create meta and remove if it already exists
    rm -f "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_NAME=$PKG_NAME" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_PRETTY=$PKG_PRETTY" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_DESC=$PKG_DESC" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_VER=$PKG_VER" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    echo "PKG_CHKSUM=$(sha512sum ${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage | head -c 128)" >> "${SHELLTON_META_DIR}/$PKG_NAME.meta"
    cp "${PKG_WORK_DIR}/${PKG_FULLNAME}.syspackage" "${SHELLTON_PKG_DIR}/${PKG_FULLNAME}.syspackage"

    info_msg "Sucessfully build Syspackage for ${PKG_NAME}. Cleaning up..."
    write_log_pass
    rm -rf "${SRC_PATH}" "${PKG_WORK_DIR}"
    if [ -v UPDATE_REQUIRED ]; then
	rm -f "${SHELLTON_UPDATES_DIR}/.${PKG_NAME}"
    fi
    exit 0
fi

if [ -v FLAG_LIB ]; then
    info_msg "Building library $PKG_NAME->SYSLIB & $PKG_NAME-dev"
    if [ -f "${SHELLTON_SYSLIB_DIR}/.${PKG_NAME}" ] && [ -f "${SHELLTON_PKG_DIR}/${PKG_FULLNAME}-dev.library" ]; then
       alr_built=$(cat "${SHELLTON_SYSLIB_DIR}/.${PKG_NAME}")
       if [ "$alr_built" = "$PKG_VER" ]; then
	   info_msg "Already built to SYSLIB and -dev with no updates found. Skipping..."
	   exit 0
       fi
    fi
    cd "$SRC_PATH"
    build
    BLD_PASS=$?
    if [ $BLD_PASS -ne 0 ]; then
	err_msg "Build failed!"
	fail_step="Building library"
	write_log_fail
	exit 1
    else
	info_msg "Build OK"
    fi

    mkdir -p "${SHELLTON_SYSLIB_DIR}/lib" "${SHELLTON_SYSLIB_DIR}/include"

    if [ -v FLAG_SYSLIB_ONLY ]; then
	find "$PKG_DEST_DIR" -type d \( -name "include" -o -name "lib" -o -name "lib64" \) | while read -r dir; do
	    if [[ "$dir" == */include ]]; then
		cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/include" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/include/" 2>/dev/null || true
	    elif [[ "$dir" == */lib ]]; then
		cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/lib" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/lib/" 2>/dev/null || true
	    elif [[ "$dir" == */lib64 ]]; then
		cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/lib64" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/lib64/" 2>/dev/null || true
	    fi
	done
	echo "$PKG_VER" > "${SHELLTON_SYSLIB_DIR}/.${PKG_NAME}"
	info_msg "Registered $PKG_NAME into SYSLIB"
	write_log_pass
	rm -rf "${SRC_PATH}" "${PKG_WORK_DIR}"
	if [ -v UPDATE_REQUIRED ]; then
	    rm -f "${SHELLTON_UPDATES_DIR}/.${PKG_NAME}"
	fi
	exit 0
    fi
    find "$PKG_DEST_DIR" -type d \( -name "include" -o -name "lib" -o -name "lib64" \) | while read -r dir; do
	if [[ "$dir" == */include ]]; then
	    mkdir -p "${PKG_DEST_DIR}/devinclude"
	    cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/include" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/include/" 2>/dev/null || true
	    cp -a "$dir"/.* "${PKG_DEST_DIR}/devinclude" 2>/dev/null || cp -a "$dir"/* "${PKG_DEST_DIR}/devinclude/" 2>/dev/null || true
	elif [[ "$dir" == */lib ]]; then
	    mkdir -p "${PKG_DEST_DIR}/devlib"
	    cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/lib" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/lib/" 2>/dev/null || true
	    cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/devlib" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/devlib/" 2>/dev/null || true
	elif [[ "$dir" == */lib64 ]]; then
	    mkdir -p "${PKG_DEST_DIR}/devlib64"
	    cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/lib64" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/lib64/" 2>/dev/null || true
	    cp -a "$dir"/.* "${SHELLTON_SYSLIB_DIR}/devlib64" 2>/dev/null || cp -a "$dir"/* "${SYSLIB_PATH}/devlib64/" 2>/dev/null || true
	fi
    done
    echo "$PKG_VER" > "${SHELLTON_SYSLIB_DIR}/.${PKG_NAME}"
    info_msg "Registered $PKG_NAME into SYSLIB, compressing $PKG_NAME-dev Libbundle..."
    INCL_LIBRARIES=$(ls "${PKG_DEST_DIR}" | grep "dev")
    tar -I 'zstd --ultra -22' -cf "${PKG_WORK_DIR}/${PKG_NAME}-dev.$PKG_VER.libbundle" -C $INCL_LIBRARIES
    
    # Create meta and remove if it already exists
    rm -f "${SHELLTON_META_DIR}/$PKG_NAME-dev.meta"
    echo "PKG_NAME=$PKG_NAME-dev" >> "${SHELLTON_META_DIR}/$PKG_NAME-dev.meta"
    echo "PKG_PRETTY=$PKG_PRETTY" >> "${SHELLTON_META_DIR}/$PKG_NAME-dev.meta"
    echo "PKG_DESC=$PKG_DESC" >> "${SHELLTON_META_DIR}/$PKG_NAME-dev.meta"
    echo "PKG_VER=$PKG_VER" >> "${SHELLTON_META_DIR}/$PKG_NAME-dev.meta"
    echo "PKG_CHKSUM=$(sha512sum ${PKG_WORK_DIR}/${PKG_NAME}-dev.$PKG_VER.libbundle | head -c 128)" >> "${SHELLTON_META_DIR}/$PKG_NAME-dev.meta"
    cp "${PKG_WORK_DIR}/${PKG_NAME}-dev.$PKG_VER.syspackage" "${SHELLTON_PKG_DIR}/${PKG_NAME}-dev.$PKG_VER.libbundle"
    info_msg "Packaged $PKG_NAME-dev libbundle sucessfully. Cleaning up..."
    write_log_pass
    rm -rf "${SRC_PATH}" "${PKG_WORK_DIR}"
    if [ -v UPDATE_REQUIRED ]; then
	rm -f "${SHELLTON_UPDATES_DIR}/.${PKG_NAME}"
    fi
    exit 0
fi
