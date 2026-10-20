#!/usr/bin/env bash

# The Shellton Build System - Seth McArthur, 2026

# Create Build Queue

SHELLTON_LOCATION=$(pwd)
REPO_LOCATION=$(cat ../repos/shellton.repo)
PKGCOUNT=0

cd "$REPO_LOCATION"

read -p "Clear update queue? (y\n)" yn

case $yn in
    [yY] )
	rm -f "${REPO_LOCATION}/.UPDATE_QUEUE"
	;;
    [nN] )
	;;
esac


# See how many packages there are
while IFS= read -r file; do
    tmp_pkg_name=$(basename "$file" .shellton)
    echo "Found Package [ $tmp_pkg_name ]"
    ((PKGCOUNT++))
done < <(find . -type f -name "*.shellton")

echo "$PKGCOUNT Packages found in REPO: $REPO_LOCATION"

echo "Searching for package updates..."

while IFS= read -r file; do
    tmp_pkg_name=$(basename "$file" .shellton)
    bash "${SHELLTON_LOCATION}/updater.sh" "${file}"
    ec=$?
    if [ $ec -eq 12 ]; then
	echo "Placing [ $tmp_pkg_name ] in update queue to be rebuilt..."
	echo "${file}" >> "${REPO_LOCATION}/.UPDATE_QUEUE"
    fi
    if [ $ec -eq 10 ]; then
	echo "No updates for [ $tmp_pkg_name ], skipping..."
    fi
    if [ -f "${REPO_LOCATION}/.FORCEBUILD" ]; then
	echo "!! Force Build Enabled, building all packages !!"
	echo "${file}" >> "${REPO_LOCATION}/.UPDATE_QUEUE"
    fi
    
done < <(find "${REPO_LOCATION}" -type f -name "*.shellton")

echo "Finished checking packages, running build queue..."

while IFS= read -r buildjob; do
    bash ${SHELLTON_LOCATION}/builder.sh "$buildjob"
done < "${REPO_LOCATION}/.UPDATE_QUEUE"
