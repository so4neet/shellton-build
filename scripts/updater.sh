#!/usr/bin/env bash

# Updater for Shellton Build System

source "$1"
source shellton_config

if declare -F update >/dev/null; then
    echo "Checking $PKG_NAME for updates..."
    ST_PATH="$1"
    update
    if [ -v "$FLAG_OOD" ]; then
	echo -e "\033[31m[ !!! ]\033[0m $PKG_NAME needs updated \033[31m[ !!! ]\033[0m"
	touch "${SHELLTON_UPDATES_DIR}/.$PKG_NAME"
    fi
    exit 0
fi
