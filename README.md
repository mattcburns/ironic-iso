# ironic-iso

GitHub Actions–based pipeline to build custom OpenStack Ironic images in ISO format using:

- `ironic-python-agent-builder`
- `diskimage-builder`
- CentOS Stream 9 as the base OS

The resulting ISO is hybrid and supports both BIOS/legacy (isolinux) and UEFI (GRUB) boot modes.

## IPA Versioning & Compatibility

This builder produces Ironic Python Agent (IPA) ramdisks. **For production use, the IPA version inside the image should match your Ironic controller release series.**

- Default: `stable/2026.1` (current maintained OpenStack release as of 2026.1 Gazpacho)
- The `IPA_BRANCH` environment variable controls which branch/tag of `ironic-python-agent` (and its requirements) is built into the image.

### Why this matters

Ironic and IPA are tightly coupled. Using a mismatched IPA can cause:
- Missing or incompatible deploy/cleaning/inspection steps
- Hardware manager differences
- API behavior changes
- Failures after Ironic upgrades

**Recommendation**: Set `IPA_BRANCH` to the same stable branch as your Ironic deployment (e.g. `stable/2026.1`, `stable/2025.2`).

### Controlling the IPA version

Override the branch when building:

```bash
# GitHub Actions - use the manual "Run workflow" form (see below).
# The `ipa_branch` field is pre-filled with `stable/2026.1`.

# Local build
IPA_BRANCH=stable/2025.2 ./scripts/build_ironic_iso.sh

# Or for a specific point release
IPA_BRANCH=9.8.0 ./scripts/build_ironic_iso.sh
```

The resulting artifact filenames include the branch for clarity:
`ironic-centos9-ipa-stable-2026.1.iso`, `ironic-centos9-ipa-stable-2026.1.kernel`, etc.

A `build-info.txt` file is also included in artifacts containing the exact `IPA_BRANCH`, builder package versions, and build timestamp.

In GitHub Actions runs, a **"Validate build-info.txt"** step runs automatically after the build to verify that the requested branch was used correctly.

### Advanced: overriding builder versions

The GitHub workflow and `local_dry_run.sh` pin `diskimage-builder` and `ironic-python-agent-builder` to known-good versions that match the default IPA branch. You can install different versions manually before running the build script if you need to test newer DIB features or a different builder release. The build script itself does not enforce the pins.

## GitHub Actions Workflow

The workflow:

- Runs in a **privileged** CentOS Stream 9 container (needed for tmpfs mounts during image build)
- Installs system dependencies via `dnf` (git, syslinux/syslinux-nonlinux, shim/grub, mtools/dosfstools, python3)
- Installs **pinned** versions of `diskimage-builder==3.40.2` and `ironic-python-agent-builder==7.2.0` for reproducibility
- Builds IPA from a configurable branch (`IPA_BRANCH`, default `stable/2026.1`) using the builder's `-b` flag
- Builds a CentOS Stream 9 based Ironic ISO with a hybrid BIOS/UEFI bootloader
- Builds an ESP (EFI System Partition) image using CentOS-provided shim and GRUB
- Uploads the ISO, kernel, initramfs, ESP image, and `build-info.txt` as build artifacts

## How to trigger

- Push to `master`
- Open a pull request targeting `master`
- Or trigger manually:

1. Go to **Actions** tab
2. Choose **Build Ironic ISO**
3. Click **Run workflow**
4. The `ipa_branch` field is **pre-filled** with the default `stable/2026.1`. You can leave it as-is or enter a different value (e.g. `stable/2025.2`, `9.7.0`, a git tag, or a commit SHA).

After the build completes, you will see a **"Validate build-info.txt"** step in the logs. This step confirms that the requested IPA branch was actually used and that `build-info.txt` was generated correctly.

The built ISO (and other artifacts) will be available as an artifact attached to the workflow run. Artifact filenames include the IPA branch for easy identification.

## How to download the ISO

There are two options:

1) From the workflow run artifacts (quickest)

- Go to the **Actions** tab
- Open the latest run of "Build Ironic ISO"
- Download the artifact named `ironic-centos9-iso` (contains versioned `*.iso`, `*.kernel`, `*.initramfs`, `*.img`, and `build-info.txt` files)

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

This will create a Python virtualenv, install the **pinned** builder packages, and build the ISO (using `IPA_BRANCH=stable/2026.1` by default) into an `artifacts/` directory.

You can override the IPA branch for a local run:

```bash
IPA_BRANCH=stable/2025.2 ./scripts/local_dry_run.sh
```

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

Other important variables you can override the same way:
- `IPA_BRANCH` — Ironic Python Agent git branch/tag (default `stable/2026.1`)
- `IMAGE_NAME` — base name for output files (default incorporates the IPA branch)
- `DIB_RELEASE`, `BASE_DISTRO`, etc. (see the top of `build_ironic_iso.sh`)

### Security Notice

The hardcoded root password is intended **for development and testing only**. For production deployments, you should:

1. Set a strong, unique password
2. Consider using key-based authentication instead
3. Disable direct root login if possible

