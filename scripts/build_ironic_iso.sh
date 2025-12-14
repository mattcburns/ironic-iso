#!/usr/bin/env bash
set -euxo pipefail

# Configuration (override via env vars if needed)
: "${BASE_DISTRO:=centos}"
: "${DIB_RELEASE:=9-stream}"          # CentOS Stream 9
: "${IMAGE_NAME:=ironic-centos9-ipa}"
: "${ARTIFACTS_DIR:=artifacts}"
: "${EFI_IMG_MB:=32}"                 # Size of the FAT EFI image
: "${UEFI_METHOD:=standalone}"        # 'shim' or 'standalone'
# Optional overrides for shim/grub on CentOS when UEFI_METHOD=shim
: "${SRC_SHIM:=/boot/efi/EFI/centos/shimx64.efi}"
: "${SRC_GRUB:=/boot/efi/EFI/centos/grubx64.efi}"

mkdir -p "${ARTIFACTS_DIR}"

echo "Using base distro: ${BASE_DISTRO}"
echo "Using DIB release: ${DIB_RELEASE}"
echo "Image name:        ${IMAGE_NAME}"
echo "Artifacts dir:     ${ARTIFACTS_DIR}"
echo "EFI image size:    ${EFI_IMG_MB}MiB"

# diskimage-builder settings
export DIB_DEBUG_TRACE=1
export DIB_RELEASE
export DIB_CLOUD_IMAGES=""

# Include repo elements in ELEMENTS_PATH
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export ELEMENTS_PATH="${REPO_ROOT}/elements${ELEMENTS_PATH:+:${ELEMENTS_PATH}}"

# Extra elements for the IPA ramdisk
ELEMENTS_EXTRA="element-manifest ironic-root-password"

# Build IPA kernel and ramdisk
IPA_OUTPUT_DIR="$(pwd)/ipa-build"
mkdir -p "${IPA_OUTPUT_DIR}"

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

# Create UEFI-only ISO
ISO_OUTPUT="${ARTIFACTS_DIR}/${IMAGE_NAME}.iso"

echo "Creating ISO: ${ISO_OUTPUT}"
WORKDIR="$(pwd)/iso-work"
mkdir -p "${WORKDIR}/boot"
mkdir -p "${WORKDIR}/EFI"

cp "${IPA_KERNEL}" "${WORKDIR}/boot/vmlinuz"
cp "${IPA_RAMDISK}" "${WORKDIR}/boot/initrd.img"

# Build UEFI boot files
EFI_STAGING="${WORKDIR}/efi-staging"
EFI_BOOT_DIR="${EFI_STAGING}/EFI/BOOT"
mkdir -p "${EFI_BOOT_DIR}"

cat > "${EFI_BOOT_DIR}/grub.cfg" <<'EOF'
set default=0
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
EOF

# Build using signed shim+grub (CentOS) when requested, else standalone GRUB
if [[ "${UEFI_METHOD}" == "shim" ]]; then
  # Resolve shim/grub paths from common locations if not present
  resolve_efi_bin() {
    local name="$1"; shift
    local candidates=("$@")
    for p in "${candidates[@]}"; do
      if [[ -f "$p" ]]; then
        echo "$p"
        return 0
      fi
    done
    return 1
  }
  # Candidates for CentOS/RHEL locations (container-friendly)
  if [[ ! -f "${SRC_SHIM}" ]]; then
    SRC_SHIM=$(resolve_efi_bin shimx64.efi \
      /boot/efi/EFI/centos/shimx64.efi \
      /usr/share/efi/EFI/centos/shimx64.efi \
      /usr/share/efi/EFI/BOOT/BOOTX64.EFI \
      /usr/lib/shim/shimx64.efi \
      /usr/lib64/efi/shimx64.efi) || true
  fi
  if [[ ! -f "${SRC_GRUB}" ]]; then
    SRC_GRUB=$(resolve_efi_bin grubx64.efi \
      /boot/efi/EFI/centos/grubx64.efi \
      /usr/share/efi/EFI/centos/grubx64.efi \
      /usr/share/grub2/efi/grubx64.efi \
      /usr/lib/grub/x86_64-efi/grubx64.efi \
      /usr/lib64/efi/grubx64.efi) || true
  fi
  if [[ -z "${SRC_SHIM}" || -z "${SRC_GRUB}" || ! -f "${SRC_SHIM}" || ! -f "${SRC_GRUB}" ]]; then
    echo "ERROR: shim/grub not found. On CentOS: dnf install -y shim-x64 grub2-efi-x64"
    echo "Checked: SRC_SHIM=${SRC_SHIM:-unset} SRC_GRUB=${SRC_GRUB:-unset}"
    exit 1
  fi
  # Place signed loaders
  install -m 0644 "${SRC_SHIM}" "${EFI_BOOT_DIR}/BOOTX64.EFI"
  install -m 0644 "${SRC_GRUB}" "${EFI_BOOT_DIR}/grubx64.efi"
