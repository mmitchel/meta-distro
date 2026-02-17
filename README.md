# Yocto Poky Build Project - Demo

This project demonstrates how to set up a Yocto build environment using the `repo` tool to manage multiple meta-layers.

## Overview

This project uses:
- **Yocto Project Poky** (Scarthgap release) as the base distribution
- **repo** tool for managing multiple git repositories
- **meta-openembedded** for additional layer support
- **meta-updater** for OTA update support (Uptane)
- **meta-virtualization** for Docker and container support
- **meta-distro** - custom distribution layer with configuration templates

## Primary Applications

This distribution is configured with:
- **Docker-moby** (Docker Engine) - Primary container runtime
- **Docker-compose** - Multi-container orchestration
- **Virtualization features** - Kernel modules and support for containers

## Prerequisites

Before you begin, ensure you have the following installed:

### 1. Install repo tool

```bash
mkdir -p ~/.bin
curl https://storage.googleapis.com/git-repo-downloads/repo > ~/.bin/repo
chmod a+rx ~/.bin/repo
export PATH=~/.bin:$PATH
```

Add `~/.bin` to your PATH permanently by adding to `~/.bashrc` or `~/.zshrc`:
```bash
export PATH=~/.bin:$PATH
```

### 2. Install Yocto Build Dependencies

For Ubuntu/Debian:
```bash
sudo apt-get install gawk wget git diffstat unzip texinfo gcc build-essential \
chrpath socat cpio python3 python3-pip python3-pexpect xz-utils debianutils \
iputils-ping python3-git python3-jinja2 libegl1-mesa libsdl1.2-dev \
pylint3 xterm python3-subunit mesa-common-dev zstd liblz4-tool
```

For Fedora:
```bash
sudo dnf install gawk make wget tar bzip2 gzip python3 unzip perl patch \
diffutils diffstat git cpp gcc gcc-c++ glibc-devel texinfo chrpath ccache \
perl-Data-Dumper perl-Text-ParseWords perl-Thread-Queue perl-bignum socat \
python3-pexpect findutils which file cpio python python3-pip xz python3-GitPython \
python3-jinja2 SDL-devel xterm rpcgen mesa-libGL-devel zstd lz4
```

## Project Structure

```
demo/
├── manifests/              # Repo manifest files
│   └── default.xml         # Main manifest defining all layers
├── layers/                 # All meta-layers (created after setup)
│   ├── poky/              # Poky base layer
│   ├── meta-openembedded/ # OpenEmbedded layers
│   ├── meta-updater/      # OTA update layer
│   ├── meta-virtualization/ # Docker and virtualization support
│   └── meta-distro/       # Custom distribution layer
│       ├── conf/
│       │   ├── layer.conf
│       │   ├── machine/
│       │   │   └── include/
│       │   │       └── defaults.inc
│       │   ├── distro/
│       │   │   └── include/
│       │   │       └── defaults.inc
│       │   └── templates/    # Configuration templates
│       │       ├── local.conf.sample
│       │       ├── bblayers.conf.sample
│       │       └── conf-notes.txt
│       ├── scripts/          # WIC plugins and kickstart files
│       │   └── lib/wic/
│       │       ├── plugins/source/
│       │       │   └── lvmrootfs.py (custom WIC plugin for LVM layouts)
│       │       ├── canned-wks/
│       │       │   ├── lvm-boot.wks.in
│       │       │   ├── lvm-boot-encrypted.wks.in
│       │       │   └── lvm-simple.wks.in
│       │       └── README.md
│       └── README.md
├── build/                  # Build directory (at project root)
│   ├── conf/              # Build configurations
│   │   ├── local.conf
│   │   └── bblayers.conf
│   ├── tmp/               # Build output
│   └── downloads/         # Source downloads
├── setup-build.sh          # Setup script
├── .gitignore             # Git ignore rules
└── README.md              # This file
```

## Quick Start

### 1. Initialize and Setup Build Environment

Run the setup script:

```bash
./setup-build.sh
```

This script will:
- Initialize the repo tool with the manifest
- Sync all required meta-layers
- Create the build directory
- Set TEMPLATECONF to use meta-distro templates
- Source the Yocto environment with proper configuration

### 2. Manual Setup (Alternative)

If you prefer to set up manually:

