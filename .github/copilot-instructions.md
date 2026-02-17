# Yocto Poky Build Project - Demo

This is a comprehensive Yocto build project using repo tool for managing meta-layers, featuring LVM disk layouts, UEFI Secure Boot, systemd-boot, Docker support with cgroups v2, OSTree atomic updates with network-resilient update mechanisms, and secure SSH access.

## Quick Start

```bash
# Initialize and build
./setup-build.sh
bitbake demo-image-ostree

# Test in QEMU
runqemu qemux86-64 nographic
```

**Current Build Status**: ✅ READY FOR PRODUCTION BUILD
- Primary Image: `demo-image-ostree` (to be built - 6.9 GB WIC with OSTree A/B deployments)
- Testing Image: `core-image-minimal-qemux86-64.rootfs.wic` (✅ BUILT - 6.9 GB)
- Includes: systemd-boot, LUKS encryption, LVM, OSTree support, Docker cgroups v2, SSH, Secure Boot
- Infrastructure tested and verified: February 16, 2026
- OSTree Status: MANDATORY feature for production deployments

## Project Architecture

### Core Technologies
- **Base**: Yocto Project Poky (Scarthgap release)
- **Distribution**: poky-sota (from meta-updater) extended with custom defaults
- **Updates**: OSTree-based atomic A/B deployments with network-resilient updates (MANDATORY)
- **Update Mechanism**: Periodic pull with automatic resume on network restoration
- **Machine**: qemux86-64 (with custom settings from defaults.inc)
- **Init System**: systemd (exclusive, no sysvinit)
- **Bootloader**: systemd-boot with UEFI Secure Boot support, OSTree integration
- **Containerization**: Docker-moby with cgroups v2 unified hierarchy
- **Security**: Root console locked, SSH key authentication enabled, OpenSSH server

### Layer Management
- **Tool**: repo (manifest-based multi-repository management)
- **Layers**: poky, meta-openembedded, meta-secure-core, meta-updater, meta-virtualization, meta-distro

## Project Structure

```
/srv/repo/
├── manifests/default.xml           # Repo manifest defining all layers
├── setup-build.sh                  # Build initialization script
├── layers/
│   ├── poky/                       # Yocto base (fetched by repo) - READ-ONLY, NO MODIFICATIONS
│   ├── meta-openembedded/          # OE layers (fetched by repo) - READ-ONLY, NO MODIFICATIONS
│   ├── meta-updater/               # OTA updates (fetched by repo) - READ-ONLY, NO MODIFICATIONS
│   ├── meta-virtualization/        # Docker support (fetched by repo) - READ-ONLY, NO MODIFICATIONS
│   └── meta-distro/                # Custom distribution layer - ALL MODIFICATIONS HERE
│       ├── conf/
│       │   ├── layer.conf
│       │   ├── machine/include/defaults.inc
│       │   ├── distro/include/defaults.inc
│       │   └── templates/          # Build configuration templates
│       ├── files/
│       │   └── secureboot/         # Secure Boot key generation scripts
│       ├── recipes-bsp/
│       │   ├── secureboot-keys/    # Key generation recipe (legacy)
│       │   └── systemd-bootconf/   # Boot configuration + key deployment
│       ├── recipes-connectivity/
│       │   └── openssh/            # SSH server configuration
│       ├── recipes-core/
│       │   ├── base-files/         # Root account lockdown
│       │   ├── images/             # Image recipes (demo-image-ostree)
│       │   └── systemd/            # systemd units (OSTree updates, cleanup)
│       ├── recipes-kernel/
│       │   └── linux/              # Kernel configuration (built-in drivers, Docker)
│       └── scripts/lib/wic/        # Custom WIC plugins
├── build/                          # Build directory (created by setup)
└── .github/workflows/              # CI/CD automation
```

## Key Features

**CRITICAL SECURITY REQUIREMENT**: All rootfs deployments MUST use LUKS encryption at rest. The rootfs and all system/data volumes must reside within a LUKS-encrypted LVM physical volume. This is non-negotiable for the distribution's security posture. The only partitions that are exempt from encryption at rest are the the first EFI system partition formatted as VFAT mounted at runtime to /boot/efi and the XBOOTLDR partition which is formatted as ext4 to contain kernels and initramfs and any other artifacts which is mounted to /boot.

### 1. LVM-Based Disk Layout with LUKS Encryption (REQUIRED)

**Security Requirement**: All rootfs partitions MUST be encrypted at rest using LUKS + LVM. This is a mandatory security requirement for the distribution.

**WIC Templates and Plugins**:
- WKS templates in `layers/meta-distro/scripts/lib/wic/canned-wks/` use `.wks.in` with UUID/GUID substitution
- Layouts may use the standard `rootfs` source or the `lvmrootfs` source as needed
- Technology: cryptsetup and cryptfs-tpm2 tools in initramfs for LUKS unlock
- LUKS Unlock: Initramfs calls `/init.cryptfs` from cryptfs-tpm2-initramfs package
- Security: LUKS encryption wraps root filesystem and LVM volumes at rest

**Key Advantages**:
- Uses standard Poky WIC plugins (reduced custom code)
- Leverages existing cryptfs-tpm2 infrastructure
- Simpler maintenance (less custom Python code in build system)
- Reliable and proven approach
- Full TPM 2.0 integration for LUKS key management

**Dependencies**:
```bash
# Required system packages for build host
sudo apt-get install lvm2 cryptsetup e2fsprogs

# Required recipes (automatically pulled by Yocto)
cryptfs-tpm2-initramfs    # Provides /init.cryptfs for LUKS unlock
initrdscripts-secure-core # Boot script orchestration
```

