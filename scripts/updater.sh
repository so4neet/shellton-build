#!/usr/bin/env bash

# Updater for Shellton Build System

source "$1"

if declare -F update >/dev/null; then
    echo "Checking $PKG_NAME for updates..."
    echo "Set ST_PATH= $1"
    ST_PATH="$1"
    if compgen -G "/srv/shellton/repository/final/"/*"$PKG_NAME"*/ > /dev/null; then
	FLAG_OOD=1
    fi
    
    update
    if [ -v "$FLAG_OOD" ]; then
	echo -e "\033[31m[ !!! ]\033[0m $PKG_NAME needs updated \033[31m[ !!! ]\033[0m"
	exit 12 # Exit code for update
    fi
    exit 10
fi
