This README file contains information on the contents of the meta-distro layer.

# meta-distro - Demo Distribution Layer

This layer provides the custom distribution configuration for the demo project.

## Layer Dependencies

This layer depends on:
- openembedded-core (poky/meta)

## Layer Structure

```
meta-distro/
├── conf/
│   ├── layer.conf                     # Layer configuration
│   ├── machine/
│   │   └── include/
│   │       └── defaults.inc         # Machine defaults (WIC, EFI, initramfs)
│   ├── distro/

│   │   └── include/
│   │       └── defaults.inc          # Distribution defaults
│   └── templates/
│       ├── local.conf.sample         # Local configuration template
│       ├── bblayers.conf.sample      # Layers configuration template
│       └── conf-notes.txt            # Build notes
├── classes/
│   ├── podman-compose.bbclass        # OCI container builder (no root required)
│   └── README.md                     # Class documentation
├── recipes-bsp/
│   ├── secureboot-keys/              # UEFI Secure Boot keys (legacy)
│   │   ├── secureboot-keys.bb        # Recipe to generate keys
│   │   ├── secureboot-keys/
│   │   │   └── generate-secureboot-keys.sh
│   │   └── README.md                 # Secure Boot documentation
│   └── systemd-bootconf/             # systemd-boot configuration
│       ├── systemd-bootconf_%.bbappend  # Copies keys to boot partition
│       └── README.md                 # systemd-boot integration docs
├── recipes-core/
│   ├── images/
│   │   └── core-image-minimal.bbappend  # Factory /var support
│   └── systemd/
│       ├── systemd-mount-var.bb      # Systemd mount for /var
│       ├── systemd-mount-var/
│       │   └── var.mount             # Mount unit file
│       ├── systemd-conf_%.bbappend   # Factory /var tmpfiles config
│       ├── systemd-conf/
│       │   └── factory-var.conf      # systemd-tmpfiles configuration
│       └── README.md                 # Factory /var documentation
├── recipes-kernel/
│   └── linux/
│       ├── linux-yocto_%.bbappend.ignore  # Kernel configuration (disabled by default)
│       └── linux-yocto/
│           ├── builtin-drivers.cfg   # Built-in drivers config
│           └── features/builtin-drivers/
│               └── builtin-drivers.scc
├── files/
│   └── secureboot/                   # Secure Boot key generation scripts
│       ├── generate-keys.sh          # Script to generate keys
│       ├── README.md                 # Key generation guide
│       └── *.auth, *.esl, *.crt      # Generated keys (after running script)
├── scripts/
│   └── lib/
│       └── wic/
│           ├── plugins/source/
│           │   └── lvmrootfs.py      # Custom WIC plugin for LVM layouts
│           ├── canned-wks/
│           │   ├── lvm-boot.wks.in      # WKS template with systemd-boot + LVM
│           │   ├── lvm-boot-encrypted.wks.in # WKS template with LUKS + LVM
│           │   └── lvm-simple.wks.in    # WKS template (minimal)
│           └── README.md             # WIC plugin documentation
└── README.md                          # This file
```

## Configuration Files

### Bootloader - systemd-boot

The layer uses **systemd-boot** as the EFI bootloader instead of GRUB:
- Faster boot times
- Native UEFI Secure Boot support
- Simpler configuration
- Integrated with systemd

Configuration in `defaults.inc`:
```bitbake
EFI_PROVIDER = "systemd-boot"
MACHINE_FEATURES:append = " secureboot"
```

### Secure Boot Keys

UEFI Secure Boot keys are generated locally and deployed when present:

**Key Generation:**
```bash
cd layers/meta-distro/files/secureboot
./generate-keys.sh
```

**Key Storage Locations:**
- Source: `layers/meta-distro/files/secureboot/` - Generated keys stored locally (not committed)
- Target: `/boot/loader/keys/` - Keys deployed by systemd-bootconf bbappend
- Includes: PK, KEK, db, dbx (certificates, signature lists, authenticated variables)

**Documentation:**
- [files/secureboot/README.md](files/secureboot/README.md) - Key generation guide
- [recipes-bsp/systemd-bootconf/README.md](recipes-bsp/systemd-bootconf/README.md) - Integration details
- [recipes-bsp/secureboot-keys/README.md](recipes-bsp/secureboot-keys/README.md) - General Secure Boot info

### Kernel Configuration

Built-in kernel drivers for filesystems and LVM (bbappend is currently disabled by default):
- EXT4, VFAT, FAT filesystems compiled into kernel
- Device Mapper (LVM) built-in, not as modules
- Eliminates need for initramfs module loading

### Factory /var Pattern

The layer implements the systemd factory pattern for `/var` population:

**How it works:**
1. Image build creates `/usr/share/factory/var` with initial `/var` contents
2. Separate LVM volume for `/var` starts empty on first boot
3. systemd-tmpfiles automatically populates `/var` from factory template
4. `/var` persists across OSTree updates while factory template stays pristine

**Benefits:**
- Clean separation of system (rootfs) and data (/var)
- OSTree compatibility - `/var` not monitored for updates
- Easy recovery - can restore `/var` from factory template
- Independent management - resize or backup `/var` separately

**Documentation:**
- [recipes-core/systemd/README.md](recipes-core/systemd/README.md) - Complete factory /var guide

### scripts/lib/wic/plugins/source/lvmrootfs.py
Custom WIC plugin for LVM-based images. LVM layouts (`lvm-boot*`) use `lvmrootfs`; the `lvm-simple.wks.in` layout uses the standard Poky `rootfs` source with `.wks.in` templates and GUID/UUID substitution.

### scripts/lib/wic/canned-wks/*.wks.in
Pre-defined WKS templates for common disk layouts:
- `lvm-boot.wks.in` - Full layout with ESP, XBOOTLDR, and LUKS-encrypted LVM
- `lvm-boot-encrypted.wks.in` - Full layout with LUKS-encrypted LVM
- `lvm-simple.wks.in` - Minimal layout (ESP + root)

All templates use GUID/UUID substitution and boot via `root=UUID=...` (no device paths or VG/LV names).

### machine/include/defaults.inc

Machine defaults that extend the base qemux86-64 machine from poky:
- WIC configuration for LVM-based disk layout
- EFI bootloader configuration (systemd-boot)
- Secure Boot support
- Bundled initramfs configuration
- Docker-specific kernel modules
- Image format settings (ext4, wic)

### defaults.inc

Overrides and extensions for the poky-sota distribution (from meta-updater):
- Distribution name and version
- Init system configuration (systemd-only, no sysvinit)
- Package format (RPM)
- SDK configuration
- Feature flags and virtual runtime providers

Note: This project uses the `poky-sota` distribution from meta-updater, and `defaults.inc` provides additional configuration and overrides.

### local.conf.sample
Template for build configuration including:
- Machine selection
- Build parallelism
- Download and cache directories
- Disk space monitoring

### bblayers.conf.sample
Template for layer configuration

## Usage

This layer is automatically configured by the `setup-build.sh` script. The configuration templates are copied to the build directory during initialization.

## Customization

To customize the distribution:
1. Edit `conf/distro/include/defaults.inc` for distribution-level overrides (project uses poky-sota from meta-updater)
2. Edit `conf/templates/local.conf.sample` for build-time defaults
3. Add custom recipes or configuration files as needed

## Maintainer

Demo Project <demo@example.com>
