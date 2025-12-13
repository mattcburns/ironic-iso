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
ELEMENTS_EXTRA="element-manifest ironic-root-password"

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

# Build a minimal GRUB UEFI image and embed the boot config
EFI_STAGING="${WORKDIR}/efi-staging"
EFI_BOOT_DIR="${EFI_STAGING}/EFI/BOOT"
mkdir -p "${EFI_BOOT_DIR}"

cat > "${EFI_BOOT_DIR}/grub.cfg" <<'EOF'
search --no-floppy --file /boot/vmlinuz --set=root
set default=0
set timeout=5

menuentry "Ironic Python Agent (UEFI)" {
  linux /boot/vmlinuz console=tty0 console=ttyS0,115200n8
  initrd /boot/initrd.img
}
EOF

if ! command -v grub-mkstandalone >/dev/null 2>&1; then
    echo "ERROR: grub-mkstandalone not found; install grub-efi-amd64-bin (Debian/Ubuntu) or grub2-efi-x64 (RHEL/CentOS)."
    exit 1
fi

GRUB_STANDALONE="${EFI_BOOT_DIR}/BOOTX64.EFI"
grub-mkstandalone \
  -O x86_64-efi \
  -o "${GRUB_STANDALONE}" \
  --compress=xz \
  "boot/grub/grub.cfg=${EFI_BOOT_DIR}/grub.cfg"

EFI_IMG="${WORKDIR}/EFI/efiboot.img"
for tool in mkfs.vfat mmd mcopy; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: ${tool} not found; install dosfstools (mkfs.vfat) and mtools (mmd/mcopy)."
    exit 1
  fi
done

truncate -s "${EFI_IMG_MB}M" "${EFI_IMG}"
mkfs.vfat "${EFI_IMG}"
mmd -i "${EFI_IMG}" ::/EFI ::/EFI/BOOT
mcopy -i "${EFI_IMG}" "${GRUB_STANDALONE}" ::/EFI/BOOT/BOOTX64.EFI
mcopy -i "${EFI_IMG}" "${EFI_BOOT_DIR}/grub.cfg" ::/EFI/BOOT/grub.cfg

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

echo "Build complete. ISO at: ${ISO_OUTPUT}"
ls -lh "${ARTIFACTS_DIR}"
