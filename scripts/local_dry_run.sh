#!/usr/bin/env bash
set -euxo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# Target architecture: amd64 or arm64. Defaults to the host's native arch.
# Building for a non-native arch here would require qemu-user-static/binfmt
# cross-chroot support, which this script does not set up -- for a real
# cross-arch build, use the GitHub Actions workflow's native arm64 runner
# instead.
case "$(uname -m)" in
  aarch64) NATIVE_ARCH=arm64 ;;
  *) NATIVE_ARCH=amd64 ;;
esac
: "${DIB_ARCH:=${NATIVE_ARCH}}"
export DIB_ARCH

if [[ "${DIB_ARCH}" != "${NATIVE_ARCH}" ]]; then
  echo "WARNING: DIB_ARCH=${DIB_ARCH} requested but this host is ${NATIVE_ARCH}."
  echo "         This script does not set up cross-arch emulation; the build will likely fail."
fi

# System dependencies (common to both arches)
sudo apt-get update
sudo apt-get install -y \
  qemu-utils \
  kpartx \
  debootstrap \
  squashfs-tools \
  xorriso \
  mtools \
  dosfstools \
  python3-venv \
  python3-dev \
  gcc \
  make \
  libffi-dev \
  libssl-dev

# Arch-specific bootloader dependencies. amd64 needs BIOS (isolinux) tooling
# in addition to UEFI; arm64 is UEFI-only.
if [[ "${DIB_ARCH}" == "amd64" ]]; then
  sudo apt-get install -y \
    syslinux \
    isolinux \
    grub-pc-bin \
    grub-efi-amd64-bin
else
  sudo apt-get install -y \
    grub-efi-arm64-bin
fi

# Python venv
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
python -m pip install --upgrade pip

# Default IPA branch (can be overridden by exporting IPA_BRANCH before running)
: "${IPA_BRANCH:=stable/2026.1}"
export IPA_BRANCH

# Pin to coordinated versions for the 2026.1 series (same as the GitHub workflow)
pip install \
  diskimage-builder==3.40.2 \
  ironic-python-agent-builder==7.2.0

echo "Building with IPA_BRANCH=${IPA_BRANCH}"

chmod +x scripts/build_ironic_iso.sh

# Run the build (IPA_BRANCH is picked up automatically by the build script)
scripts/build_ironic_iso.sh
