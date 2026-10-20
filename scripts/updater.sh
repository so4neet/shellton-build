#!/usr/bin/env bash

# Updater for Shellton Build System

source "$1"

if declare -F update >/dev/null; then
    echo "Checking $PKG_NAME for updates..."
    ST_PATH="$1"
    echo "DEBUG:: Checking for package built in repo"
    
    update
    if [ -v "$FLAG_OOD" ]; then
	echo -e "\033[31m[ !!! ]\033[0m $PKG_NAME needs updated \033[31m[ !!! ]\033[0m"
	exit 12 # Exit code for update
    fi
    exit 10
fi
