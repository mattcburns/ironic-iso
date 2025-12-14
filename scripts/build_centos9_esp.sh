#!/usr/bin/env bash
set -euxo pipefail

# Minimal signed ESP image generator for CentOS Stream 9
# Requires: dosfstools, mtools, shim-x64, grub2-efi-x64

OUTPUT_IMG="${OUTPUT_IMG:-esp-centos9.img}"
SRC_SHIM="${SRC_SHIM:-/boot/efi/EFI/centos/shimx64.efi}"
SRC_GRUB="${SRC_GRUB:-/boot/efi/EFI/centos/grubx64.efi}"
EFI_IMG_MB="${EFI_IMG_MB:-3}"

# Simple kernel entry grub.cfg (adjust as needed)
GRUB_CFG_CONTENT='set default=0
set timeout=5
menuentry "Ironic Python Agent (UEFI)" {
  set root=(cd0)
  if [ -f /vmlinuz -a -f /initrd ]; then
    linux /vmlinuz console=tty0 console=ttyS0,115200n8
    initrd /initrd
  elif [ -f /boot/vmlinuz -a -f /boot/initrd.img ]; then
    linux /boot/vmlinuz console=tty0 console=ttyS0,115200n8
    initrd /boot/initrd.img
  fi
}
'

if [[ ! -f "$SRC_SHIM" || ! -f "$SRC_GRUB" ]]; then
  echo "Error: Bootloader binaries not found."
  echo "On CentOS: sudo dnf install -y shim-x64 grub2-efi-x64"
  echo "Checked SRC_SHIM=$SRC_SHIM SRC_GRUB=$SRC_GRUB"
  exit 1
fi

# Create and format image (FAT12 for small ESPs)
truncate -s "${EFI_IMG_MB}M" "$OUTPUT_IMG"
mkfs.vfat -F 12 "$OUTPUT_IMG"

# Create directories
mmd -i "$OUTPUT_IMG" ::/EFI ::/EFI/BOOT

# Copy signed loaders
mcopy -i "$OUTPUT_IMG" "$SRC_SHIM" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "$OUTPUT_IMG" "$SRC_GRUB" ::/EFI/BOOT/grubx64.efi

# Write grub.cfg to both fallback and CentOS paths for robustness
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
printf "%s" "$GRUB_CFG_CONTENT" > "$TMPDIR/grub.cfg"

mcopy -i "$OUTPUT_IMG" "$TMPDIR/grub.cfg" ::/EFI/BOOT/grub.cfg
mmd -i "$OUTPUT_IMG" ::/EFI/centos || true
mcopy -i "$OUTPUT_IMG" "$TMPDIR/grub.cfg" ::/EFI/centos/grub.cfg

echo "Success! $OUTPUT_IMG is ready."
