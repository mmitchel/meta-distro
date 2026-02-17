# Kernel Configuration

This directory contains kernel configuration fragments for the meta-distro layer.

## Overview

Custom kernel configurations are applied through bbappend files and configuration fragments to enable specific features required for the distribution.

## Configuration Fragments

### builtin-drivers.cfg

Forces critical filesystem and storage drivers to be compiled into the kernel instead of as loadable modules:

- **EXT4 filesystem**: Primary filesystem for root and data volumes
- **FAT/VFAT filesystems**: Required for EFI boot partition
- **LVM (Device Mapper)**: Logical Volume Management for flexible storage

This ensures these drivers are available early in the boot process without requiring initramfs module loading.

### docker-support.cfg

Enables comprehensive Docker and container runtime support including:

- **Control Groups (cgroups) v2**: Modern resource management and isolation
  - Memory controller (memcg) with swap and kmem support
  - CPU controller with quota and bandwidth limiting
  - Block IO controller with throttling
  - PID controller for process limiting
  - Device controller for device access control
  - BPF-based cgroup programs

- **Namespaces**: Process isolation
  - UTS namespace (hostname/domain isolation)
  - IPC namespace (System V IPC isolation)
  - PID namespace (process ID isolation)
  - Network namespace (network stack isolation)
  - User namespace (UID/GID isolation)

- **Networking**: Container networking features
  - Bridge networking with VLAN filtering
  - VETH pairs for container connectivity
  - VXLAN for overlay networks
  - MACVLAN and IPVLAN for direct network access
  - Netfilter and iptables for packet filtering
  - NAT and masquerading for container egress
  - IP Virtual Server (IPVS) for load balancing

- **Storage**: Container filesystem support
  - Overlay filesystem for efficient layering
  - Device Mapper thin provisioning
  - Tmpfs with POSIX ACLs and extended attributes

- **Security**: Container isolation and security
  - Seccomp filtering for syscall restrictions
  - AppArmor for mandatory access control
  - Audit framework for security logging
  - Network security features

- **Advanced Features**:
  - eBPF support for modern networking and tracing
  - Quota support for resource limiting
  - Hugetlbfs for performance optimization

## Feature Files

### features/builtin-drivers/builtin-drivers.scc

Kernel feature definition for built-in drivers:
```scc
define KFEATURE_DESCRIPTION "Built-in drivers for ext4, vfat, and LVM"
define KFEATURE_COMPATIBILITY all

kconf non-hardware builtin-drivers.cfg
```

### features/docker/docker.scc

Kernel feature definition for Docker support:
```scc
define KFEATURE_DESCRIPTION "Docker and container runtime support with cgroups v2"
define KFEATURE_COMPATIBILITY all

kconf non-hardware docker-support.cfg
```

## Usage

The kernel configuration is intended to be applied through the `linux-yocto_%.bbappend` file. In this layer, the bbappend is currently stored as `linux-yocto_%.bbappend.ignore` and is not active by default.

```bitbake
FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://builtin-drivers.cfg"
SRC_URI += "file://docker-support.cfg"

KERNEL_FEATURES:append = " features/builtin-drivers/builtin-drivers.scc"
KERNEL_FEATURES:append = " features/docker/docker.scc"
```

## Verification

To verify kernel configuration after building:

```bash
# Check built image config
zcat /proc/config.gz | grep -E "CONFIG_(EXT4|VFAT|BLK_DEV_DM|CGROUPS|OVERLAY_FS)="

# Or check build artifacts
bitbake -c kernel_configcheck linux-yocto
```

Expected output:
```
CONFIG_EXT4_FS=y
CONFIG_VFAT_FS=y
CONFIG_BLK_DEV_DM=y
CONFIG_CGROUPS=y
CONFIG_OVERLAY_FS=y
```

## Testing Docker Support

After booting the system, verify Docker kernel requirements:

```bash
# Check Docker compatibility
docker info

# Should show:
# - Cgroup Version: 2
# - Storage Driver: overlay2
# - Kernel Version: (should match your kernel)
```

## Customization

To add additional kernel features:

1. Create a new `.cfg` file in `linux-yocto/`
2. Create a corresponding `.scc` file in `linux-yocto/features/<feature-name>/`
3. Add to `SRC_URI` and `KERNEL_FEATURES` in the bbappend

## References

- [Yocto Kernel Development Manual](https://docs.yoctoproject.org/kernel-dev/)
- [Docker Kernel Requirements](https://docs.docker.com/engine/install/linux-postinstall/#kernel-configuration)
- [Linux Control Groups v2](https://www.kernel.org/doc/html/latest/admin-guide/cgroup-v2.html)
- [Kernel Configuration Options](https://www.kernel.org/doc/html/latest/kbuild/kconfig.html)
