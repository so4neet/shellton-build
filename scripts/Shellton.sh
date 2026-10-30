#!/usr/bin/env bash

err_msg() {
    echo -e "\033[31m[ X ]\033[0m $1"
}

yes_msg() {
    echo -e "\033[0;32m[:::]\033[0m $1"
}

warn_msg() {
    echo -e "\033[33m[ ! ]\033[0m $1"
}


set -eo pipefail

BLDR_ROOT="/srv/shellton"
REPO_DIR=$(cat ../repos/shellton.repo)

yes_msg "Using repository: $REPO_DIR"

declare -A SHELLTON_MAP=()
declare -A DEPENDS_MAP=() # -> BUILD_DEPENDS
ALL_PKGS=()

while IFS= read -r -d '' shellton; do
    eval $(
	unset PKG_NAME PKG_PRETTY PKG_DESC PKG_VER PKG_URL BUILD_DEPENDS FLAG_GIT FLAG_COREPACKAGE FLAG_LIB FLAG_SYSPACKAGE FLAG_APPIMAGE FLAG_PREPACKAGED
	bash updater.sh "$shellton"
	source "$shellton"
	
	if [ -n "${PKG_NAME:-}" ]; then
	    echo "extracted_name=\"$PKG_NAME\""
	    echo "extracted_deps=\"${BUILD_DEPENDS:-}\""
	fi
    )
    if [ -n "${extracted_name:-}" ]; then
	SHELLTON_MAP["$extracted_name"]="$shellton"
	DEPENDS_MAP["$extracted_name"]="$extracted_deps"
	ALL_PACKAGES+=("$extracted_name")
	echo "  -> Discovered package: $extracted_name ($shellton)"
    fi
done < <(find "$REPO_DIR" -type f -name "*.shellton" -print0)

declare -A STATE=() # 0 = unvisited, 1 = visiting (cycles), 2 = visited
BUILD_ORDER=()

visit() {
    local pkg="$1"

    if [ "${STATE[$pkg]:-0}" -eq 2 ]; then
	return 0
    fi
    
    if [ "${STATE[$pkg]:-0}" -eq 1 ]; then
	err_msg "Circular dependency detected involving package: $pkg"
	exit 1
    fi

    STATE[$pkg]=1

    local deps="${DEPENDS_MAP[$pkg]:-}"
    for dep in $deps; do
	if [ -n "${SHELLTON_MAP[$dep]:-}" ]; then
	    visit "$dep"
	else
	    warn_msg "Dependency '$dep' requested by '$pkg' not found in repo recipes (assumed external)."
	fi
    done

    STATE[$pkg]=2
    BUILD_ORDER+=("$pkg")
}

yes_msg "Resolving global build order..."
for pkg in "${ALL_PACKAGES[@]}"; do
    visit "$pkg"
done

echo ""
yes_msg "Resolved build queue:"
for i in "${!BUILD_ORDER[@]}"; do
    yes_msg "  $((i+1)). ${BUILD_ORDER[$i]}"
done

echo ""
yes_msg "Starting automated build for $REPO_DIR"

for pkg in "${BUILD_ORDER[@]}"; do
    shellton="${SHELLTON_MAP[$pkg]}"
    echo "=================================================="
    echo " Shellton: $shellton"
    echo " Logging to /srv/shellton/logs/$pkg.log"
    echo "=================================================="

    ./builder.sh "$shellton" > /srv/shellton/logs/$pkg.log 2>&1
    echo ""
done

yes_msg "Finished automated build for $REPO_DIR"
