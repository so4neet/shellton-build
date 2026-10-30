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

echo "[:::] Binding virtual fs for installer phase..."
sudo mount --bind /dev "$MOUNT_DIR/dev"
sudo mount --bind /proc "$MOUNT_DIR/proc"
sudo mount --bind /sys "$MOUNT_DIR/sys"

echo "[:::] Generating initramfs inside chroot..."
KERNEL_VER=$(sudo chroot "$MOUNT_DIR" ls /usr/lib/modules | head -n 1)

if [ -z "$KERNEL_VER" ]; then
    echo "[ X ] No kernel modules found in rootfs!"
    exit 1
fi

sudo chroot "$MOUNT_DIR" dracut --force "/boot/initramfs-${KERNEL_VER}.img" "$KERNEL_VER"

sudo chroot "$MOUNT_DIR" bash -c "
     if [ -f /boot/vmlinuz-$KERNEL_VER-lira ]; then
     	cp /boot/vmlinuz-$KERNEL_VER-lira /boot/vmlinuz
     elif [ -f /usr/lib/modules/$KERNEL_VER/vmlinuz ]; then
     	cp /usr/lib/modules/$KERNEL_VER/vmlinuz /boot/vmlinuz
     fi
"

# 8. Install systemd-boot using Lira OS's own built files
echo "[:::] Installing systemd-boot from unpacked rootfs packages..."
sudo chroot "$MOUNT_DIR" bootctl install --path=/boot

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