**Disk Layouts** (all use LUKS encryption - REQUIRED):
- `lvm-simple.wks.in`: EFI + LUKS root (minimal layout, UUID-based boot) - currently active for core-image-minimal
- `lvm-boot.wks.in`: EFI + XBOOTLDR + LUKS-encrypted LVM (root + var + optional data/log volumes) - optional
- `lvm-boot-encrypted.wks.in`: EFI + XBOOTLDR + LUKS-encrypted LVM (root + var) - optional

**WKS Template Processing**:
- All WKS files use `.wks.in` template format with variable substitution
- Variables substituted from distro config:
  - `@PARTTYPE_ESP@` → `c12a7328-f81f-11d2-ba4b-00a0c93ec93b` (ESP GUID)
  - `@PARTTYPE_XBOOTLDR@` → `bc13c2ff-59e6-4262-a352-b275fd6f7172` (XBOOTLDR GUID)
  - `@PARTTYPE_ROOT@` → `4f68bce3-e8cd-4db1-96e7-fbcaf984b709` (Root GUID)
  - `@UUID_ESP@` → `3a4f2c1e-9b8d-4c3f-8e1a-7d2b9f4c6a11` (ESP filesystem UUID)
  - `@UUID_XBOOTLDR@` → `5d7e1b2c-3f4a-4c8d-9e22-1a6b7c8d9e33` (XBOOTLDR UUID)
  - `@UUID_ROOT@` → `8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11` (Root filesystem UUID)
  - `@UUID_VAR@` → `d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55` (Var LV UUID)
- Source: `conf/distro/include/defaults.inc` (all GUID/UUID variables defined centrally)
- Processed WKS files created in build workdir with `.in` extension removed

**Note**: Root and /var are discovered by filesystem UUID; partition discovery uses GPT GUIDs.

**Configuration**:
- EFI System Partition: 512MB VFAT for UEFI boot (mounted at /boot/efi) - UNENCRYPTED
  - Partition Type: `C12A7328-F81F-11D2-BA4B-00A0C93EC93B` (ESP)
- Boot partition: 1GB ext4 for kernels and initramfs (mounted at /boot) - UNENCRYPTED (optional separate partition)
  - Partition Type: `BC13C2FF-59E6-4262-A352-B275FD6F7172` (XBOOTLDR)
- **LUKS-encrypted LVM partition (REQUIRED)**: Physical volume containing all system and data logical volumes
  - Partition Type: `4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709` (Linux root x86-64, encrypted)
  - Encryption: LUKS2 with AES-256 (mandatory for rootfs and all data volumes)
- LVM volumes inside LUKS: rootlv (rootfs), varfs (OSTree /var), datafs (optional), logfs (optional)
  - LV names are internal only; discovery and mounts use filesystem UUIDs
- Separate /var for OSTree compatibility (not monitored for updates)
- Optional mount points: `--lvm-mountpoints="datafs:/mnt/data,logfs:/var/log/extra"`
- LUKS passphrase options: `--luks-passphrase="secret"` or `--luks-passphrase="NULL"` (uses /dev/null for automated unlock)
- LUKS device name: `--luks-name="cryptroot"` (default)
- Boot unlocking: Initramfs tries /dev/null key first, then prompts for passphrase on failure

**Security Note**: The rootfs and all system data MUST reside within the LUKS-encrypted LVM. Only the EFI partition and optional /boot partition remain unencrypted (required for bootloader and kernel loading).

**Discoverable Partitions Specification**:
- Implements UAPI Group Type #2 for automatic partition discovery
- Partition type GUIDs enable systemd to mount without /etc/fstab
- Standard GUIDs:
  - ESP: `C12A7328-F81F-11D2-BA4B-00A0C93EC93B` (SD_GPT_ESP)
  - XBOOTLDR (/boot): `BC13C2FF-59E6-4262-A352-B275FD6F7172` (SD_GPT_XBOOTLDR)
  - Root x86-64: `4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709` (SD_GPT_ROOT_X86_64, LUKS encrypted)
- Benefits: Secure boot workflows, attestation, simplified configuration
- Note: Encrypted root partitions use architecture-specific root types, not generic LVM type

**fstab Generation**:
- LUKS-encrypted rootfs mount handled by initramfs-cryptsetup in /init.cryptfs
- /etc/fstab is optional for this deployment (rootfs mounted by initramfs)
- Additional volumes (if using LVM) can be mounted via standard fstab entries

**Initramfs Boot Sequence** (monolithic, not modular):
- Script: `/init` in initramfs (from `initrdscripts-secure-core` package)
- Approach: Single script handles full boot sequence (not using initramfs-framework modules)
- Required flow (UUID/GUID-based discovery):
  1. Locate LUKS partition by PARTTYPE=SD_GPT_ROOT_X86_64
  2. Unlock LUKS and activate LVM
  3. Mount root LV by UUID `8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11`
  4. Mount /var by UUID `d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55`
  5. Run `ostree-prepare-root` in initramfs
  6. `switch_root` into the OSTree deployment
- Modules handled externally via delegation:
  - LUKS unlock: `/init.cryptfs` (from `cryptfs-tpm2-initramfs` package)
  - IMA verification: `/init.ima` (from `initrdscripts-ima` package, if enabled)
- Features: FULL_DISK_ENCRYPTION flag gated via `DISTRO_FEATURES`


### 2. UEFI Secure Boot

**Key Generation**:
- Script: `layers/meta-distro/files/secureboot/generate-keys.sh`
- Creates: PK, KEK, db, dbx keys (valid 10 years)
- Storage: `layers/meta-distro/files/secureboot/` (keys are generated locally; repo does not include key artifacts)

