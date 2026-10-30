#!/bin/bash
set -e

IMAGE_SIZE_MB=1024
REPO_DIR="/srv/shellton/repository"
BUILD_DIR="/srv/shellton/lira_os_core"
MOUNT_DIR="$BUILD_DIR/mnt"
IMAGE_NAME="$BUILD_DIR/lira_os_core.img"
echo "[:::] Initializing Lira OS Image Builder..."

cleanup() {
    set +e
    sudo umount -lf "$MOUNT_DIR/boot" 2>/dev/null
    sudo umount -lf "$MOUNT_DIR/dev" 2>/dev/null
    sudo umount -lf "$MOUNT_DIR/proc" 2>/dev/null
    sudo umount -lf "$MOUNT_DIR/sys" 2>/dev/null
    sudo umount -lf "$MOUNT_DIR" 2>/dev/null
    if [ -n "$LOOP_DEV" ]; then
	sudo losetup -d "$LOOP_DEV" 2>/dev/null
    fi
}
trap cleanup EXIT
# 1. Prepare Workspace
sudo rm -rf "$BUILD_DIR"
mkdir -p "$MOUNT_DIR"

# 2. Create Raw Disk Image
dd if=/dev/zero of="$IMAGE_NAME" bs=1M count="$IMAGE_SIZE_MB"

# 3. Partition with GPT (ESP + Root)
parted --script "$IMAGE_NAME" \
    mklabel gpt \
    mkpart ESP fat32 1MiB 257MiB \
    set 1 esp on \
    mkpart root ext4 257MiB 100%

# 4. Setup Loop Device
LOOP_DEV=$(sudo losetup --find --show --partscan "$IMAGE_NAME")
ESP_PART="${LOOP_DEV}p1"
ROOT_PART="${LOOP_DEV}p2"

# 5. Format Partitions
sudo mkfs.fat -F32 -n "EFI" "$ESP_PART"
sudo mkfs.ext4 -L "LIRA_ROOT" "$ROOT_PART"

ROOT_UUID=$(sudo blkid -s UUID -o value "$ROOT_PART")

# 6. Mount Filesystems
sudo mount "$ROOT_PART" "$MOUNT_DIR"
sudo mkdir -p "$MOUNT_DIR/boot"
sudo mount "$ESP_PART" "$MOUNT_DIR/boot"

# Rootfs directory skeleton
sudo mkdir -p "$MOUNT_DIR"/{dev,proc,sys,etc,opt/syspackages,opt/spkg,root,home,tmp,var/tmp,usr/bin}
sudo chmod 1777 "$MOUNT_DIR/tmp" "$MOUNT_DIR/var/tmp"

# 7. Populate RootFS exclusively from Shellton Repository packages
echo "[:::] Populating rootfs from Lira OS repository packages..."
if [ -d "$REPO_DIR" ]; then
    for pkg_file in "$REPO_DIR"/*.syspackage; do
        if [ -f "$pkg_file" ]; then
            echo "[:::] Installing package: $(basename "$pkg_file")"
            sudo tar --no-same-owner -I 'zstd' -xf "$pkg_file" -C "$MOUNT_DIR"
        fi
    done
else
    echo "[!] Error: Repository directory $REPO_DIR not found!"
    exit 1
fi

echo "[:::] Symlinking step..."

if [ -d "$MOUNT_DIR/opt/syspackages" ]; then
    for pkg_dir in "$MOUNT_DIR"/opt/syspackages/*; do
	if [ -d "$pkg_dir/bin" ]; then
	    pkg_name=$(basename "$pkg_dir")
	    echo "[:::] Processing syspackage bin dir: $pkg_name"

	    for bin_file in "$pkg_dir/bin"/*; do
		if [ -f "$bin_file" ] && [ -x "$bin_file" ]; then
		    bin_name=$(basename "$bin_file")
		    sudo ln -sf "/opt/syspackages/$pkg_name/bin/$bin_name" "$MOUNT_DIR/usr/bin/$bin_name"
		    echo "  -> Linked: /usr/bin/$bin_name -> /opt/syspackages/$pkg_name/bin/$bin_name"
		fi
	    done
	fi
    done
fi

sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/getty.target.wants"
sudo ln -sfn usr/bin "$MOUNT_DIR/bin"
sudo ln -sfn usr/sbin "$MOUNT_DIR/bin"
sudo ln -sfn /usr/lib/systemd/systemd "$MOUNT_DIR/usr/bin/init"
sudo ln -sfn /usr/lib/systemd/system/getty@.service "$MOUNT_DIR/etc/systemd/system/getty.target.wants/getty@tty1.service"

sudo chmod 600 shadow
sudo chmod 600 gshadow

echo "[:::] Generating initramfs"
KERNEL_VER=""
if [ -d "$MOUNT_DIR/lib/modules" ]; then
    KERNEL_VER=$(ls "$MOUNT_DIR/lib/modules" 2>/dev/null | head -n 1)
    [ -n "$KERNEL_VER" ] && MODULE_SRC="$MOUNT_DIR/lib/modules/$KERNEL_VER"
fi
if [ -z "$KERNEL_VER" ] && [ -d "$MOUNT_DIR/usr/lib/modules" ]; then
    KERNEL_VER=$(ls "$MOUNT_DIR/usr/lib/modules" 2>/dev/null | head -n 1)
    [ -n "KERNEL_VER" ] && MODULE_SRC="$MOUNT_DIR/usr/lib/modules/$KERNEL_VER"
fi

if [ -z "$KERNEL_VER" ]; then
    echo "[ X ] No kernel modules found in rootfs!"
    exit 1
fi

sudo mkdir -p "/lib/modules/$KERNEL_VER"
sudo mount --bind "$MODULE_SRC" "/lib/modules/$KERNEL_VER"

trap 'sudo umount /lib/modules/$KERNEL_VER 2>/dev/null; cleanup' EXIT

sudo dracut --force --no-hostonly --filesystems "ext4 vfat" --add-drivers "virtio_blk virtio_pci ahci sd_mod ext4 simpledrm drm" "$MOUNT_DIR/boot/initramfs.img" "$KERNEL_VER"

if [ -f "$MOUNT_DIR/boot/vmlinuz-$KERNEL_VER-lira" ]; then
   sudo cp "$MOUNT_DIR/boot/vmlinuz-$KERNEL_VER-lira" "$MOUNT_DIR/boot/vmlinuz"
elif [ -f "$MOUNT_DIR/usr/lib/modules/$KERNEL_VER/vmlinuz" ]; then
   sudo cp "$MOUNT_DIR/usr/lib/modules/$KERNEL_VER/vmlinuz" "$MOUNT_DIR/boot/vmlinuz"
fi


# 8. Install systemd-boot using Lira OS's own built files
echo "[:::] Installing systemd-boot from unpacked rootfs packages..."
sudo bootctl install --path="$MOUNT_DIR/boot"

# 9. Configure systemd-boot loader entries
sudo bash -c "cat > $MOUNT_DIR/boot/loader/loader.conf" << 'EOF'
timeout 3
default lira.conf
editor yes
EOF

sudo bash -c "cat > $MOUNT_DIR/boot/loader/entries/lira.conf" << EOF
title   Lira OS
linux   /vmlinuz
initrd  /initramfs.img
options root=UUID=$ROOT_UUID rw console=tty0 console=ttyS0,115200n8 rd.shell rd.debug
EOF

# 10. Finalize and Unmount
echo "[:::] Finalizing image..."
sudo sync
sudo umount "$MOUNT_DIR/boot"
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP_DEV"

echo "[:::] Success! image created: $IMAGE_NAME"
