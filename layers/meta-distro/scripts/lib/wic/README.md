# WIC Layouts and Templates

This directory contains WIC layout templates (`.wks.in`) and custom WIC plugins for the DISTRO Project.

## Custom WIC Plugins

### 1. lvmrootfs.py - LVM with LUKS Encryption and TPM2

The `lvmrootfs` plugin creates LUKS-encrypted LVM physical volumes with:
- LUKS encryption around LVM physical volume (MANDATORY)
- TPM2-sealed LUKS keys (primary unlock method)
- Hierarchical unlock: TPM2 NV+PCR7 → /dev/null OR passphrase
- Rootfs logical volume (MANDATORY)
- Optional additional logical volumes


- Creates EFI System Partition
- Copies kernel and initramfs to boot partition
- Note: Currently WKS files use `--source empty` for ESP

### Key Features

- **Direct system calls**: Uses Python subprocess to call system binaries directly
- **Simple architecture**: Direct calls to losetup, LVM, cryptsetup, mount utilities
- Creates LVM physical volume within a partition
- Automatically creates and populates rootfs logical volume
- Supports additional logical volumes with customizable names and sizes
- Formats volumes with ext4 filesystem
- Automatic /etc/fstab generation for mount points when `--lvm-mountpoints` is set
- Integrates with Yocto's WIC image creation system

### Technology

This plugin uses **native Python subprocess** to call system binaries directly:
- Direct calls to losetup for loop device management (requires disk group membership)
- Direct calls to LVM tools via `lvm` subcommands (lvm pvcreate, lvm vgcreate, lvm lvcreate, lvm vgchange)
- Direct calls to cryptsetup for LUKS encryption
- Direct calls to mount/umount for filesystem operations
- Tool paths are resolved via hardcoded TOOLS dictionary with PATH fallback
- Simpler and more portable than virtualization-based approaches
- **Works for non-root users when user is member of disk group**

### WKS Template Processing

All canned WKS files use the `.wks.in` template format with direct BitBake variable expansion (not @VARIABLE@ substitution).

**Template Variables** (defined in `conf/distro/include/defaults.inc`):
- `${PARTTYPE_ESP}` → GPT partition type GUID for ESP
- `${PARTTYPE_XBOOTLDR}` → GPT partition type GUID for XBOOTLDR
- `${PARTTYPE_ROOT}` → GPT partition type GUID for root (x86-64, LUKS)
- `${FSUUID_ESP}` → Filesystem UUID for ESP
- `${FSUUID_XBOOTLDR}` → Filesystem UUID for XBOOTLDR
- `${FSUUID_ROOT}` → Filesystem UUID for root LV
- `${FSUUID_VAR}` → Filesystem UUID for /var LV

**Processing**: WIC expands variables at image creation time using BitBake environment

### Discoverable Partitions Specification

The WKS files implement the **UAPI Group Discoverable Partitions Specification Type #2**:
- Partition type GUIDs allow systemd to discover partitions
- Filesystems are mounted by UUID (no /dev/sdX, VG, or LV names)
- Enables secure boot and attestation workflows

**Partition Type GUIDs (Required):**
- ESP: `c12a7328-f81f-11d2-ba4b-00a0c93ec93b` (SD_GPT_ESP)
- XBOOTLDR: `bc13c2ff-59e6-4262-a352-b275fd6f7172` (SD_GPT_XBOOTLDR)
- Root x86-64: `4f68bce3-e8cd-4db1-96e7-fbcaf984b709` (SD_GPT_ROOT_X86_64, LUKS encrypted)

**Note**: Encrypted root partitions use architecture-specific root partition types (SD_GPT_ROOT_X86_64) rather than the generic LVM type, even when LVM is used inside the LUKS container.

### WKS File Parameters

The `lvmrootfs` plugin supports the following parameters in WKS files:

- `--lvm-vg-name=NAME`: Volume group name (default: "vg0")
- `--lvm-rootfs-name=NAME`: Rootfs logical volume name (default: "rootlv")
    - **Note**: VG/LV names are used only during image creation; boot and discovery use filesystem UUIDs