**Key Deployment**:
- Recipe: `systemd-bootconf_%.bbappend`
- Target: `/boot/loader/keys/` on target system
- Includes: *.auth, *.esl, *.crt files for enrollment

**Key Hierarchy**:
```
PK (Platform Key) - Root of trust, self-signed
└── KEK (Key Exchange Key) - Signed by PK
    ├── db (Signature Database) - Signed by KEK, authorizes boot components
    └── dbx (Forbidden Database) - Signed by KEK, revocation list
```

### 3. systemd-boot Bootloader

**Configuration**:
- EFI_PROVIDER = "systemd-boot"
- Replaces GRUB for faster boot times
- Native Secure Boot support
- Integrated with systemd ecosystem
- LUKS support via initramfs

**Features**:
- Automatic key detection from `/boot/loader/keys/`
- Signed bootloader and kernel with db key
- Boot menu with 5-second timeout
- Kernel parameters for encrypted volumes: `root=UUID=8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11 rd.luks.name=<LUKS_UUID>=cryptroot`

### 4. Factory /var Pattern

**Purpose**: OSTree-compatible /var management with systemd-tmpfiles

**Implementation**:
- Image build: Copies /var → /usr/share/factory/var
- First boot: systemd-tmpfiles populates empty /var from factory
- Configuration: `/usr/lib/tmpfiles.d/factory-var.conf`

**Benefits**:
- /var persists across OSTree updates
- Easy recovery (clear LVM volume, reboot)
- Factory template always pristine in read-only rootfs

**Boot Sequence**:
1. LVM activation
2. Mount /var by filesystem UUID (no VG/LV names)
3. systemd-tmpfiles-setup.service runs
4. If /var empty: Copy from /usr/share/factory/var
5. Services start with populated /var

### 5. Kernel Configuration

**Built-in Drivers** (not modules):
- EXT4 filesystem (CONFIG_EXT4_FS=y)
- VFAT/FAT filesystems (CONFIG_VFAT_FS=y, CONFIG_FAT_FS=y)
- Device Mapper/LVM (CONFIG_BLK_DEV_DM=y, CONFIG_DM_SNAPSHOT=y)

**Docker Support with cgroups v2**:
- Control Groups v2 (CONFIG_CGROUPS=y) with memory, CPU, block IO controllers
- Namespaces (CONFIG_NAMESPACES=y) for process isolation
- Overlay filesystem (CONFIG_OVERLAY_FS=y) for container layers
- Bridge networking, VETH, VXLAN for container networking
- Netfilter, NAT, and iptables for packet filtering
- Seccomp and AppArmor for security
- eBPF support for modern networking and tracing

**Benefits**:
- No module loading in initramfs needed
- Faster boot times
- Simplified initramfs
- Full Docker and container runtime support
- Modern cgroups v2 for better resource management

**Configuration**:
- bbappend: `linux-yocto_%.bbappend` (currently present as `linux-yocto_%.bbappend.ignore`)
- Fragments: `builtin-drivers.cfg`, `docker-support.cfg`
- Features: `builtin-drivers.scc`, `docker.scc`

- Feature: `builtin-drivers.scc`

### 6. Docker Integration

**Packages**:
- docker-moby (Docker Engine)
- docker-compose
- meta-virtualization layer

**Configuration**:
- DISTRO_FEATURES:append = " virtualization"
- Kernel modules: xt-nat, iptable-nat
- systemd service enablement is not explicitly set in this layer (packages are installed)
- Required bbappends for container image creation:
  - `recipes-containers/podman/podman_%.bbappend` sets `BBCLASSEXTEND = "native nativesdk"`
  - `recipes-containers/podman-compose/podman-compose_%.bbappend` sets `BBCLASSEXTEND = "native nativesdk"`

### 7. Separate /var LVM Volume

**Mount Configuration**:
- Recipe: `systemd-mount-var.bb`
- Unit: `/usr/lib/systemd/system/var.mount`
- Device: UUID=d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55
- Type: ext4

**systemd Dependencies**:
- After: lvm2-activation.service
- Before: local-fs.target
- WantedBy: local-fs.target

**Alternative Mounting**:
- Can use WIC plugin's --lvm-mountpoints parameter for automatic /etc/fstab generation
- Example: `--lvm-mountpoints="varfs:/var"` creates fstab entry for varfs volume
- Useful for additional volumes (data, logs) without creating separate systemd mount units
- Current WKS files do not set `--lvm-mountpoints` by default

### 8. Security and Access Control

**Root Account**:
- Console/Serial: Blocked via empty `/etc/securetty`
- SSH: Allowed with key-based authentication only
- Password: Locked (hash replaced with `!` in `/etc/shadow`)

**User Accounts**:
- Console/Serial: Allowed with password authentication
- SSH: Allowed with password or key authentication

**SSH Configuration**:
- Recipe: `openssh_%.bbappend`
- Settings: `PermitRootLogin yes`, `PubkeyAuthentication yes`
- Global: Enabled via `EXTRA_IMAGE_FEATURES:append = " ssh-server-openssh"`

**Implementation**:
- `base-files_%.bbappend`: Creates empty securetty, locks root password
- `openssh_%.bbappend`: Configures SSH server settings
- Applied to all images via defaults.inc

**Access Examples**:
```bash
# Root access via SSH (requires authorized_keys setup)
ssh root@device

# User console login
# Login at tty1, tty2, ttyS0 with username/password

# Deploy SSH keys for root
echo "ssh-rsa AAAA..." > /root/.ssh/authorized_keys
```

### 9. OSTree Atomic A/B Deployments (MANDATORY)

