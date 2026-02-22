# Yocto Poky Build Project - DISTRO

This is a comprehensive Yocto build project using repo tool for managing meta-layers, featuring LVM disk layouts, UEFI Secure Boot, u-boot bootloader, Docker support with cgroups v2, OSTree atomic updates with network-resilient update mechanisms, and secure SSH access.

## Overview

This project uses:
- **Yocto Project Poky** (Scarthgap release) as the base distribution
- **Distribution**: poky-sota (DISTRO Distribution) with custom meta-distro layer
- **Machines** (MANDATORY): qemux86-64, qemuarm64 (both must build successfully)
- **repo** tool for managing multiple git repositories
- **meta-openembedded** for additional layer support
- **meta-updater** for OSTree atomic A/B updates (MANDATORY)
- **meta-virtualization** for Docker and container support
- **meta-secure-core** for security features
- **meta-distro** - custom distribution layer with configuration templates

## Primary Applications

This distribution is configured with:
- **Docker-moby** (Docker Engine) - Primary container runtime with cgroups v2
- **Docker-compose** - Multi-container orchestration
- **Virtualization features** - Kernel modules and support for containers
- **OSTree** - Atomic A/B deployment updates (MANDATORY)
- **TPM2** - Hardware security for LUKS key management (MANDATORY)

## Key Features

### 1. **MANDATORY Storage Architecture**
- **LVM**: Root partition MUST reside on LVM logical volume
- **LUKS**: Full disk encryption MANDATORY (AES-256)
- **TPM2**: LUKS keys sealed in TPM2 NV memory with PCR7
- **Unlock Hierarchy**: TPM2 NV+PCR7 → /dev/null OR passphrase (mutually exclusive)
- **Initramfs**: Direct cryptsetup/LVM tools (systemd NEVER used as manager)

### 2. **U-Boot Bootloader** (MANDATORY for all device types)
- **MANDATORY Machines**: qemux86-64 and qemuarm64 (both must build)
- EFI mode for both architectures
- EFI Secure Boot with variable authentication
- TPM2 integration via EFI_TCG2_PROTOCOL
- Measured boot support
- Deploys as BOOTx64.EFI (x86-64) or BOOTAA64.EFI (ARM64)

### 3. **OSTree Atomic Updates** (MANDATORY)
- A/B deployment model with automatic rollback
- Network-resilient update mechanism
- Two-deployment retention (current + previous)
- Periodic update checks every 4 hours
- Shared /var across deployments (separate LVM volume)

### 4. **Security Features**
- Root console locked (empty /etc/securetty)
- SSH key authentication only for root
- TPM2 for LUKS key sealing with PCR7
- Secure Boot chain: UEFI → u-boot → kernel
- LUKS encryption MANDATORY for all system data at rest

### 5. **Container Runtime**
- Docker-moby with cgroups v2 unified hierarchy
- Kernel built-in support (no modules needed)
- Persistent across OSTree updates

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
pylint3 xterm python3-subunit mesa-common-dev zstd liblz4-tool lvm2 cryptsetup \
e2fsprogs

# Add current user to disk group for WIC image creation
sudo usermod -a -G disk $USER
newgrp disk
```

For Fedora:
```bash
sudo dnf install gawk make wget tar bzip2 gzip python3 unzip perl patch \
diffutils diffstat git cpp gcc gcc-c++ glibc-devel texinfo chrpath ccache \
perl-Data-Dumper perl-Text-ParseWords perl-Thread-Queue perl-bignum socat \
python3-pexpect findutils which file cpio python python3-pip xz python3-GitPython \
python3-jinja2 SDL-devel xterm rpcgen mesa-libGL-devel zstd lz4 lvm2 cryptsetup \
e2fsprogs
```

## Project Structure

```
<project-root>/
├── manifests/              # Repo manifest files
│   └── default.xml         # Main manifest defining all layers
├── layers/                 # All meta-layers (created after setup)
│   ├── poky/              # Poky base layer (READ-ONLY)
│   ├── meta-openembedded/ # OpenEmbedded layers (READ-ONLY)
│   ├── meta-updater/      # OSTree atomic updates (READ-ONLY)
│   ├── meta-secure-core/  # Security features (READ-ONLY)
│   ├── meta-virtualization/ # Docker and virtualization support (READ-ONLY)
│   └── meta-distro/       # Custom distribution layer (ALL MODIFICATIONS HERE)
│       ├── conf/
│       │   ├── layer.conf
│       │   ├── machine/include/defaults.inc
│       │   ├── distro/include/defaults.inc
│       │   └── templates/    # Build configuration templates
│       ├── recipes-bsp/
│       │   └── u-boot/       # U-Boot with EFI Secure Boot config
│       │       ├── u-boot_%.bbappend
│       │       └── files/efi-secure-boot.cfg
│       ├── recipes-core/
│       │   ├── images/       # Image recipes
│       │   └── systemd/      # systemd units
│       ├── recipes-kernel/
│       │   └── linux/        # Kernel configuration
│       ├── scripts/          # WIC plugins and kickstart files
│       │   └── lib/wic/
│       │       ├── plugins/source/
│       │       │   └── lvmrootfs.py (LVM+LUKS+TPM2 plugin)
│       │       ├── canned-wks/
│       │       │   ├── lvm-simple.wks.in
│       │       │   ├── lvm-boot-encrypted.wks.in (ACTIVE)
│       │       │   └── lvm-boot-unencrypted.wks.in
│       │       └── README.md
│       ├── files/secureboot/   # Secure Boot key generation
│       └── README.md
├── build/                  # Build directory
│   ├── conf/              # Build configurations
│   ├── tmp/               # Build output
│   └── downloads/         # Source downloads
├── setup-build.sh          # Setup script
├── .gitignore             # Git ignore rules
└── README.md              # This file
```

## Quick Start

### 1. MANDATORY: First Build Setup

**MANDATORY**: For the first build, use the setup script:

```bash
source setup-build.sh
```

This script will:
- Initialize the repo tool with the manifest
- Sync all required meta-layers
- Create the build directory
- Set TEMPLATECONF to use meta-distro templates
- Source the Yocto environment with proper configuration

### 2. MANDATORY: Successive Build Setup

**MANDATORY**: For all successive builds, use:

```bash
source layers/poky/oe-init-build-env
```

This will source the Yocto build environment without re-initializing repo.

### 3. Build an Image

After setup, you can build images:

```bash
# First build: Use setup script (MANDATORY)
source setup-build.sh