- `--lvm-volumes="name:size,name:size"`: Additional volumes to create
  - Format: comma-separated list of "name:size" pairs
  - Size can be specified in K, M, or G (e.g., "2G", "512M", "1024K")
  - Example: `--lvm-volumes="datafs:2G,logfs:1G,cache:512M"`
- `--lvm-mountpoints="name:path,name:path"`: Optional mount points for volumes
  - Format: comma-separated list of "lvname:mountpoint" pairs
  - Automatically updates /etc/fstab in the rootfs
  - Example: `--lvm-mountpoints="datafs:/mnt/data,logfs:/var/log"`
  - Note: Mount points must be absolute paths starting with /
    - Note: Current canned WKS files do not set `--lvm-mountpoints` by default
- `--luks-passphrase=PASSPHRASE`: Enable LUKS encryption with passphrase
  - Set to "NULL" to use `/dev/null` as key file (useful for testing)
  - Example: `--luks-passphrase="mysecret"` or `--luks-passphrase="NULL"`
  - Boot behavior: Initramfs first tries `/dev/null` key, then prompts for passphrase if that fails
- `--luks-name=NAME`: LUKS device mapper name (default: "cryptroot")
    - Example: `--luks-name="cryptroot"`

### Filesystem UUIDs (Preassigned)

All filesystem UUIDs are **static and preassigned**. The WKS templates set them explicitly and boot-time discovery uses UUIDs (never device paths or VG/LV names).

| Filesystem | UUID | Purpose |
|------------|------|---------|
| ESP | `3a4f2c1e-9b8d-4c3f-8e1a-7d2b9f4c6a11` | EFI System Partition (/boot/efi) |
| XBOOTLDR | `5d7e1b2c-3f4a-4c8d-9e22-1a6b7c8d9e33` | /boot |
| Root LV | `8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11` | / |
| Var LV | `d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55` | /var |

These values are defined in `layers/meta-distro/conf/distro/include/defaults.inc` and enforced in WKS templates.

### Example WKS Files

#### lvm-boot-encrypted.wks.in (LUKS Encrypted)
```
# EFI System Partition for systemd-boot
# Partition Type: @PARTTYPE_ESP@ (SD_GPT_ESP)
part /boot/efi --source bootimg-efi --sourceparams="loader=systemd-boot" \
    --ondisk sda --label efi --active --align 1024 --size 512M --fstype=vfat \
    --uuid=@UUID_ESP@ --part-type=@PARTTYPE_ESP@

# Boot partition for kernels and initramfs (XBOOTLDR)
# Partition Type: @PARTTYPE_XBOOTLDR@ (SD_GPT_XBOOTLDR)
part /boot --ondisk sda --label boot --align 1024 --size 1024M --fstype=ext4 \
    --uuid=@UUID_XBOOTLDR@ --part-type=@PARTTYPE_XBOOTLDR@

# LUKS-encrypted root partition containing LVM
# Partition Type: @PARTTYPE_ROOT@ (SD_GPT_ROOT_X86_64)
# var volume is separate from rootfs as ostree does not monitor /var for updates
# varfs created last using all remaining space
part / --source lvmrootfs --ondisk sda --fstype=ext4 --label rootfs \
    --align 1024 --size 4096M --extra-space 2048M \
    --lvm-vg-name=vg0 --lvm-rootfs-name=rootlv \
    --lvm-volumes="datafs:2G,logfs:1G,varfs:100%FREE" \
    --luks-passphrase="changeme" --luks-name="cryptroot" \
    --part-type=@PARTTYPE_ROOT@

bootloader --ptable gpt --timeout=5 \
    --append="root=UUID=@UUID_ROOT@ rootflags=ro rootfstype=ext4 rd.luks.name=<LUKS_UUID>=cryptroot systemd.unified_cgroup_hierarchy=1 cgroup_no_v1=all"
```

