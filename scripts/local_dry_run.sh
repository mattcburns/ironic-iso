#!/usr/bin/env bash
set -euxo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# System dependencies
sudo apt-get update
sudo apt-get install -y \
  qemu-utils \
  kpartx \
  debootstrap \
  squashfs-tools \
  xorriso \
  syslinux \
  isolinux \
  grub-pc-bin \
  grub-efi-amd64-bin \
  mtools \
  dosfstools \
  python3-venv \
  python3-dev \
  gcc \
  make \
  libffi-dev \
  libssl-dev

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
