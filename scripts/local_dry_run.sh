#!/usr/bin/env bash
set -euxo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${REPO_ROOT}"

# System dependencies (CentOS Stream 9)
sudo dnf -y install \
  python3 \
  python3-pip \
  python3-devel \
  gcc \
  make \
  libffi-devel \
  openssl-devel \
  qemu-img \
  kpartx \
  squashfs-tools \
  xorriso \
  mtools \
  dosfstools \
  shim-x64 \
  grub2-efi-x64

# Python venv
if [[ ! -d .venv ]]; then
  python3 -m venv .venv
fi
source .venv/bin/activate
python3 -m pip install --upgrade pip
python3 -m pip install diskimage-builder ironic-python-agent-builder

chmod +x scripts/build_ironic_iso.sh

# Run the build with signed shim/grub
UEFI_METHOD=shim scripts/build_ironic_iso.sh
