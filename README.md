# ironic-iso

GitHub Actions–based pipeline to build custom OpenStack Ironic images in ISO format using:

- `ironic-python-agent-builder`
- `diskimage-builder`
- CentOS Stream 9 as the base OS

Images are built for both **amd64** and **arm64**. On amd64 the resulting ISO is hybrid and supports both BIOS/legacy (isolinux) and UEFI (GRUB) boot modes. On arm64 there is no legacy BIOS mode, so the ISO is UEFI-only (GRUB).

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

The resulting artifact filenames include the branch and target architecture for clarity:
`ironic-centos9-ipa-stable-2026.1-amd64.iso`, `ironic-centos9-ipa-stable-2026.1-arm64.kernel`, etc.

A `build-info.txt` file is also included in artifacts containing the exact `IPA_BRANCH`, builder package versions, and build timestamp.

In GitHub Actions runs, a **"Validate build-info.txt"** step runs automatically after the build to verify that the requested branch was used correctly.

### Advanced: overriding builder versions

The GitHub workflow and `local_dry_run.sh` pin `diskimage-builder` and `ironic-python-agent-builder` to known-good versions that match the default IPA branch. You can install different versions manually before running the build script if you need to test newer DIB features or a different builder release. The build script itself does not enforce the pins.

## Architecture Support (amd64 / arm64)

The build is a matrix over `amd64` and `arm64`, each running **natively** (no QEMU/binfmt emulation):

- `amd64` runs on the standard `ubuntu-latest` GitHub-hosted runner
- `arm64` runs on GitHub's hosted `ubuntu-24.04-arm` runner (free for public repos)

Both jobs use the same multi-arch `quay.io/centos/centos:stream9` container image, which Docker pulls in the matching architecture automatically. Since each job runs on a host of its own target architecture, `diskimage-builder`/`ironic-python-agent-builder` builds the ramdisk natively via `disk-image-create -a <arch>` (passed through `--extra-args`) — no cross-compilation or emulation is involved.

Key differences on `arm64`:
- Boot packages are `shim-aa64`/`grub2-efi-aa64` instead of `shim-x64`/`grub2-efi-x64`
- The ISO has no legacy BIOS (isolinux) boot path — arm64 has no BIOS mode, so it's UEFI-only
- `syslinux`/`syslinux-nonlinux` are not installed (not needed without a BIOS boot path)

To build for `arm64` locally on non-CentOS/non-arm64 hardware, cross-arch chroot support (`qemu-user-static`/binfmt) would be required; `scripts/local_dry_run.sh` does not set this up and expects to run natively on the target arch. Use the GitHub Actions workflow for cross-arch builds.

## GitHub Actions Workflow

The workflow:

- Runs a matrix job (`amd64`, `arm64`), each in a **privileged** CentOS Stream 9 container on a native-arch runner (needed for tmpfs mounts during image build)
- Installs system dependencies via `dnf` (git, mtools/dosfstools, python3, plus arch-specific shim/grub and, on amd64 only, syslinux/syslinux-nonlinux for BIOS boot)
- Installs **pinned** versions of `diskimage-builder==3.40.2` and `ironic-python-agent-builder==7.2.0` for reproducibility
- Builds IPA from a configurable branch (`IPA_BRANCH`, default `stable/2026.1`) using the builder's `-b` flag, for the job's target arch via `-a`
- Builds a CentOS Stream 9 based Ironic ISO (hybrid BIOS/UEFI on amd64, UEFI-only on arm64)
- Builds an ESP (EFI System Partition) image using CentOS-provided shim and GRUB
- Uploads the ISO, kernel, initramfs, ESP image, and `build-info.txt` as build artifacts, one artifact set per architecture

## How to trigger

- Push to `master`
- Open a pull request targeting `master`
- Or trigger manually:

1. Go to **Actions** tab
2. Choose **Build Ironic ISO**
3. Click **Run workflow**
4. The `ipa_branch` field is **pre-filled** with the default `stable/2026.1`. You can leave it as-is or enter a different value (e.g. `stable/2025.2`, `9.7.0`, a git tag, or a commit SHA).

After the build completes, you will see a **"Validate build-info.txt"** step in the logs. This step confirms that the requested IPA branch was actually used and that `build-info.txt` was generated correctly.

The built ISO (and other artifacts) will be available as an artifact attached to the workflow run, one per architecture. Artifact filenames include the IPA branch and architecture for easy identification.

## How to download the ISO

There are three options:

1) From the workflow run artifacts (quickest)

- Go to the **Actions** tab
- Open the latest run of "Build Ironic ISO"
- Download `ironic-centos9-iso-amd64` and/or `ironic-centos9-iso-arm64` (each contains versioned `*.iso`, `*.kernel`, `*.initramfs`, `*-esp.img`, and `*-build-info.txt` files for that architecture)

2) From an automatic per-merge Release (every merge to `master`)

- Every push to `master` (i.e. every merged PR) automatically publishes a **prerelease** GitHub Release tagged `build-<run number>-<short SHA>`, e.g. `build-42-a1b2c3d`, with both arches' artifacts attached.
- Navigate to **Releases** in the repo and grab the topmost one for the latest `master` build.
- These accumulate over time (one per merge); prune old ones from the Releases page if desired.

3) From a version-tagged Release (shareable permalink)

- Create and push a tag, e.g. `v0.1.0`:

```bash
git tag v0.1.0
git push origin v0.1.0
```

- The workflow will publish a full (non-prerelease) Release for that tag and attach the built ISO.
- Navigate to **Releases** in the repo to download the asset.

## Local dry run

To test the build locally on a CentOS 9 Stream system, run:

```bash
./scripts/local_dry_run.sh
```

This will create a Python virtualenv, install the **pinned** builder packages, and build the ISO (using `IPA_BRANCH=stable/2026.1` by default) into an `artifacts/` directory, for the host's native architecture (`amd64` or `arm64`, detected via `uname -m`).

You can override the IPA branch for a local run:

```bash
IPA_BRANCH=stable/2025.2 ./scripts/local_dry_run.sh
```

You can also force a specific target architecture (only meaningful if the host is natively that architecture — see [Architecture Support](#architecture-support-amd64--arm64) above):

```bash
DIB_ARCH=arm64 ./scripts/local_dry_run.sh
```

**Note:** The build script expects to run on CentOS 9 Stream (or compatible) as it requires access to CentOS-provided EFI files at `/boot/efi/EFI/centos/`.

The build mounts tmpfs/loop devices; run as root or via `sudo`, or inside a privileged CentOS Stream 9 container. On CentOS, `isolinux.bin`/`isohdpfx.bin` come from the `syslinux`/`syslinux-nonlinux` packages under `/usr/share/syslinux/` (amd64 only).

### EFI/UEFI and ESP image dependencies

The build process creates:
1. On amd64: a hybrid ISO with BIOS (isolinux) and UEFI (GRUB) boot support. On arm64: a UEFI-only ISO (no BIOS mode on arm64).
2. A separate ESP (EFI System Partition) image using CentOS-provided shim and GRUB binaries

Required packages (automatically installed by the GitHub Actions workflow and `local_dry_run.sh`), by architecture:

amd64:
- `grub2-efi-x64` and `grub2-pc` (for GRUB)
- `shim-x64` (for secure boot support)
- `syslinux` and `syslinux-nonlinux` (for `isolinux.bin`/`isohdpfx.bin`)

arm64:
- `grub2-efi-aa64` (for GRUB)
- `shim-aa64` (for secure boot support)

Both:
- `mtools` and `dosfstools` (for creating FAT EFI/ESP images)

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

