# ironic-iso

GitHub Actions–based pipeline to build custom OpenStack Ironic images in ISO format using:

- `ironic-python-agent-builder`
- `diskimage-builder`
- CentOS Stream 9 as the base OS

The resulting ISO supports UEFI boot mode only (via GRUB).

## GitHub Actions Workflow

The workflow:

- Runs inside a `CentOS Stream 9` container for Secure Boot support
- Installs `diskimage-builder` and `ironic-python-agent-builder`
- Builds a CentOS Stream 9 based Ironic ISO with `UEFI_METHOD=shim`
- Uploads the resulting ISO as a build artifact

## How to trigger

- Push to `master`
- Open a pull request targeting `master`
- Or trigger manually:

1. Go to **Actions** tab
2. Choose **Build Ironic ISO**
3. Click **Run workflow**

The built ISO will be available as an artifact attached to the workflow run.

## How to download the ISO

There are two options:

1) From the workflow run artifacts (quickest)

- Go to the **Actions** tab
- Open the latest run of "Build Ironic ISO"
- Download the artifact named `ironic-centos9-iso` (contains `*.iso`)

2) From a GitHub Release (shareable permalink)

- Create and push a tag, e.g. `v0.1.0`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

- The workflow will publish a Release for that tag and attach the built ISO.
- Navigate to **Releases** in the repo to download the asset.

## Local dry run (CentOS Stream 9)

Run on a CentOS Stream 9 system:

```bash
./scripts/local_dry_run.sh
```

This will create a Python virtualenv, install CentOS packages (via `dnf`), and build the ISO into an `artifacts/` directory using signed shim/grub.

**Not running CentOS?** Use a container:

```bash
podman run --rm -it -v $(pwd):/workspace:z -w /workspace \
  quay.io/centos/centos:stream9 \
  bash -c "dnf install -y sudo git && ./scripts/local_dry_run.sh"
```

(Replace `podman` with `docker` if preferred.)

### UEFI dependencies

UEFI ISO creation requires a bootloader and FAT tooling for the embedded EFI image. On CentOS Stream 9:

- `shim-x64` and `grub2-efi-x64` (signed bootloaders for Secure Boot)
- `mtools` and `dosfstools` (FAT image creation)
## Secure Boot (CentOS Stream 9)

This repo supports building an ESP using CentOS-signed `shim` + `grub`, enabling UEFI Secure Boot.

- On a CentOS 9 host/container:

```bash
sudo dnf install -y dosfstools mtools shim-x64 grub2-efi-x64
```

- Option A: Build a standalone ESP image only

```bash
scripts/build_centos9_esp.sh
# Outputs esp-centos9.img (config at EFI/BOOT/grub.cfg)
```

- Option B: Integrate into full ISO build

```bash
UEFI_METHOD=shim \
SRC_SHIM=/boot/efi/EFI/centos/shimx64.efi \
SRC_GRUB=/boot/efi/EFI/centos/grubx64.efi \
./scripts/build_ironic_iso.sh
```

Notes:
- When `UEFI_METHOD=shim`, the script copies signed `shimx64.efi` → `EFI/BOOT/BOOTX64.EFI` and `grubx64.efi` → `EFI/BOOT/grubx64.efi`, and writes `grub.cfg` to both `EFI/BOOT/` and `EFI/centos/` for robustness.
- When `UEFI_METHOD=standalone` (default), the build uses `grub-mkstandalone` to produce `BOOTX64.EFI` and a minimal `grub.cfg` in `EFI/BOOT/`.

## Root Password

The built ISO includes a hardcoded root password for easier testing and development:

- **Username:** `root`
- **Password:** `ironic`

This password is set during the ISO build process via the `ironic-root-password` element.

### Customizing the Root Password

To change the root password, you can override the `IRONIC_ROOT_PASSWORD` environment variable when building:

```bash
IRONIC_ROOT_PASSWORD=mypassword ./scripts/build_ironic_iso.sh
```

### Security Notice

The hardcoded root password is intended **for development and testing only**. For production deployments, you should:

1. Set a strong, unique password
2. Consider using key-based authentication instead
3. Disable direct root login if possible

