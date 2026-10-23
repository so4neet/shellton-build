#!/usr/bin/env bash
set -eo pipefail

REPO_DIR="$(cat ../repos/shellton.repo)"
SCRIPTS_DIR="$(pwd)"

declare -a queued_shelltons=()
while IFS= read -r -d '' shellton; do
    queued_shelltons+=("$shellton")
done < <(find "$REPO_DIR" -name "*.shellton" -type f -print0)

if [ ${#queued_shelltons[@]} -eq 0 ]; then
    echo "[X] No shelltons found in $REPO_DIR!"
    exit 1
fi

echo "[ ::: ] Starting dynamic build queue for ${#queued_shelltons[@]} packages contained in $REPO_DIR..."
echo ""
echo "5 Second grace period..."
sleep 5

while [ ${#queued_shelltons[@]} -gt 0 ]; do
    progress_made=0
    declare -a next_remaining=()

    for shellton in "${queued_shelltons[@]}"; do
	pkg_basename=$(basename "$shellton")
	echo "[ ::: ] Evaluating: $pkg_basename ($recipe)"
	
	if bash "$SCRIPTS_DIR/builder.sh $shellton"; then
	    progress_made=1
	    echo "[ ::: ] Completed / Skipped: $pkg_basename"
	else
	    next_remaining+=("$shellton")
	fi
    done

    if [ $progress_made -eq 0 ]; then
	echo ""
	echo "[X] - Build Init Fail: Missing or Circular Dependency"
	for r in "${next_remaining[@]}"; do
	    echo "    - ($r)"
	done
	exit 1
    fi

    queued_shelltons=("${next_remaining[@]}")
done

echo ""
echo "[ ::: ] Build complete!"

