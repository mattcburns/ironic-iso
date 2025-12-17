#!/usr/bin/env bash
set -euxo pipefail

# Default configuration; can be overridden by env vars.
: "${BASE_DISTRO:=centos}"
: "${DIB_RELEASE:=9-stream}"          # CentOS Stream 9
: "${IMAGE_NAME:=ironic-centos9-ipa}"
: "${ARTIFACTS_DIR:=artifacts}"
: "${EFI_IMG_MB:=16}"                 # Size of the FAT EFI image

mkdir -p "${ARTIFACTS_DIR}"

echo "Using base distro: ${BASE_DISTRO}"
echo "Using DIB release: ${DIB_RELEASE}"
echo "Image name:        ${IMAGE_NAME}"
echo "Artifacts dir:     ${ARTIFACTS_DIR}"
echo "EFI image size:    ${EFI_IMG_MB}MiB"

# Ensure required env vars for diskimage-builder are set
export DIB_DEBUG_TRACE=1
export DIB_RELEASE
export DIB_CLOUD_IMAGES=""

# Set ELEMENTS_PATH to include our custom elements directory
# This allows diskimage-builder to find our custom elements
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ELEMENTS_PATH="${REPO_ROOT}/elements${ELEMENTS_PATH:+:${ELEMENTS_PATH}}"

# Extra elements to include in addition to the default ipa ramdisk elements
# Do NOT include 'ironic-python-agent-ramdisk' here; the builder adds it.
# Space-separated list, e.g. "element-manifest some-driver". Can be empty.
ELEMENTS_EXTRA="element-manifest ironic-root-password dracut-network-config"

# Build the ramdisk + kernel using ironic-python-agent-builder
# Note: This creates a kernel and ramdisk; we then wrap into an ISO.
IPA_OUTPUT_DIR="$(pwd)/ipa-build"
mkdir -p "${IPA_OUTPUT_DIR}"

# The -o flag expects an output PREFIX (file path), not a directory.
# We'll produce files like: ${IPA_OUTPUT_DIR}/${IMAGE_NAME}.kernel and .initramfs
IPA_PREFIX="${IPA_OUTPUT_DIR}/${IMAGE_NAME}"

echo "Building ironic-python-agent ramdisk..."

# Convert ELEMENTS_EXTRA into repeated -e flags safely
EXTRA_E_ARGS=()
if [[ -n "${ELEMENTS_EXTRA}" ]]; then
  read -r -a _els <<< "${ELEMENTS_EXTRA}"
  for _e in "${_els[@]}"; do
    [[ -n "${_e}" ]] && EXTRA_E_ARGS+=( -e "${_e}" )
  done
fi

ironic-python-agent-builder \
  -o "${IPA_PREFIX}" \
  -r "${DIB_RELEASE}" \
  "${EXTRA_E_ARGS[@]}" \
  "${BASE_DISTRO}"

IPA_KERNEL="${IPA_PREFIX}.kernel"
IPA_RAMDISK="${IPA_PREFIX}.initramfs"

if [[ ! -f "${IPA_KERNEL}" || ! -f "${IPA_RAMDISK}" ]]; then
    echo "ERROR: IPA kernel or ramdisk not found in ${IPA_OUTPUT_DIR}"
    ls -l "${IPA_OUTPUT_DIR}" || true
    exit 1
fi

# Wrap kernel+ramdisk into a hybrid (BIOS + UEFI) ISO
ISO_OUTPUT="${ARTIFACTS_DIR}/${IMAGE_NAME}.iso"

echo "Creating ISO: ${ISO_OUTPUT}"
WORKDIR="$(pwd)/iso-work"
mkdir -p "${WORKDIR}/isolinux"
mkdir -p "${WORKDIR}/boot"
mkdir -p "${WORKDIR}/EFI"

cp "${IPA_KERNEL}" "${WORKDIR}/boot/vmlinuz"
cp "${IPA_RAMDISK}" "${WORKDIR}/boot/initrd.img"