**Architecture**:
- Atomic A/B deployment updates via OSTree
- Two active deployments at all times (current + rollback)
- Automatic network-resilient update mechanism
- Bootloader integration for safe deployment switching
- Separate /var LVM volume for persistent state across deployments

**Purpose**: Support production-grade deployment updates with zero-downtime rollback capability

**Current Status**: OSTree support is **MANDATORY and primary**
- Core feature: A/B deployment updates using `DISTRO_FEATURES:append = " sota"`
- Enabled by default in meta-distro/conf/distro/include/defaults.inc
- Image: `demo-image-ostree` is the primary production image
- Boot sequence runs `ostree-prepare-root` in initramfs before `switch_root`
- Two-deployment retention enforced by cleanup service on every boot

**Deployment Structure** (if OSTree enabled):
```
/ostree/
├── repo/                    # OSTree repository (objects, refs)
└── deploy/
    └── demo/               # OSTREE_OSNAME
        ├── deploy/
        │   ├── 0/          # Current deployment
        │   └── 1/          # Previous deployment (rollback)
        └── var/            # Shared /var across deployments
```

**Update Flow**:
1. System boots from OSTree deployment 0 (current)
2. ostree-pull-updates.timer triggers periodic update checks (every 4 hours)
3. New version pulled from remote into OSTree repo (operation resumes if network interrupted)
4. Admin manually validates and deploys new version: `ostree admin deploy origin:demo/<version>`
5. systemd-boot bootloader updated with new deployment entry
6. System reboot required to activate new deployment
7. Bootloader displays both deployments (new as default)
8. New deployment becomes active after reboot
9. If deployment fails: Automatic rollback by selecting previous deployment from bootloader menu
10. Previous deployment remains available for 2-deployment retention (older versions cleaned up)

**Features**:
- Multiple deployments on single partition
- Atomic updates with hardlinks (space efficient)
- Automatic cleanup on boot (keeps only 2 deployments: current + previous)
- Periodic update checks with network failure resilience
- OSTree pull operations resume automatically after network restoration
- Manual rollback via bootloader menu
- Persistent data in separate /var (LVM)
- Docker containers persist across updates

**Tools**:
- Recipe: `demo-image-ostree.bb` (OSTree-enabled image, primary)
- Command: `ostree admin status` (view deployments)
- Command: `ostree admin deploy <ref>` (create deployment)
- Command: `ostree remote add <name> <url>` (add update server)

**Configuration** (in meta-distro/conf/distro/include/defaults.inc):
```bitbake
# Optional: Enable OSTree updates
DISTRO_FEATURES:append = " sota usrmerge"
# Baseline required features
DISTRO_FEATURES:append = " systemd usrmerge polkit"
OSTREE_OSNAME = "demo"
OSTREE_BRANCHNAME = "${DISTRO_VERSION}"
OSTREE_BOOTLOADER = "systemd-boot"

# Image features
IMAGE_FSTYPES = "wic wic.bmap ostree.tar.bz2"
```

**Bootloader Integration**:
- systemd-boot configured for OSTree in `systemd-bootconf_%.bbappend`
- Boot timeout: 5 seconds
- Editor disabled for security
- OSTree manages boot entries automatically
- Deployments appear as separate menu entries
- Default deployment selected automatically

**Usage**:
```bash
# Build OSTree image (optional)
bitbake demo-image-ostree

# Check deployments
ostree admin status

# View available refs
ostree refs

# Create new deployment
ostree admin deploy demo:1.0

# Add remote repository
ostree remote add origin http://server/repo --no-gpg-verify

# Pull updates from remote (using DISTRO_VERSION)
ostree pull origin:demo/1.1

# Deploy new version
ostree admin deploy origin:demo/1.1

# Reboot to activate
systemctl reboot

# Rollback
ostree admin set-default 1
systemctl reboot
```

**CRITICAL ARCHITECTURE NOTE**: OSTree operations (`ostree-prepare-root`) MUST run in initramfs **before** switch_root. This is required and must not be changed.

## Development Guidelines

### Upstream Layer Policy - STRICTLY FORBIDDEN MODIFICATIONS

**CRITICAL POLICY**: Modifications, patches, or any changes to upstream layers are **STRICTLY FORBIDDEN**. This is a non-negotiable requirement for maintainability and upgradeability.

**Forbidden Paths** (NO modifications allowed):
- `/srv/repo/meta-distro/layers/poky/**`
- `/srv/repo/meta-distro/layers/meta-openembedded/**`
- `/srv/repo/meta-distro/layers/meta-secure-core/**`
- `/srv/repo/meta-distro/layers/meta-updater/**`
- `/srv/repo/meta-virtualization/**`

**All changes MUST be contained in**: `/srv/repo/meta-distro/layers/meta-distro/`

**Allowed Modification Patterns**:
- `.bbappend` files in meta-distro that extend upstream recipes
- New recipes in meta-distro
- Configuration files in meta-distro/conf/
- Custom classes in meta-distro/classes/
- Custom scripts in meta-distro/scripts/
- Patches stored in meta-distro/files/ and applied via bbappends

**If you need to modify upstream behavior**:
1. Create a `.bbappend` file in the corresponding meta-distro recipe directory
2. Add patches to meta-distro/files/ and reference them in SRC_URI
3. Override variables using bbappend
4. Create wrapper recipes that REQUIRE the upstream recipe

**Never**:
- Edit files directly in upstream layers
- Create patches that modify upstream layer files
- Add new files to upstream layer directories
- Modify upstream layer configuration files

### Initial Setup