**Note**: Encrypted root partitions use the architecture-specific root partition type (SD_GPT_ROOT_X86_64 for x86-64) rather than the generic LVM type. The LUKS container holds the LVM physical volume.

## Usage

### Using in Machine Configuration

Set the WKS file in your machine configuration:

```bitbake
WKS_FILE = "lvm-boot-encrypted.wks.in"
```

### Dependencies

The plugin requires standard Linux tools:
- `lvm2`: LVM tools via `lvm` subcommands (lvm pvcreate, lvm vgcreate, lvm lvcreate, lvm vgchange, lvm lvdisplay)
- `cryptsetup`: LUKS encryption (cryptsetup)
- `e2fsprogs`: ext4 filesystem tools (mkfs.ext4)
- `dosfstools`: VFAT filesystem tools (for boot partition)
- `util-linux`: mount/umount utilities

These are typically pre-installed on Linux build systems. No Yocto native recipe dependencies needed.

### Using in local.conf

Override the WKS file in your build configuration:

```bitbake
WKS_FILE = "lvm-simple.wks.in"
```

### Runtime LVM Management

The image includes `lvm2` tools for managing volumes at runtime:

```bash
# List volume groups
vgs

# List logical volumes
lvs

# Extend a logical volume (e.g., /var)
# Use lvs to identify the LV, then extend it with lvextend.
# Resize the filesystem by UUID (no device paths in boot or config):
resize2fs /dev/disk/by-uuid/d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55
```

### Separate /var Volume for OSTree

The `/var` logical volume is created separately from the rootfs to support OSTree-based atomic updates:

- **OSTree compatibility**: OSTree in meta-updater does not monitor `/var` for updates, making it suitable for persistent data
- **Automatic mounting**: A systemd mount unit (`systemd-mount-var`) mounts `/var` by filesystem UUID
- **Persistent data**: Application data, logs, and package caches in `/var` persist across OSTree updates
- **Independent management**: The `/var` volume can be resized or managed independently from the rootfs

To include the systemd mount unit in your image:
```bitbake
CORE_IMAGE_EXTRA_INSTALL += "systemd-mount-var"
```

## Requirements

### Build-Time Dependencies

The plugin requires the following system tools:
- `lvm2`: LVM tools via `lvm` subcommands (lvm pvcreate, lvm vgcreate, lvm lvcreate, lvm vgchange, lvm lvdisplay)
- `cryptsetup`: LUKS encryption support
- `e2fsprogs`: ext4 filesystem utilities
- `dosfstools`: VFAT support for boot partition
- `util-linux`: Standard mount/umount utilities

Install on Ubuntu/Debian:
```bash
sudo apt-get install lvm2 cryptsetup e2fsprogs dosfstools
```

Install on RHEL/Fedora:
```bash
sudo dnf install lvm2 cryptsetup e2fsprogs dosfstools util-linux
```

### Build Host Configuration

**Good News**: This plugin uses **native subprocess calls**, which means:
- ✅ **No HOSTTOOLS configuration needed**
- ✅ **Works with standard system tools**
- ✅ **No virtualization required**
- ✅ **Works in containers and restricted environments**
- ✅ **Faster than virtualization-based approaches**

The plugin calls system binaries directly via Python subprocess.run(), with tool paths resolved via a TOOLS dictionary with PATH fallback.

#### Build User Permissions

To use LVM, cryptsetup, and mount operations, your build user needs appropriate permissions. Choose one approach:

**Option 1: Add user to disk group (simpler)**
```bash
sudo usermod -a -G disk $USER
# Log out and back in for group to take effect
```

**Option 2: Configure sudo without password (more secure)**
```bash
# Add to /etc/sudoers (via visudo):
%<buildgroup> ALL=(ALL) NOPASSWD: /sbin/losetup, /sbin/lvm, /bin/mount, /bin/umount, /sbin/cryptsetup
```

**Option 3: Use with sudo prompt (least automatic)**
```bash
# Plugin will work, but prompt for password on operations requiring elevation
```

## Technical Details