cat > "${WORKDIR}/isolinux/isolinux.cfg" <<EOF
DEFAULT ipa
LABEL ipa
  KERNEL /boot/vmlinuz
  APPEND initrd=/boot/initrd.img console=tty0 console=ttyS0,115200n8
TIMEOUT 50
PROMPT 0
EOF

# Basic isolinux bootloader files are typically provided by syslinux
# On Ubuntu, they live under /usr/lib/ISOLINUX or similar.
ISOLINUX_BIN="/usr/lib/ISOLINUX/isolinux.bin"
if [[ ! -f "${ISOLINUX_BIN}" ]]; then
    echo "ERROR: isolinux.bin not found at ${ISOLINUX_BIN}"
    echo "Check syslinux/isolinux installation path on this runner."
    exit 1
fi
cp "${ISOLINUX_BIN}" "${WORKDIR}/isolinux/isolinux.bin"

ISOHYBRID_MBR="/usr/lib/ISOLINUX/isohdpfx.bin"
if [[ ! -f "${ISOHYBRID_MBR}" ]]; then
    echo "WARNING: isohdpfx.bin not found at ${ISOHYBRID_MBR}; ISO will still build but hybrid MBR may be missing"
    ISOHYBRID_MBR=""
fi

# Build ESP image
EFI_IMG="${ARTIFACTS_DIR}/esp.img"
echo "Building ESP image..."

# Paths for CentOS 9 Stream packages
SRC_SHIM="/boot/efi/EFI/centos/shimx64.efi"
SRC_GRUB="/boot/efi/EFI/centos/grubx64.efi"

dd if=/dev/zero of="${EFI_IMG}" bs=1M count=16 status=none
mkfs.msdos -F 12 -n 'ESP_IMAGE' "${EFI_IMG}" > /dev/null
mmd -i "${EFI_IMG}" ::EFI
mmd -i "${EFI_IMG}" ::EFI/BOOT
mcopy -i "${EFI_IMG}" "${SRC_SHIM}" ::EFI/BOOT/BOOTX64.EFI
mcopy -i "${EFI_IMG}" "${SRC_GRUB}" ::EFI/BOOT/grubx64.efi

echo "Done. Created ${EFI_IMG}"

# Create a copy for the ISO's EFI boot image
mkdir -p "${WORKDIR}/EFI"
EFI_ISO_BOOT="${WORKDIR}/EFI/efiboot.img"
cp "${EFI_IMG}" "${EFI_ISO_BOOT}"

# Assemble the hybrid ISO: isolinux for BIOS, GRUB for UEFI
XORRISO_ARGS=(
  -o "${ISO_OUTPUT}"
  -b isolinux/isolinux.bin
  -c isolinux/boot.cat
  -no-emul-boot
  -boot-load-size 4
  -boot-info-table
  -eltorito-alt-boot
  -e EFI/efiboot.img
  -no-emul-boot
  -isohybrid-gpt-basdat
  -V "IRONIC_IPA_ISO"
  "${WORKDIR}"
)

if [[ -n "${ISOHYBRID_MBR}" ]]; then
  XORRISO_ARGS=( -isohybrid-mbr "${ISOHYBRID_MBR}" "${XORRISO_ARGS[@]}" )
fi

xorriso -as mkisofs "${XORRISO_ARGS[@]}"

# Copy kernel and initramfs to artifacts directory for publishing
cp "${IPA_KERNEL}" "${ARTIFACTS_DIR}/${IMAGE_NAME}.kernel"
cp "${IPA_RAMDISK}" "${ARTIFACTS_DIR}/${IMAGE_NAME}.initramfs"

echo "Build complete. ISO at: ${ISO_OUTPUT}"
echo "Kernel at: ${ARTIFACTS_DIR}/${IMAGE_NAME}.kernel"
echo "Initramfs at: ${ARTIFACTS_DIR}/${IMAGE_NAME}.initramfs"
echo "ESP image at: ${EFI_IMG}"
ls -lh "${ARTIFACTS_DIR}"