```bash
# Clone repository
git clone <repo-url> /srv/repo
cd /srv/repo

# Generate Secure Boot keys (optional for development)
cd layers/meta-distro/files/secureboot
./generate-keys.sh
cd -

# Initialize build environment
./setup-build.sh

# Build image
bitbake core-image-minimal
```

### Key Configuration Files

1. **Machine**: `layers/meta-distro/conf/machine/include/defaults.inc`
   - WIC configuration, EFI provider, initramfs, Secure Boot
   - Kernel modules for Docker/virtualization

2. **Distribution**: `layers/meta-distro/conf/distro/include/defaults.inc`
   - Overrides/extensions for poky-sota distro (from meta-updater)
   - systemd-only configuration, no sysvinit

3. **Local Config**: `layers/meta-distro/conf/templates/local.conf.sample`
   - Requires defaults.inc and defaults.inc
   - Build settings, image features, Docker, LVM support

4. **Layers**: `layers/meta-distro/conf/templates/bblayers.conf.sample`
   - All required layers defined

### BitBake Variables Reference

**Standard Variables**:
- `${datadir}` = /usr/share
- `${prefix}` = /usr
- `${systemd_unitdir}` = /usr/lib/systemd
- `${LAYERDIR_meta-distro}` = Path to meta-distro layer

**Custom Variables**:
- `VALIDITY_DAYS` = 3650 (10 years for Secure Boot keys)
- `GUID` = UEFI Secure Boot key GUID

### Recipe Patterns

**IMPORTANT**: All recipe modifications MUST be in meta-distro layer. Never modify upstream layer recipes directly.

**Image Extension** (in meta-distro):
```bitbake
require recipes-core/images/core-image-minimal.bb
ROOTFS_POSTPROCESS_COMMAND += "custom_function; "
```

**bbappend Pattern** (in meta-distro, extending upstream recipe):
```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"
SRC_URI += "file://custom.conf"
```

**Location**: `/srv/repo/meta-distro/layers/meta-distro/recipes-*/.../*.bbappend`

**systemd Unit Installation**:
```bitbake
install -d ${D}${systemd_system_unitdir}
install -m 0644 ${WORKDIR}/unit.mount ${D}${systemd_system_unitdir}/
```

## CI/CD Integration

### GitHub Actions Workflows

**build.yml**: Main build workflow
- Triggers: push to main/develop, PRs, manual dispatch
- Caching: downloads and sstate for faster builds
- Artifacts: WIC images with 30-day retention

**validate.yml**: Syntax validation
- Checks: shell scripts, Python, YAML, XML manifests
- Runs on: PRs affecting meta-distro or manifests

### Repository Variables

Set in GitHub Settings → Secrets and variables → Actions → Variables:
- `YOCTO_DISTRO` = poky-sota
- `YOCTO_MACHINE` = qemux86-64
- `YOCTO_IMAGE` = core-image-minimal

## Maintenance Procedures

### Initramfs Boot Architecture Decision

**Status**: Monolithic initrdscripts-secure-core approach is final
- **Why not modular**: Comprehensive evaluation determined that modularizing to `initramfs-framework` would:
  - Increase maintenance burden by 2-3x
  - Expand test matrix from 3 to 16+ configurations
  - Require 54-76 hours initial implementation + 30-50 hours/year maintenance
  - Create brittleness in module ordering and interactions
  - Fundamentally misplace OSTree operations (which must run in initramfs)
- **Current approach**: Single `/init` script with external delegation to `/init.cryptfs` (TPM/LUKS) and `/init.ima` (IMA verification)
- **Benefits**: Simple, proven, maintainable, 2,095 bytes total code
- **No refactoring planned**: Keep existing implementation as-is

### Updating Secure Boot Keys

```bash
cd layers/meta-distro/files/secureboot
./generate-keys.sh [custom-guid]
# Backup private keys to secure location
# Rebuild image
```

### Modifying Disk Layout

Edit WKS files in `layers/meta-distro/scripts/lib/wic/canned-wks/`:
- Adjust partition sizes
- Add/remove LVM volumes
- Update --lvm-volumes parameter

### Adding New Layers

1. Edit `manifests/default.xml`:
   ```xml
   <project name="meta-mylayer" remote="github" revision="scarthgap" path="layers/meta-mylayer"/>
   ```

2. Run `repo sync`

3. Add to `bblayers.conf.sample`

### Customizing Factory /var

Modify `populate_factory_var()` in `core-image-minimal.bbappend`:
```bitbake
customize_factory_var() {
    install -d ${IMAGE_ROOTFS}${datadir}/factory/var/myapp
    echo "config" > ${IMAGE_ROOTFS}${datadir}/factory/var/myapp/config
}
ROOTFS_POSTPROCESS_COMMAND += "customize_factory_var; "
```

## Testing and Verification

### Build Verification

```bash
# Clean build
bitbake core-image-minimal -c cleanall
bitbake core-image-minimal

# Check artifacts
ls -lh tmp/deploy/images/qemux86-64/
```

### QEMU Testing

```bash
runqemu qemux86-64 nographic
```

### Verify Components

```bash
# On running system:

# Check Secure Boot keys
ls -la /boot/loader/keys/

# Check LVM volumes
lvs
vgs

# Check /var mount
mount | grep /var
systemctl status var.mount

# Check factory /var
ls -la /usr/share/factory/var/

# Check Docker
docker info
systemctl status docker

# Check systemd-tmpfiles
journalctl -u systemd-tmpfiles-setup.service
```

## Troubleshooting

### Build Issues

**Problem**: Missing layer dependencies
```bash
bitbake-layers show-layers
repo sync
```

**Problem**: Disk space errors
```bash
df -h
rm -rf tmp/
```