```bash
# Initialize repo
repo init -u file://$(pwd)/manifests -b master -m default.xml

# Sync repositories
repo sync

# Source the build environment with TEMPLATECONF
TEMPLATECONF=layers/meta-distro/conf/templates source layers/poky/oe-init-build-env build
```

### 3. Build an Image

After setup, you can build images:

```bash
# Source the environment (if not already done)
TEMPLATECONF=layers/meta-distro/conf/templates source layers/poky/oe-init-build-env build

# Build primary production image (OSTree A/B)
bitbake demo-image-ostree

# Build testing image (minimal)
bitbake core-image-minimal
```

### 4. Run the Image in QEMU

After building, you can run the image in QEMU:

```bash
runqemu qemux86-64
```

## Configuration

### Machine Configuration

This project uses the **qemux86-64** machine from Yocto's poky layer, with custom settings applied via [layers/meta-distro/conf/machine/include/defaults.inc](layers/meta-distro/conf/machine/include/defaults.inc). The defaults.inc file adds:
- Bundled initramfs (core-image-minimal-initramfs)
- Docker-specific kernel modules
- LVM-based disk layout with WIC
- Image formats: wic, wic.bmap
- Based on standard qemux86-64 with custom enhancements

### WIC Image Layout

The project uses WKS template files (`.wks.in`) with variable substitution for partition GUIDs and filesystem UUIDs. The LVM layouts (`lvm-boot*`) use the `lvmrootfs` plugin; `lvm-simple.wks.in` uses the standard Poky `rootfs` source.

#### lvm-boot.wks.in (optional)
- EFI System Partition (ESP)
- XBOOTLDR (/boot)
- LUKS-encrypted LVM partition (rootfs + optional data/log volumes)

#### lvm-boot-encrypted.wks.in (optional)
- EFI System Partition (ESP)
- XBOOTLDR (/boot)
- LUKS-encrypted LVM partition (rootfs + /var)

#### lvm-simple.wks.in (default)
- EFI System Partition (ESP)
- LUKS-encrypted root partition (rootfs)

**Template Processing**:
- Templates use placeholders like `@PARTTYPE_ESP@` and `@UUID_ROOT@`
- Values come from `layers/meta-distro/conf/distro/include/defaults.inc`
- Processed `.wks` files are created in the build workdir

**Discovery Rules**:
- Physical partitions are identified by GPT partition type GUID
- Filesystems are identified by filesystem UUID
- Kernel uses `root=UUID=<UUID_ROOT>` (no device paths or VG/LV names)

WIC plugins and kickstart files are in [layers/meta-distro/scripts/lib/wic/](layers/meta-distro/scripts/lib/wic/). See the [WIC README](layers/meta-distro/scripts/lib/wic/README.md) for detailed plugin documentation.

To switch layouts, edit `build/conf/local.conf`:
```bitbake
WKS_FILE = "lvm-simple.wks.in"
```

### Distribution Configuration

This project uses the **poky-sota** distribution from meta-updater, which provides OTA (Over-The-Air) update capabilities using the Uptane framework. The distribution includes:
- OSTree for atomic updates
- Aktualizr OTA client
- Secure update mechanisms
- Systemd as init system

The local configuration template is in [layers/meta-distro/conf/templates/local.conf.sample](layers/meta-distro/conf/templates/local.conf.sample).

### Local Configuration

Edit `build/conf/local.conf` to customize:

- **MACHINE**: Target hardware (default: `qemux86-64`)
  - `qemux86-64` - QEMU x86-64 with custom settings from defaults.inc (default)
  - `qemux86-64` - Standard QEMU x86-64 emulator
  - `qemuarm64` - QEMU ARM 64-bit
  - `beaglebone-yocto` - BeagleBone Black
  - `genericx86-64` - Generic x86-64 hardware

- **DISTRO**: Distribution (default: `poky-sota` from meta-updater)

- **BB_NUMBER_THREADS**: Number of BitBake threads
- **PARALLEL_MAKE**: Number of parallel make jobs
- **DL_DIR**: Download directory for source tarballs
- **SSTATE_DIR**: Shared state cache directory

### Layer Configuration

Edit `build/conf/bblayers.conf` to add or remove layers. The default configuration includes:
- poky/meta (core)
- poky/meta-poky
- poky/meta-yocto-bsp
- meta-openembedded layers (meta-oe, meta-python, meta-networking, meta-filesystems)
- meta-virtualization (Docker, container support)
- meta-updater (OTA updates)
- meta-distro (custom distribution)

