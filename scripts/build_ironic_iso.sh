#!/usr/bin/env bash
set -euxo pipefail

# Default configuration; can be overridden by env vars.
: "${BASE_DISTRO:=centos}"
: "${DIB_RELEASE:=9-stream}"          # CentOS Stream 9
: "${IMAGE_NAME:=ironic-centos9-ipa}"
: "${ARTIFACTS_DIR:=artifacts}"

mkdir -p "${ARTIFACTS_DIR}"

echo "Using base distro: ${BASE_DISTRO}"
echo "Using DIB release: ${DIB_RELEASE}"
echo "Image name:        ${IMAGE_NAME}"
echo "Artifacts dir:     ${ARTIFACTS_DIR}"

# Ensure required env vars for diskimage-builder are set
export DIB_DEBUG_TRACE=1
export DIB_RELEASE
export DIB_CLOUD_IMAGES=""

# Base elements for an ironic-python-agent image
# You may customize this list with hardware-specific elements as needed.
ELEMENTS="ironic-python-agent-ramdisk element-manifest"

# Build the ramdisk + kernel using ironic-python-agent-builder
# Note: This creates a kernel and ramdisk; we then wrap into an ISO.
IPA_OUTPUT_DIR="$(pwd)/ipa-build"
mkdir -p "${IPA_OUTPUT_DIR}"

echo "Building ironic-python-agent ramdisk..."
ironic-python-agent-builder \
  -o "${IPA_OUTPUT_DIR}" \
  -e "${ELEMENTS}" \
  -r "${DIB_RELEASE}" \
  "${BASE_DISTRO}"

IPA_KERNEL="${IPA_OUTPUT_DIR}/ipa.kernel"
IPA_RAMDISK="${IPA_OUTPUT_DIR}/ipa.initramfs"

if [[ ! -f "${IPA_KERNEL}" || ! -f "${IPA_RAMDISK}" ]]; then
    echo "ERROR: IPA kernel or ramdisk not found in ${IPA_OUTPUT_DIR}"
    ls -l "${IPA_OUTPUT_DIR}" || true
    exit 1
fi

# Wrap kernel+ramdisk into an ISO
ISO_OUTPUT="${ARTIFACTS_DIR}/${IMAGE_NAME}.iso"

echo "Creating ISO: ${ISO_OUTPUT}"
# A simple approach using xorriso and a grub/syslinux based template could be used.
# For now, we use a very simple isolinux-based layout.
WORKDIR="$(pwd)/iso-work"
mkdir -p "${WORKDIR}/isolinux"
mkdir -p "${WORKDIR}/boot"

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

xorriso -as mkisofs \
  -o "${ISO_OUTPUT}" \
  -b isolinux/isolinux.bin \
  -c isolinux/boot.cat \
  -no-emul-boot \
  -boot-load-size 4 \
  -boot-info-table \
  -V "IRONIC_IPA_ISO" \
  "${WORKDIR}"

echo "Build complete. ISO at: ${ISO_OUTPUT}"
ls -lh "${ARTIFACTS_DIR}"