### How It Works

The plugin uses native Python subprocess calls to execute system binaries:

1. **Create sparse disk image**: Create file with dd
2. **Setup loop device**: Attach sparse file via losetup
3. **Encrypt (optional)**: Format with LUKS via cryptsetup
4. **LVM operations**: Create physical volume, volume group, and logical volumes via LVM tools
5. **Filesystem creation**: Format volumes with mkfs.ext4
6. **Content population**: Copy rootfs content via tar
7. **Fstab modification**: Update /etc/fstab in mounted rootfs
8. **Cleanup**: Unmount, deactivate LVM, detach loop device

Tool paths are resolved from the TOOLS dictionary with automatic PATH fallback.

### Performance Considerations

- **Direct system calls**: Near-native performance
- **No virtualization overhead**: Faster than libguestfs approach
- **Disk I/O**: Standard host filesystem performance
- **Tool availability**: Fast when tools are in standard system paths

### Advantages Over Virtualization

| Feature | Native Subprocess | Virtualization (libguestfs) |
|---------|-------------------|------------------------------|
| Performance | ⚡ Excellent | ⚠️ Slower (VM overhead) |
| Simplicity | ✅ Simple | ⚠️ Complex |
| Dependencies | ✅ Minimal | ❌ Heavy (QEMU, libguestfs) |
| User permissions | ⚠️ Needs careful setup | ✅ None |
| Container-friendly | ✅ Yes | ⚠️ Limited (KVM needed) |
| Portability | ✅ High | ⚠️ Medium |

## Troubleshooting

### Error: "Tool 'losetup' or 'lvm' not found"

**Cause**: LVM tools or util-linux not installed or not in PATH

**Solution**:
- Install lvm2: `sudo apt-get install lvm2` (Ubuntu/Debian)
- Install cryptsetup: `sudo apt-get install cryptsetup`
- Install util-linux: `sudo apt-get install util-linux`
- Verify tools are in PATH: `which losetup lvm mkfs.ext4`

### Error: "Command failed with code 1"

**Cause**: Insufficient permissions for disk operations

**Solution**: Ensure your build user has appropriate permissions
- Add to disk group: `sudo usermod -a -G disk $USER` (then log out/in)
- Or configure sudoers for passwordless execution of disk tools

### Error: "Permission denied" on loop device setup

**Cause**: User not in disk group or /dev/loop* permissions restricted

**Solution**:
- Add user to disk group: `sudo usermod -a -G disk $USER`
- Check loop device permissions: `ls -l /dev/loop*`
- If needed, adjust permissions: `sudo chmod 666 /dev/loop*`

### Error: "Device mapper not found"

**Cause**: Device mapper kernel module not loaded

**Solution**:
- Load module: `sudo modprobe dm_mod`
- For persistent loading, add to `/etc/modules`:
  ```
  dm_mod
  dm_crypt
  ```

### Error: "lvm lvcreate failed"

**Cause**: LVM tools not working correctly or insufficient space

**Solution**:
- Verify LVM is installed: `sudo lvm version`
- Check sparse file was created: `ls -lh tmp/lvm-*/lvm-pv.img`
- Verify logical volume size calculation: Check WKS file parameters
- Clear any existing LVM state: `sudo lvm vgremove -f <vgname>` (if leftover from failed build)

### Error: "mkfs.ext4 not found"

**Cause**: e2fsprogs not installed

**Solution**: Install e2fsprogs:
```bash
sudo apt-get install e2fsprogs  # Ubuntu/Debian
sudo dnf install e2fsprogs      # RHEL/Fedora
```

## Boot Configuration

The kernel boot parameters must specify the root filesystem by UUID:

```
root=UUID=8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11
```

The initramfs must:
- Locate the LUKS partition by GPT PARTTYPE (SD_GPT_ROOT_X86_64)
- Unlock LUKS, activate LVM, and mount the root LV by UUID
- Run `ostree-prepare-root` before `switch_root`
- Mount `/var` by UUID before OSTree finalization
