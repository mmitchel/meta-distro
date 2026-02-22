# Factory /var Support for systemd-tmpfiles

This directory contains configuration for populating `/var` from a factory template using systemd-tmpfiles.

## Overview

When using a separate LVM volume for `/var`, the partition starts empty on first boot. The factory `/var` pattern allows systemd-tmpfiles to automatically populate it with necessary directory structure and initial contents.

## Implementation

### 1. Image Configuration

The `core-image-minimal.bbappend` extends the base image to:
- Copy contents of `/var` to `/usr/share/factory/var` during image creation
- Preserve the factory template in the rootfs (read-only)
- Make it available for systemd-tmpfiles to restore

### 2. systemd-tmpfiles Configuration

The `factory-var.conf` file tells systemd-tmpfiles to:
- Check if `/var` is empty or missing
- Copy contents from `/usr/share/factory/var` to `/var` if needed
- Preserve permissions and ownership

## How It Works

### Boot Sequence

1. **Kernel boots** with bundled initramfs
2. **Root filesystem mounts** (by filesystem UUID)
3. **systemd starts** early in boot process
4. **systemd-tmpfiles runs** early in boot (before most services)
5. **systemd-tmpfiles checks** `/var` directory
6. **If /var is empty**: Copies from `/usr/share/factory/var`
7. **systemd.mount unit** mounts `/var` by filesystem UUID
8. **Services start** with populated `/var`

### Directory Structure

```
/
├── usr/
│   └── share/
│       └── factory/
│           └── var/              # Template (read-only, on rootfs)
│               ├── cache/
│               ├── lib/
│               ├── log/
│               ├── spool/
│               └── tmp/
└── var/                          # Runtime (read-write, separate LVM volume)
    ├── cache/
    ├── lib/
    ├── log/
    ├── spool/
    └── tmp/
```

## systemd-tmpfiles Configuration

File: `/usr/lib/systemd/tmpfiles.d/factory-var.conf`

```
C /var - - - - /usr/share/factory/var
```

### Configuration Format

- `C`: Copy directive - copy recursively if target doesn't exist
- `/var`: Target path
- `-`: Use default mode (preserve from source)
- `-`: Use default UID (preserve from source)
- `-`: Use default GID (preserve from source)
- `-`: No age argument (don't clean up)
- `/usr/share/factory/var`: Source path

### Other Available Directives

While we use `C` (copy), systemd-tmpfiles supports other directives:

- `L`: Create symlink
- `d`: Create directory
- `D`: Create directory and clean up contents on boot
- `f`: Create file if doesn't exist
- `z`: Set permissions without creating

## Benefits

### For OSTree/Atomic Updates

- `/var` is separate from atomic rootfs updates
- Factory template always available in rootfs
- Each deployment can have fresh `/var` if needed
- Rollbacks don't affect `/var` data

### For Persistent Data

- User data in `/var` persists across updates
- Can be backed up separately from system
- Can be resized independently
- Can be on different storage (SSD vs HDD)

### For Recovery

- If `/var` becomes corrupted, can be restored from factory
- Simple recovery: unmount `/var`, clear LVM volume, reboot
- Factory template is always pristine

## Usage

### Normal Boot (First Time)

```bash
# System boots, /var LVM volume is empty
# systemd-tmpfiles runs automatically
# Copies /usr/share/factory/var to /var
# Services start normally
```

### Manual Reset of /var

```bash
# Unmount /var
umount /var

# Clear and recreate the LVM volume (use lvs to identify the LV)
# Then reformat and set the required filesystem UUID:
# mkfs.ext4 -U d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55 <LV_DEVICE>

# Reboot - systemd-tmpfiles will repopulate
reboot
```

### Manual Population

```bash
# If you need to manually populate /var
systemd-tmpfiles --create --prefix=/var

# Or force recreation
systemd-tmpfiles --create --remove --prefix=/var
```

### Customize Factory Template

To customize what goes into `/var`:

1. Add packages that install to `/var`
2. Use ROOTFS_POSTPROCESS_COMMAND to modify contents
3. Factory template is created automatically during image build

Example:
```bitbake
# In your image recipe or bbappend
customize_factory_var() {
    # Add custom directory
    install -d ${IMAGE_ROOTFS}/var/myapp

    # Factory will include it
}
ROOTFS_POSTPROCESS_COMMAND += "customize_factory_var; "
```

## Integration with LVM /var

This works seamlessly with the separate `/var` LVM volume:

1. **Image build** creates factory template in rootfs
2. **WIC plugin** creates empty `/var` LVM volume
3. **systemd-mount-var.mount** mounts `/var` by filesystem UUID
4. **systemd-tmpfiles** populates if empty
5. **Services start** with working `/var`

### Mount Order

systemd ensures correct ordering:
```
systemd-tmpfiles-setup.service
  ├── After=local-fs.target
  └── Before=sysinit.target

var.mount
  ├── After=lvm2-activation.service
  └── Before=local-fs.target
```

So the sequence is:
1. LVM activation
2. Mount `/var` LVM volume
3. Run systemd-tmpfiles (populate from factory)
4. Continue boot

## Verification

### Check Factory Template Exists

```bash
ls -la /usr/share/factory/var/
```

### Check systemd-tmpfiles Configuration

```bash
cat /usr/lib/systemd/tmpfiles.d/factory-var.conf
```

### Test systemd-tmpfiles

```bash
# Dry-run to see what would be created
systemd-tmpfiles --create --dry-run --prefix=/var

# Show what systemd-tmpfiles would do
systemd-tmpfiles --cat-config | grep /var
```

### Check if /var was Populated

```bash
# Check for factory marker or timestamp
ls -la /var/

# Check systemd-tmpfiles service log
journalctl -u systemd-tmpfiles-setup.service
```

## Troubleshooting

### /var Not Populated

**Problem**: `/var` is empty after boot

**Check**:
```bash
# Verify factory template exists
ls /usr/share/factory/var/

# Check tmpfiles configuration
systemd-tmpfiles --cat-config | grep factory

# Check service status
systemctl status systemd-tmpfiles-setup.service

# Check logs
journalctl -u systemd-tmpfiles-setup.service
```

**Solution**:
- Ensure `systemd-conf` bbappend is applied
- Verify factory-var.conf exists in image
- Run manually: `systemd-tmpfiles --create --prefix=/var`

### Factory Template Empty

**Problem**: `/usr/share/factory/var/` is empty

**Check**:
```bash
# Check image recipe was applied
bitbake-layers show-appends | grep core-image-minimal

# Rebuild image
bitbake core-image-minimal -c cleanall
bitbake core-image-minimal
```

### Permission Issues

**Problem**: Files in `/var` have wrong permissions

**Solution**:
- Factory template preserves permissions from build
- Check permissions in `/usr/share/factory/var/`
- systemd-tmpfiles copies exactly

## References

- [systemd-tmpfiles Documentation](https://www.freedesktop.org/software/systemd/man/systemd-tmpfiles.html)
- [tmpfiles.d Configuration](https://www.freedesktop.org/software/systemd/man/tmpfiles.d.html)
- [Factory Reset Pattern](https://systemd.io/PORTABLE_SERVICES/)