else
    # Support both Debian and RHEL names for mkstandalone
    MKSTANDALONE_BIN="$(command -v grub-mkstandalone || command -v grub2-mkstandalone || true)"
    if [[ -z "${MKSTANDALONE_BIN}" ]]; then
      echo "ERROR: grub-mkstandalone/grub2-mkstandalone not found."
      echo "On Debian/Ubuntu: install grub-efi-amd64-bin. On CentOS/RHEL: grub2-efi-x64."
      exit 1
    fi
  GRUB_STANDALONE="${EFI_BOOT_DIR}/BOOTX64.EFI"
  cat > "${EFI_BOOT_DIR}/bootstrap.cfg" <<'EOF'
set timeout=0
if [ -f ($root)/EFI/BOOT/grub.cfg ]; then
  configfile ($root)/EFI/BOOT/grub.cfg
else
  search --no-floppy --file /EFI/BOOT/grub.cfg --set=espdev
  if [ -n "$espdev" ]; then
    configfile ($espdev)/EFI/BOOT/grub.cfg
  fi
fi
EOF
  "${MKSTANDALONE_BIN}" \
    -O x86_64-efi \
    -o "${GRUB_STANDALONE}" \
    --compress=xz \
    "boot/grub/grub.cfg=${EFI_BOOT_DIR}/bootstrap.cfg"
fi

EFI_IMG="${WORKDIR}/EFI/efiboot.img"
for tool in mkfs.vfat mmd mcopy; do
  if ! command -v "${tool}" >/dev/null 2>&1; then
    echo "ERROR: ${tool} not found; install dosfstools (mkfs.vfat) and mtools (mmd/mcopy)."
    exit 1
  fi
done

truncate -s "${EFI_IMG_MB}M" "${EFI_IMG}"
mkfs.vfat -F 12 "${EFI_IMG}"
mmd -i "${EFI_IMG}" ::/EFI ::/EFI/BOOT
mcopy -i "${EFI_IMG}" "${EFI_BOOT_DIR}/grub.cfg" ::/EFI/BOOT/grub.cfg
if [[ "${UEFI_METHOD}" == "shim" ]]; then
  mcopy -i "${EFI_IMG}" "${EFI_BOOT_DIR}/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
  mcopy -i "${EFI_IMG}" "${EFI_BOOT_DIR}/grubx64.efi" ::/EFI/BOOT/grubx64.efi
  # Also place config in CentOS path for robustness
  mmd -i "${EFI_IMG}" ::/EFI/centos || true
  mcopy -i "${EFI_IMG}" "${EFI_BOOT_DIR}/grub.cfg" ::/EFI/centos/grub.cfg
else
  mcopy -i "${EFI_IMG}" "${EFI_BOOT_DIR}/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
fi

# Assemble UEFI-only ISO
xorriso -as mkisofs \
  -o "${ISO_OUTPUT}" \
  -e EFI/efiboot.img \
  -no-emul-boot \
  -V "IRONIC_IPA_ISO" \
  "${WORKDIR}"

# Verify UEFI ESP image was created
if [[ ! -f "${EFI_IMG}" ]]; then
    echo "ERROR: UEFI ESP image not found at ${EFI_IMG}"
    exit 1
fi

# Copy kernel and initramfs to artifacts directory for publishing
cp "${IPA_KERNEL}" "${ARTIFACTS_DIR}/${IMAGE_NAME}.kernel"
cp "${IPA_RAMDISK}" "${ARTIFACTS_DIR}/${IMAGE_NAME}.initramfs"

# Copy UEFI ESP image for on-the-fly ISO creation support with OpenStack Ironic
cp "${EFI_IMG}" "${ARTIFACTS_DIR}/${IMAGE_NAME}-efiboot.img"

# Verify all artifacts are present
if [[ ! -f "${ARTIFACTS_DIR}/${IMAGE_NAME}.iso" || ! -f "${ARTIFACTS_DIR}/${IMAGE_NAME}-efiboot.img" ]]; then
    echo "ERROR: ISO or ESP image failed to copy to artifacts directory"
    exit 1
fi

echo "Build complete. ISO at: ${ISO_OUTPUT}"
echo "Kernel at: ${ARTIFACTS_DIR}/${IMAGE_NAME}.kernel"
echo "Initramfs at: ${ARTIFACTS_DIR}/${IMAGE_NAME}.initramfs"
echo "UEFI ESP image at: ${ARTIFACTS_DIR}/${IMAGE_NAME}-efiboot.img"
ls -lh "${ARTIFACTS_DIR}"
