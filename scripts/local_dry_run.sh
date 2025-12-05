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
pip install diskimage-builder ironic-python-agent-builder

chmod +x scripts/build_ironic_iso.sh

# Run the build
scripts/build_ironic_iso.sh
