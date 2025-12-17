# ironic-iso

GitHub Actions–based pipeline to build custom OpenStack Ironic images in ISO format using:

- `ironic-python-agent-builder`
- `diskimage-builder`
- CentOS Stream 9 as the base OS

The resulting ISO is hybrid and supports both BIOS/legacy (isolinux) and UEFI (GRUB) boot modes.

## GitHub Actions Workflow

The workflow:

- Runs in a **privileged** CentOS Stream 9 container (needed for tmpfs mounts during image build)
- Installs system dependencies via `dnf` (git, syslinux/syslinux-nonlinux, shim/grub, mtools/dosfstools, python3)
- Installs `diskimage-builder` and `ironic-python-agent-builder` with `python3`/`pip3`
- Builds a CentOS Stream 9 based Ironic ISO with a hybrid BIOS/UEFI bootloader
- Builds an ESP (EFI System Partition) image using CentOS-provided shim and GRUB
- Uploads the ISO, kernel, initramfs, and ESP image as build artifacts

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
- Download the artifact named `ironic-centos9-iso` (contains `*.iso`, `*.kernel`, `*.initramfs`, and `*.img` files)

2) From a GitHub Release (shareable permalink)

- Create and push a tag, e.g. `v0.1.0`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

- The workflow will publish a Release for that tag and attach the built ISO.
- Navigate to **Releases** in the repo to download the asset.

## Local dry run

To test the build locally on a CentOS 9 Stream system, run:

```bash
./scripts/local_dry_run.sh
```

This will create a Python virtualenv, install the required packages, and build the ISO into an `artifacts/` directory.

**Note:** The build script expects to run on CentOS 9 Stream (or compatible) as it requires access to CentOS-provided EFI files at `/boot/efi/EFI/centos/`.

The build mounts tmpfs/loop devices; run as root or via `sudo`, or inside a privileged CentOS Stream 9 container. On CentOS, `isolinux.bin`/`isohdpfx.bin` come from the `syslinux`/`syslinux-nonlinux` packages under `/usr/share/syslinux/`.

### EFI/UEFI and ESP image dependencies

The build process creates:
1. A hybrid ISO with BIOS (isolinux) and UEFI (GRUB) boot support
2. A separate ESP (EFI System Partition) image using CentOS-provided shim and GRUB binaries

Required packages (automatically installed by the GitHub Actions workflow and `local_dry_run.sh`):

- `grub2-efi-x64` and `grub2-pc` (for GRUB)
- `shim-x64` (for secure boot support)
- `mtools` and `dosfstools` (for creating FAT EFI/ESP images)
- `syslinux` and `syslinux-nonlinux` (for `isolinux.bin`/`isohdpfx.bin`)

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