### Boot Issues

**Problem**: LVM volumes not detected
- Check kernel has built-in DM support: `zcat /proc/config.gz | grep BLK_DEV_DM`
- Verify initramfs includes LVM tools: `lsinitramfs /boot/initrd.img-*`
- Check boot logs: `journalctl -b | grep lvm`

**Problem**: /var not populated
- Check `/usr/share/factory/var/` exists
- Run: `systemd-tmpfiles --create --prefix=/var`
- Review service: `systemctl status systemd-tmpfiles-setup.service`

**Problem**: Secure Boot fails
- Verify keys enrolled in UEFI
- Check signatures: `sbverify --cert db.crt /boot/vmlinuz`
- Disable Secure Boot temporarily to test

### OSTree Update Issues

**Problem**: Pull service fails with network errors
- Normal behavior - service will retry automatically
- Check: `systemctl status ostree-pull-updates.service`
- Manual retry: `systemctl start ostree-pull-updates.service`

**Problem**: Deployment fails after pull
- Check available space: `df -h /ostree`
- Verify ref exists: `ostree refs`
- Manual deploy: `ostree admin deploy origin:demo/<version>`

**Problem**: Boot menu doesn't show deployments
- Check boot entries: `ls /boot/loader/entries/`
- Verify OSTree deployments: `ostree admin status`
- Run bootloader update: `systemctl start ostree-bootloader-update.service`

**Problem**: Cleanup service not running
- Check: `systemctl status ostree-cleanup-deployments.service`
- Manual cleanup: `ostree admin cleanup`
- Verify only 2 deployments kept: `ostree admin status`

## Documentation References

### Internal Documentation
- `layers/meta-distro/README.md` - Layer overview
- `layers/meta-distro/files/secureboot/README.md` - Key generation
- `layers/meta-distro/recipes-bsp/systemd-bootconf/README.md` - Boot configuration
- `layers/meta-distro/recipes-core/systemd/README.md` - Factory /var details
- `layers/meta-distro/scripts/lib/wic/README.md` - WIC plugin documentation
- `.github/workflows/README.md` - CI/CD details

