# ironic-iso

GitHub Actions–based pipeline to build custom OpenStack Ironic images in ISO format using:

- `ironic-python-agent-builder`
- `diskimage-builder`
- CentOS Stream 9 as the base OS

## GitHub Actions Workflow

The workflow:

- Installs Python and dependencies on `ubuntu-latest`
- Installs `diskimage-builder` and `ironic-python-agent-builder`
- Builds a CentOS Stream 9 based Ironic ISO
- Uploads the resulting ISO as a build artifact

## How to trigger

- Push to `main`
- Open a pull request targeting `main`
- Or trigger manually:

1. Go to **Actions** tab
2. Choose **Build Ironic ISO**
3. Click **Run workflow**

The built ISO will be available as an artifact attached to the workflow run.

## Local dry run

To test the build locally on a Debian/Ubuntu-like system, run:

```bash
./scripts/local_dry_run.sh
```

This will create a Python virtualenv, install the required packages, and build the ISO into an `artifacts/` directory.
