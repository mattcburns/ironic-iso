# ironic-iso

GitHub Actions–based pipeline to build custom OpenStack Ironic images in ISO format using:

- `ironic-python-agent-builder`
- `diskimage-builder`
- CentOS Stream 9 as the base OS

The resulting ISO is hybrid and supports both BIOS/legacy (isolinux) and UEFI (GRUB) boot modes.

## GitHub Actions Workflow

The workflow:

- Installs Python and dependencies on `ubuntu-latest`
- Installs `diskimage-builder` and `ironic-python-agent-builder`
- Builds a CentOS Stream 9 based Ironic ISO
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

## Local dry run

To test the build locally on a Debian/Ubuntu-like system, run:

```bash
./scripts/local_dry_run.sh
```

This will create a Python virtualenv, install the required packages, and build the ISO into an `artifacts/` directory.

### EFI/UEFI dependencies

Hybrid ISO creation requires GRUB for UEFI and FAT tooling for the embedded EFI image. The `local_dry_run.sh` script installs:

- `grub-efi-amd64-bin` and `grub-pc-bin` (for `grub-mkstandalone`)
- `mtools` and `dosfstools` (for creating the FAT EFI image)

On RHEL/CentOS/Fedora, install the equivalents (e.g., `grub2-efi-x64`, `grub2-pc`, `mtools`, `dosfstools`).

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