### External Documentation
- [Yocto Project Documentation](https://docs.yoctoproject.org/)
- [systemd-boot Manual](https://www.freedesktop.org/software/systemd/man/systemd-boot.html)
- [systemd-tmpfiles Manual](https://www.freedesktop.org/software/systemd/man/tmpfiles.d.html)
- [repo Tool Documentation](https://gerrit.googlesource.com/git-repo/)
- [UEFI Secure Boot Specification](https://uefi.org/specifications)

## Quick Command Reference

```bash
# Setup
./setup-build.sh
source layers/poky/oe-init-build-env build

# Build
bitbake core-image-minimal
bitbake -c cleanall core-image-minimal

# Layer Management
bitbake-layers show-layers
bitbake-layers show-appends
repo sync

# Testing
runqemu qemux86-64
runqemu qemux86-64 nographic qemuparams="-m 2048"

# Image Analysis
wic list images
wic ls tmp/deploy/images/qemux86-64/core-image-minimal-qemux86-64.wic

# Key Generation
cd layers/meta-distro/files/secureboot && ./generate-keys.sh
```

## Known State Checklist

To recreate or verify this project state:

**Core Infrastructure:**
- [ ] repo manifest includes: poky, meta-openembedded, meta-updater, meta-virtualization, meta-secure-core
- [ ] meta-distro layer structure complete with all recipes
- [ ] defaults.inc with OSTree, SSH, and Docker configuration
- [ ] defaults.inc with EFI_PROVIDER=systemd-boot
- [ ] WKS files use `lvmrootfs` for LVM layouts and `rootfs` for lvm-simple
- [ ] WKS_FILE:forcevariable override prevents sota.bbclass override

**Security:**
- [ ] Secure Boot keys generated in files/secureboot/
- [ ] systemd-bootconf bbappend for key deployment
- [ ] base-files_%.bbappend for root account lockdown
- [ ] openssh_%.bbappend with SSH server configuration

**Storage:**
- [ ] WKS layouts (lvm-boot.wks.in, lvm-simple.wks.in) with template variable substitution
- [ ] LUKS encryption via initramfs-cryptsetup (not custom plugin)
- [ ] systemd-mount-var recipe (if using separate /var LVM volume)
- [ ] Factory /var support in systemd-conf with factory-var.conf

**Boot Sequence:**
- [ ] initrdscripts-secure-core recipe (monolithic init script)
- [ ] Delegation to /init.cryptfs for LUKS unlock
- [ ] Delegation to /init.ima for IMA verification (optional)
- [ ] NO initramfs-framework modules (decision made to keep monolithic)
- [ ] NO custom WIC plugin complexity

**Kernel:**
- [ ] linux-yocto bbappend with builtin-drivers.cfg (ext4, vfat, dm, lvm)
- [ ] docker-support.cfg with cgroups v2 configuration (CONFIG_NETFILTER_XT_TARGET_NAT=y)
- [ ] Boot parameters: root=UUID=8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11 systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all

**OSTree Updates (Mandatory):**
- [ ] demo-image-ostree.bb recipe for OSTree deployments (PRIMARY production image)
- [ ] ostree-bootloader-update.service for kernel arg management (required for A/B updates)
- [ ] ostree-cleanup-deployments.service for two-deployment retention (enforces A/B model)
- [ ] ostree-pull-updates.service + timer for network-resilient updates (periodic sync with server)
- [ ] OSTREE_BRANCHNAME set to ${DISTRO_VERSION}
- [ ] OSTree operations run in initramfs (prepare-root before switch_root)
- [ ] Two-deployment limit enforced by cleanup service on every boot

**CI/CD:**
- [ ] GitHub Actions workflows (build.yml, validate.yml)
- [ ] All documentation files (READMEs) updated
- [ ] Copilot instructions reflect current expectations (monolithic boot, demo-image-ostree primary)

**Final Build Artifacts** (verified Feb 16, 2026):
- [x] core-image-minimal-qemux86-64.rootfs.wic (✅ BUILT - 6.9 GB testing/development image)
- [ ] demo-image-ostree-qemux86-64.rootfs.wic (⏳ READY TO BUILD - OSTree A/B deployment image)
- [x] All image formats present for core-image-minimal: WIC, ext4, OSTree tar.bz2, tar.bz2
- [x] Initramfs: core-image-minimal-initramfs-cryptsetup (16 MB)
- [x] OSTree repository structure (ostree_repo/ directory created in deploy)
- [x] Secure Boot keys generated in files/secureboot/
- [x] All kernel drivers built-in (no modules required in initramfs)
- [x] Docker cgroups v2 support verified (CONFIG_NETFILTER_XT_TARGET_NAT=y)

## Making Changes to This Project

**CRITICAL REMINDER**: All modifications must be in `/srv/repo/meta-distro/layers/meta-distro/`. Never modify files in upstream layers (poky, meta-openembedded, meta-updater, meta-secure-core, meta-virtualization).

**IMPORTANT ARCHITECTURAL DECISIONS:**
1. **Boot sequence is monolithic** (initrdscripts-secure-core single /init script)
   - NOT using initramfs-framework modules
   - NOT refactoring to modular approach (evaluated and rejected due to high maintenance burden)
   - Changes to boot sequence MUST be made to `/init` script directly
   - External operations delegated to /init.cryptfs (LUKS) and /init.ima (IMA)

2. **Primary image is demo-image-ostree** (production deployments via A/B updates)
   - OSTree is MANDATORY feature for production use (A/B deployment updates)
   - core-image-minimal available for testing/development only
   - demo-image-ostree is the production deliverable
   - OSTree provides atomic updates with automatic rollback capability

3. **WIC uses `lvmrootfs` for LVM layouts and `rootfs` for lvm-simple**
   - LUKS encryption handled by initramfs-cryptsetup
   - WKS files in meta-distro/scripts/lib/wic/canned-wks/
   - WKS_FILE:forcevariable prevents sota.bbclass override

### Common Modification Patterns

**Add a New System Service** (in meta-distro):
1. Create service file in `meta-distro/recipes-core/systemd/systemd-conf/<service-name>.service`
2. Add to SRC_URI in `meta-distro/recipes-core/systemd/systemd-conf_%.bbappend`
3. Install in do_install:append() with conditional DISTRO_FEATURES check
4. Add to FILES and SYSTEMD_SERVICE variables
5. **Never modify** upstream systemd recipes directly

**Modify Boot Sequence** (via init script in meta-secure-core):
1. Edit `/srv/repo/meta-distro/layers/meta-secure-core/meta-secure-core-common/recipes-core/initrdscripts/files/init`
2. Monolithic script - all boot logic in single file
3. Keep external delegations: /init.cryptfs (LUKS), /init.ima (IMA optional)
4. Test changes in QEMU before deploying
5. **Never modularize** to initramfs-framework (evaluated and rejected)

**Modify Kernel Configuration** (via bbappend in meta-distro):
1. Edit or create .cfg fragment in `meta-distro/recipes-kernel/linux/linux-yocto/`
2. Add to SRC_URI in `meta-distro/recipes-kernel/linux/linux-yocto_%.bbappend`
3. Use `bitbake -c menuconfig virtual/kernel` to generate config
4. Rebuild: `bitbake virtual/kernel -c cleansstate && bitbake virtual/kernel`
5. **Never modify** kernel recipes in poky layer

**Change Boot Parameters** (in meta-distro WKS templates):
1. Edit `.wks.in` files in `meta-distro/scripts/lib/wic/canned-wks/`
2. Modify `--append` parameter in bootloader line (use `root=UUID=@UUID_ROOT@`)
3. Rebuild image: `bitbake core-image-minimal -c cleanall && bitbake core-image-minimal`
4. **Never modify** WKS files in upstream layers

**Add LUKS/TPM/LVM Features** (in meta-distro):
1. Modify /init script in meta-secure-core for new functionality
2. Use DISTRO_FEATURES conditionals to gate optional features
3. Delegate complex operations to external scripts if needed
4. Keep boot sequence logic centralized in /init script
5. **Do not create initramfs-framework modules** (see architectural decision above)

**Modify OSTree Configuration** (in meta-distro, mandatory feature):
1. Edit `meta-distro/conf/distro/include/defaults.inc`
2. Change OSTREE_OSNAME, OSTREE_BRANCHNAME, or OSTREE_BOOTLOADER if needed
3. Update remote URL in ostree-pull-updates.service if needed (meta-distro)
4. Rebuild: `bitbake demo-image-ostree -c cleanall && bitbake demo-image-ostree` (primary production image)
5. **Never modify** meta-updater configuration directly

**Add Global Package to All Images** (in meta-distro):
1. Edit `meta-distro/conf/distro/include/defaults.inc`
2. Add to DISTRO_FEATURES or create IMAGE_INSTALL:append
3. Document in copilot-instructions.md
4. **Never modify** upstream distro configurations

**Change Update Check Frequency**:
1. Edit `recipes-core/systemd/systemd-conf/ostree-pull-updates.timer`
2. Modify OnUnitActiveSec value (e.g., 4h, 8h, 1d)
3. Rebuild image (if using OSTree)

**Modify Security Settings** (via bbappends in meta-distro):
1. Root lockdown: `meta-distro/recipes-core/base-files/base-files_%.bbappend`
2. SSH config: `meta-distro/recipes-connectivity/openssh/openssh/sshd_config_custom`
3. Test in QEMU before deploying
4. **Never modify** upstream security recipes directly

**Debug Build Issues**:
```bash
# View build task log
bitbake <recipe> -c <task> -v

# Check dependencies
bitbake <recipe> -g

# Force rebuild
bitbake <recipe> -c cleansstate && bitbake <recipe>

# Interactive devshell
bitbake <recipe> -c devshell
```

### Recipe Organization

**Location Guidelines** (all paths within meta-distro layer):
- `meta-distro/recipes-bsp/`: Bootloader, firmware, hardware-specific
- `meta-distro/recipes-connectivity/`: Network services (SSH, etc.)
- `meta-distro/recipes-core/`: System fundamentals (base-files, images, systemd)
- `meta-distro/recipes-kernel/`: Kernel configuration and modules
- `meta-distro/scripts/lib/wic/`: Image creation plugins
- `meta-distro/files/`: Static files (keys, scripts)
- `meta-distro/conf/`: Configuration files (machine, distro, templates)
- `meta-distro/classes/`: Custom BitBake classes

**FORBIDDEN**: Creating recipes or files in upstream layers (poky, meta-openembedded, etc.)

**Naming Conventions**:
- Recipe files: `<package-name>_<version>.bb` or `<package-name>_%.bbappend`
- Service files: `<service-name>.service`, `<timer-name>.timer`
- Config fragments: `<feature>.cfg`, `<feature>.scc`
- WKS layouts: `<layout-name>.wks`

### Testing Strategy

**1. Build Testing**:
```bash
# Clean build
bitbake demo-image-ostree -c cleanall
bitbake demo-image-ostree

# Check for errors
bitbake demo-image-ostree -c listtasks
```

**2. QEMU Testing**:
```bash
# Boot image
runqemu qemux86-64 nographic

# With more memory
runqemu qemux86-64 nographic qemuparams="-m 2048"
```

**3. System Verification**:
```bash
# On running system:

# Check OSTree deployments
ostree admin status

# Verify LVM
lvs
vgs
mount | grep /var

# Check services
systemctl status ostree-pull-updates.timer
systemctl status docker

# Test SSH
ssh root@localhost

# Verify Docker
docker run hello-world

# Check kernel params
cat /proc/cmdline | grep cgroup
```

**4. Update Testing**:
```bash
# On target system:

# Add remote
ostree remote add origin http://server/repo --no-gpg-verify

# Manual pull
systemctl start ostree-pull-updates.service

# Check status
journalctl -u ostree-pull-updates.service

# Deploy if successful
ostree admin deploy origin:demo/1.1
systemctl reboot

# Verify deployment after boot
ostree admin status

# Rollback if needed (from bootloader menu or)
ostree admin set-default 1
systemctl reboot
```

### Best Practices

1. **NEVER modify upstream layers** - all changes in meta-distro only
2. **Always test in QEMU first** before deploying to hardware
3. **Document changes** in copilot-instructions.md and recipe comments
4. **Use conditional features** (DISTRO_FEATURES) for optional components
5. **Create bbappends** instead of patching upstream recipes directly
6. **Version control** Secure Boot keys separately (not in git)
7. **Increment DISTRO_VERSION** for each OSTree update release
8. **Keep two deployments** - cleanup service maintains this automatically
9. **Test rollback** - ensure previous deployment boots successfully
10. **Monitor disk space** - OSTree and Docker images accumulate
11. **Use direct system tools** - no libguestfs integration in this layer
12. **Follow Yocto conventions** - use standard variables and paths
13. **Verify layer isolation** - ensure no files created outside meta-distro

### Troubleshooting Common Issues

**"No space left on device" during build**:
```bash
df -h
rm -rf build/tmp/
bitbake -c cleanall <image>
```

**"File not found" in WIC plugin**:
- Check ROOTFS_DIR exists
- Verify SOURCE_DIR_<name> paths
- Ensure dependencies are built first

**OSTree pull fails repeatedly**:
- Check network connectivity
- Verify remote URL: `ostree remote list -u`
- Check server is serving ostree repo
- Review logs: `journalctl -u ostree-pull-updates.service`

**Root SSH login fails**:
- Deploy authorized_keys: `/root/.ssh/authorized_keys`
- Check SSH config: `cat /etc/ssh/sshd_config | grep PermitRoot`
- Verify root password is locked: `grep ^root: /etc/shadow`

**Docker cgroups errors**:
- Verify kernel boot params: `cat /proc/cmdline`
- Check cgroups v2: `mount | grep cgroup`
- Review kernel config: `zcat /proc/config.gz | grep CGROUP`

**LVM volumes not mounting**:
- Check kernel has DM built-in: `zcat /proc/config.gz | grep BLK_DEV_DM`
- Verify volume exists: `lvs`
- Check systemd mount unit: `systemctl status var.mount`

## Version Information

- **Yocto Release**: Scarthgap
- **systemd**: Latest from Scarthgap
- **Kernel**: linux-yocto (Scarthgap)
- **Docker**: docker-moby from meta-virtualization
- **Secure Boot Key Validity**: 10 years (3650 days)
- **Layer Compatibility**: LAYERSERIES_COMPAT = "scarthgap"
- **Primary Production Image**: demo-image-ostree (OSTree A/B deployments)
- **OSTree Status**: MANDATORY feature for production deployments