### Configuration Templates

Configuration templates are stored in [layers/meta-distro/conf/templates/](layers/meta-distro/conf/templates/):
- `local.conf.sample` - Build configuration template
- `bblayers.conf.sample` - Layer configuration template
- `conf-notes.txt` - Build information displayed after setup

The templates are automatically applied when using `TEMPLATECONF=layers/meta-distro/conf/templates` with oe-init-build-env.

## Adding More Layers

To add additional layers, edit `manifests/default.xml`:

```xml
<project name="meta-mylayer"
         remote="github"
         revision="scarthgap"
         path="layers/meta-mylayer"/>
```

Then run:
```bash
repo sync
```

And add the layer to `build/conf/bblayers.conf`:
```
BBLAYERS += "${PROJECT_ROOT}/layers/meta-mylayer"
```

## Common Commands

```bash
# Sync all repositories
repo sync

# Update to latest changes
repo sync -c

# Show repository status
repo status

# Clean build
rm -rf build/tmp

# BitBake commands
bitbake <image-name>           # Build an image
bitbake -c cleanall <recipe>   # Clean a recipe
bitbake -c listtasks <recipe>  # List available tasks
bitbake-layers show-layers     # Show all layers

# Docker commands (after boot)
docker info                    # Verify Docker installation
docker run hello-world         # Test Docker
docker-compose version         # Check docker-compose
```

## Docker Usage

After building and booting the image, Docker will be available:

```bash
# Start Docker daemon (if not auto-started)
systemctl start docker
systemctl enable docker

# Run containers
docker run -d --name nginx -p 80:80 nginx
docker ps

# Use docker-compose
docker-compose up -d
```

## Available Images

- `core-image-minimal` - Small image capable of booting a device (includes Docker)
- `core-image-base` - Console-only image with more features (includes Docker)
- `core-image-full-cmdline` - Full command-line system (includes Docker)
- `core-image-sato` - Image with Sato UI
- `core-image-weston` - Wayland/Weston compositor

**Note**: All images include docker-moby and docker-compose by default.

## Troubleshooting

### Docker Issues

If Docker fails to start:
```bash
# Check Docker status
systemctl status docker

# Check kernel modules
lsmod | grep overlay
lsmod | grep xt_nat

# View Docker logs
journalctl -u docker
```

### Disk Space Issues

Yocto builds require significant disk space (50GB+ recommended for Docker builds). Monitor:
```bash
df -h
```

### Build Failures

Clean and rebuild:
```bash
bitbake -c cleanall <failing-recipe>
bitbake <image-name>
```

### Network Issues

If downloads fail, check your internet connection and proxy settings in `local.conf`:
```
HTTP_PROXY = "http://proxy.example.com:8080"
HTTPS_PROXY = "http://proxy.example.com:8080"
```

## CI/CD with GitHub Actions

This project includes GitHub Actions workflows for automated building and validation.

### Automated Builds

Builds are automatically triggered on:
- Push to `main` or `develop` branches
- Pull requests to `main`
- Manual workflow dispatch

### Configuration Variables

Set these repository variables in GitHub (Settings → Secrets and variables → Actions → Variables):

- `YOCTO_DISTRO` - Distribution (default: `poky-sota`)
- `YOCTO_MACHINE` - Target machine (default: `qemux86-64`)
- `YOCTO_IMAGE` - Image to build (default: `core-image-minimal`)

### Running Manual Builds

1. Go to **Actions** tab in GitHub
2. Select **Yocto Build** workflow
3. Click **Run workflow**
4. Optionally override machine, image, or enable clean build
5. Download artifacts after build completes

See [.github/workflows/README.md](.github/workflows/README.md) for detailed CI/CD documentation.

## Resources

- [Yocto Project Documentation](https://docs.yoctoproject.org/)
- [Yocto Project Wiki](https://wiki.yoctoproject.org/)
- [OpenEmbedded Layers Index](https://layers.openembedded.org/)
- [repo Tool Documentation](https://gerrit.googlesource.com/git-repo/)

## License

This project structure is provided as-is for demonstration purposes. Individual components (Poky, meta-layers) have their own licenses.