# Successive builds: Source environment (MANDATORY)
source layers/poky/oe-init-build-env

# Build verification images (both tested and supported)
bitbake core-image-minimal          # Minimal bootable image
bitbake core-image-full-cmdline     # Full-featured console image with package management

# Build OSTree deployment image (optional)
bitbake demo-image-ostree
```

**Current Build Status**: ✅ Both core-image-minimal and core-image-full-cmdline built successfully

### 4. Run the Image in QEMU

After building, you can run the image in QEMU:

```bash
runqemu qemux86-64 nographic
```

## Configuration

### Machine Configuration

This project uses the **qemux86-64** machine from Yocto's poky layer, with custom settings applied via [layers/meta-distro/conf/machine/include/defaults.inc](layers/meta-distro/conf/machine/include/defaults.inc). The defaults.inc file adds:
- **Bootloader**: u-boot (MANDATORY, EFI mode with Secure Boot support)
- **Initramfs**: core-image-minimal-initramfs-cryptsetup (unbundled, systemd-free)
- **Storage**: LVM (MANDATORY) with LUKS encryption (MANDATORY)
- **Security**: TPM2 (MANDATORY) for LUKS key sealing with PCR7
- **Updates**: OSTree atomic A/B deployments (MANDATORY)
- **Container Runtime**: Docker-moby with cgroups v2
- **Kernel**: Built-in drivers (ext4, vfat, dm, lvm) for fast boot
- **WIC Layout**: lvm-boot-encrypted.wks.in (ACTIVE)
- **Image formats**: wic, wic.bmap, ostree.tar.bz2

### WIC Image Layout

The project uses WKS template files (`.wks.in`) with direct BitBake variable expansion for partition GUIDs and filesystem UUIDs. All layouts use custom WIC plugins in meta-distro.

#### lvm-boot-encrypted.wks.in (ACTIVE - Default)
- EFI System Partition (ESP, 512MB, VFAT, unencrypted)
- XBOOTLDR (/boot, 1GB, ext4, unencrypted)
- LUKS-encrypted LVM physical volume (MANDATORY):
  - Root logical volume (ext4)
  - Var logical volume (ext4)

#### lvm-simple.wks.in (Available)
- EFI System Partition (ESP, 512MB)
- LUKS-encrypted LVM partition (root logical volume only)

**Template Processing**:
- Templates use direct variable expansion: `${PARTTYPE_ESP}`, `${FSUUID_ROOT}`
- Values defined in `layers/meta-distro/conf/distro/include/defaults.inc`
- WIC processes `.wks.in` files at image creation time

**Discovery Rules**:
- Physical partitions: Identified by GPT partition type GUID
- Filesystems: Identified by filesystem UUID (no VG/LV names in fstab)
- Root discovery: `root=UUID=8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11`
- Kernel uses `root=UUID=<UUID_ROOT>` (no device paths or VG/LV names)

WIC plugins and kickstart files are in [layers/meta-distro/scripts/lib/wic/](layers/meta-distro/scripts/lib/wic/). See the [WIC README](layers/meta-distro/scripts/lib/wic/README.md) for detailed plugin documentation.

To switch layouts, edit `build/conf/local.conf`:
```bitbake
WKS_FILE = "lvm-simple.wks.in"
```

### Distribution Configuration

This project uses the **poky-sota** distribution from meta-updater (DISTRO Distribution), which provides OSTree-based atomic A/B updates (MANDATORY). The distribution includes:
- **OSTree**: Atomic updates with automatic rollback capability (MANDATORY)
- **Update Mechanism**: Periodic pull with network-resilient resume
- **Bootloader**: u-boot (MANDATORY for all device types)
- **Security**: Root console locked, SSH key authentication, TPM2
- **Storage**: LVM (MANDATORY) with LUKS encryption (MANDATORY)
- **Containers**: Docker-moby with cgroups v2
- **Init System**: systemd (target system only, NOT in initramfs)

**Key Architecture Points**:
- **Primary Image**: core-image-minimal (production and testing)
- **OSTree Image**: demo-image-ostree (available for deployments)
- **Initramfs**: systemd is NEVER used as manager (uses busybox)
- **LUKS Unlock**: TPM2 NV+PCR7 → /dev/null OR passphrase (mutually exclusive)
- **Boot Sequence**: LUKS unlock → LVM activation → OSTree prepare → switch_root

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
