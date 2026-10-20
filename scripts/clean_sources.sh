#!/usr/bin/env bash

echo "This will *DELETE* the following folders:"
echo "  - /srv/shellton/source"
echo "  - /srv/shellton/working"
echo ""
read -p  "Are you *SURE* you want to continue? (y/n)" yn

case $yn in
    [yY] )
	sudo rm -rf "/srv/shellton/source" "/srv/shellton/working"
	;;
    [nN] )
	echo "Aborted."
	;;
esac
