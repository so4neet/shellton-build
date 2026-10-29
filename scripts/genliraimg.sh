#!/bin/bash
set -e

IMAGE_SIZE_MB=1024
REPO_DIR="/srv/shellton/repository"
BUILD_DIR="/srv/shellton/lira_os_core"
MOUNT_DIR="$BUILD_DIR/mnt"
IMAGE_NAME="$BUILD_DIR/lira_os_core.img"
echo "[:::] Initializing Lira OS Image Builder..."

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
sudo mkdir -p "$MOUNT_DIR"/{dev,proc,sys,etc,opt/syspackages,opt/spkg,root,home,tmp}
sudo chmod 1777 "$MOUNT_DIR/tmp"

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

# 8. Install systemd-boot using Lira OS's own built files
echo "[:::] Installing systemd-boot from unpacked rootfs packages..."
sudo mkdir -p "$MOUNT_DIR/boot/EFI/systemd"
sudo mkdir -p "$MOUNT_DIR/boot/EFI/BOOT"
sudo mkdir -p "$MOUNT_DIR/boot/loader/entries"

# Locate systemd-boot EFI binary from within the extracted rootfs
TARGET_EFI_SRC="$MOUNT_DIR/usr/lib/systemd/boot/efi/systemd-bootx64.efi"

if [ -f "$TARGET_EFI_SRC" ]; then
    sudo cp "$TARGET_EFI_SRC" "$MOUNT_DIR/boot/EFI/systemd/systemd-bootx64.efi"
    sudo cp "$TARGET_EFI_SRC" "$MOUNT_DIR/boot/EFI/BOOT/BOOTX64.EFI"
else
    echo "[!] Error: systemd-bootx64.efi not found in installed packages! Ensure systemd package is built and installed."
    exit 1
fi

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
options root=UUID=$ROOT_UUID rw quiet
EOF

# 10. Finalize and Unmount
echo "[:::] Finalizing image..."
sudo sync
sudo umount "$MOUNT_DIR/boot"
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP_DEV"

echo "[:::] Success! image created: $IMAGE_NAME"
