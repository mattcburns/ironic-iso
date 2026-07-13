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
- Open a pull request targeting `master` (builds and uploads artifacts for PR testing)
- Or trigger manually:

1. Go to **Actions** tab
2. Choose **Build Ironic ISO**
3. Click **Run workflow**
4. The `ipa_branch` field is **pre-filled** with the default `stable/2026.1`. You can leave it as-is or enter a different value (e.g. `stable/2025.2`, `9.7.0`, a git tag, or a commit SHA).

After the build completes, you will see a **"Validate build-info.txt"** step in the logs. This step confirms that the requested IPA branch was actually used and that `build-info.txt` was generated correctly.

The built ISO (and other artifacts) will be available as an artifact attached to the workflow run. Artifact filenames include the IPA branch for easy identification. Artifacts are retained for **7 days**.

## How to download the ISO

There are three options:

1) From a pull request (best for testing before merge)

- Open the PR targeting `master`
- Wait for the **Build Ironic ISO** check to finish
- Open the check / linked Actions run → **Artifacts**
- Download `ironic-centos9-iso` (versioned `*.iso`, `*.kernel`, `*.initramfs`, `*.img`, and `build-info.txt`)
- Use the kernel + initramfs in Ironic with dynamic-login append params as documented below

2) From any workflow run (push, PR, or manual)

- Go to the **Actions** tab
- Open the relevant run of "Build Ironic ISO"
- Download the artifact named `ironic-centos9-iso`

3) From a GitHub Release (shareable permalink)

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

## Dynamic login (boot-time credentials)

No root password is baked into the image. The build includes diskimage-builder’s [`dynamic-login`](https://docs.openstack.org/diskimage-builder/latest/elements/dynamic-login/README.html) element so you can inject a root password and/or SSH key **at boot** via kernel command-line parameters. Prefer the **kernel + initramfs** artifacts (not only the ISO) so Ironic can pass append parameters cleanly.

### Generate credentials

**Root password** must be encrypted, then base64-encoded:

```bash
# Produce the value for rootpwd=
openssl passwd -6 -stdin <<< 'YOUR_PASSWORD' | base64 -w 0
```

**SSH public key** is passed as-is (quotes required on the kernel cmdline):

```text
sshkey="ssh-rsa AAAA... user@host"
```

Example append fragments (always **quote** values):

```text
rootpwd="<BASE64_OF_ENCRYPTED_HASH>"
sshkey="ssh-rsa AAAA... user@host"
# CentOS may block login under enforcing SELinux; optional for troubleshooting:
selinux=0
```

### Global configuration (conductor-wide)

Use this only in isolated lab/dev environments when every IPA boot should get the same login hooks. Do **not** put a real production password in global conductor config.

In `/etc/ironic/ironic.conf` (section and option names can vary by release):

```ini
[pxe]
# Modern Ironic uses kernel_append_params (legacy name: pxe_append_params)
kernel_append_params = rootpwd="<BASE64_HASH>" sshkey="ssh-rsa AAAA... user@host" selinux=0
```

1. Generate `rootpwd` and/or prepare `sshkey` as above.
2. Set `kernel_append_params` (or legacy `pxe_append_params`) under the boot-related section(s) your deployment uses (`[pxe]`, and any equivalent for other boot interfaces such as Redfish virtual media).
3. Restart `ironic-conductor` so conductors reload the config.
4. Subsequent IPA boots for nodes using that conductor receive the parameters.

### Per-node configuration (troubleshooting one device)

Preferred path for production: inject credentials for a **single** node without changing fleet-wide config.

```bash
# Temporary / instance-scoped append params (exact property may depend on boot interface)
baremetal node set <node> \
  --instance-info kernel_append_params='rootpwd="<BASE64_HASH>" selinux=0'

# Some sites store boot append data on driver_info instead; use what your
# boot interface documents for extra kernel arguments.
```

Operator workflow:

1. Generate a one-time password hash and/or use a temporary SSH public key.
2. Set append params **only** on the node under investigation (`instance_info` for temporary use, or `driver_info` if that is how your boot driver expects them).
3. Reboot or re-run deploy/clean/inspect so the node boots with the new kernel cmdline.
4. Log in as root on console or SSH; collect IPA logs.
5. **Remove** the temporary `rootpwd` / `sshkey` from that node when finished so the next boot is locked down again.

### ISO-only boots

The hybrid ISO’s `isolinux.cfg` uses a fixed `APPEND` line. Dynamic-login params for pure ISO/virtual-media boots without Ironic-managed kernel append require editing that boot config, or (recommended) publishing **kernel + initramfs** to Ironic and passing params via the global or per-node methods above.

### Security notice

- Prefer **per-node** temporary credentials for troubleshooting.
- Global password/SSH injection is convenient for labs but is a security risk on shared or production conductors.
- Base64-encoded password hashes avoid `$` escaping issues on the kernel command line.
- Always quote parameter values.

### Other build variables

You can still override these when building:

- `IPA_BRANCH` — Ironic Python Agent git branch/tag (default `stable/2026.1`)
- `IMAGE_NAME` — base name for output files (default incorporates the IPA branch)
- `DIB_RELEASE`, `BASE_DISTRO`, etc. (see the top of `build_ironic_iso.sh`)
