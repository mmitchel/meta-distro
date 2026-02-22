# GitHub Actions Workflows

This directory contains GitHub Actions workflows for automated building and validation of the Yocto project.

## Workflows

### build.yml - Main Build Workflow

Builds the Yocto image with configurable parameters.

#### Triggers
- Push to `main` or `develop` branches
- Pull requests to `main` branch
- Manual dispatch (workflow_dispatch)

#### Configuration Variables

The workflow uses repository variables that can be set in GitHub repository settings:

**Repository Variables** (Settings → Secrets and variables → Actions → Variables):
- `YOCTO_DISTRO` - Distribution to build (default: `poky-sota`)
- `YOCTO_MACHINE` - Target machine (default: `qemux86-64`)
- `YOCTO_IMAGE` - Image to build (default: `core-image-minimal`)

#### Manual Dispatch Inputs

When running manually, you can override:
- **machine**: Target machine to build for
- **image**: Image recipe to build
- **clean_build**: Whether to clean sstate and downloads cache (default: false)

#### Features

- **Caching**: Downloads and sstate are cached between builds for faster execution
- **Disk Space Optimization**: Removes unnecessary tools before build
- **Parallel Building**: Uses all available CPU cores
- **Artifact Upload**: Built images are uploaded as GitHub artifacts (30-day retention)
- **Build Summary**: Generates a summary in the GitHub Actions UI
- **Error Logging**: Shows last 100 lines of build log on failure

#### Build Time

- Initial build: 4-6 hours
- Incremental builds: 1-2 hours (with cache)

### validate.yml - Syntax Check Workflow

Validates configuration files and scripts without performing a full build.

#### Triggers
- Pull requests affecting meta-distro layer or manifests
- Push to main branch

#### Checks
- Shell script syntax (shellcheck)
- Python syntax (pyflakes)
- YAML syntax (yamllint)
- XML manifest validation (xmllint)
- Common BitBake configuration issues

## Usage

### Setting Up Repository Variables

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click on **Variables** tab
4. Click **New repository variable**
5. Add the following variables:

```
Name: YOCTO_DISTRO
Value: poky-sota

Name: YOCTO_MACHINE
Value: qemux86-64

Name: YOCTO_IMAGE
Value: core-image-minimal
```

### Running a Manual Build

1. Go to **Actions** tab in your repository
2. Select **Yocto Build** workflow
3. Click **Run workflow**
4. Fill in optional parameters:
   - Machine: `qemux86-64-demo` or `qemux86-64`
   - Image: `core-image-minimal` or `core-image-full-cmdline`
   - Clean build: Check to rebuild from scratch
5. Click **Run workflow**

### Downloading Build Artifacts

1. Go to **Actions** tab
2. Click on a completed workflow run
3. Scroll down to **Artifacts** section
4. Download `yocto-images-<machine>-<run-number>.zip`
5. Extract to get:
   - `*.wic` - Disk image file
   - `*.wic.bmap` - Block map for faster flashing
   - `*.manifest` - Package manifest
   - `build-info.txt` - Build information

## Storage Considerations

- **Runner disk space**: ~60GB free (after cleanup)
- **Cache storage**: Downloads and sstate can consume 20-30GB
- **Artifacts**: WIC images are typically 2-4GB
- **Retention**: Artifacts are kept for 30 days

## Optimization Tips

### Speed up builds

1. **Enable caching**: Keep `clean_build: false` for most builds
2. **Use self-hosted runners**: Much faster than GitHub-hosted runners
3. **Incremental builds**: Only rebuild when necessary

### Reduce costs

1. **Limit concurrent builds**: Set concurrency limits in workflow
2. **Clean old artifacts**: Manually delete old workflow runs
3. **Use scheduled builds**: Build only on a schedule instead of every push

### Self-hosted runners

For faster builds, consider using self-hosted runners:

```yaml
jobs:
  build:
    runs-on: self-hosted
    # ... rest of configuration
```

Requirements for self-hosted runner:
- Ubuntu 22.04 or later
- 100GB+ free disk space
- 16GB+ RAM
- 8+ CPU cores recommended

## Troubleshooting

### Build fails with disk space errors

- Increase runner disk space or use self-hosted runner
- Enable `clean_build` to remove old cache

### Build times out

- Increase `timeout-minutes` in workflow
- Use self-hosted runner with more CPU cores

### Cache not being restored

- Check cache key patterns match
- Verify cache hasn't expired (7 days for GitHub)
- Try manual `clean_build` to reset

### Artifacts not uploaded

- Check build actually completed successfully
- Verify artifact path exists
- Check repository storage quota

## Example: Building Different Configurations

### Build for different machine

```bash
# Via repository variable
YOCTO_MACHINE=qemuarm64

# Via manual dispatch
Machine: qemuarm64
```

### Build different image

```bash
# Via repository variable
YOCTO_IMAGE=core-image-full-cmdline

# Via manual dispatch
Image: core-image-full-cmdline
```

### Build with clean cache

Use manual dispatch and check **clean_build** option.

## CI/CD Integration

The workflows can be extended for full CI/CD:

1. **Test stage**: Add QEMU testing after build
2. **Deploy stage**: Deploy images to artifact server or cloud storage
3. **Release stage**: Create GitHub releases with images
4. **Notification**: Send build status to Slack/Email

Example additions:

```yaml
- name: Test image in QEMU
  run: |
    timeout 300 runqemu qemux86-64 nographic qemuparams="-m 2048"

- name: Create release
  if: startsWith(github.ref, 'refs/tags/')
  uses: softprops/action-gh-release@v1
  with:
    files: artifacts/*.wic*
```
