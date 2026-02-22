---
# Host Setup

This document consolidates all host setup instructions for building images, including LVM, loop devices, and general setup.

## Table of Contents
- General Host Setup
- LVM Setup
- Loop Device Setup

---

## General Host Setup

(Insert content from previous HOST-SETUP.md here.)

---

## LVM Setup

(Insert content from HOST-SETUP-LVM.md here.)

---

## Loop Device Setup

(Insert content from HOST-SETUP-LOSETUP.md here.)

---

# End of Host Setup Documentation
# Reload rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

**Verify**:

```bash
ls -la /dev/loop0
# Expected: crw-rw---- root disk

# Test with your user
losetup -f
# Should succeed without sudo
```

### 2.2 Device Mapper (`/dev/mapper/*`)

Device-mapper provides LVM logical volume management.

**Setup via udev rules** (recommended):

```bash
# Create rule file
sudo tee /etc/udev/rules.d/99-device-mapper.rules > /dev/null <<EOF
KERNEL=="control", GROUP="disk", MODE="0660"
KERNEL=="dm-*", GROUP="disk", MODE="0660"
EOF

# Reload rules
sudo udevadm control --reload-rules
sudo udevadm trigger
```

**Alternative: Setup via systemd-tmpfiles** (if udev rules don't work):

```bash
# Create tmpfiles configuration
sudo tee /etc/tmpfiles.d/dm-control.conf > /dev/null <<'EOF'
z /dev/mapper/control 0660 root disk - -
EOF

# Apply immediately
sudo systemd-tmpfiles --create /etc/tmpfiles.d/dm-control.conf

# Verify
ls -l /dev/mapper/control
# Expected: crw-rw---- 1 root disk
```

**Setup via systemd-tmpfiles** (persistent across reboots):

```bash
# Create tmpfiles configuration
sudo tee /etc/tmpfiles.d/99-device-mapper.conf > /dev/null <<EOF
# Device-mapper directory permissions
d /dev/mapper 0755 root root -
z /dev/mapper 0755 root disk -
EOF

# Apply immediately
sudo systemctl restart systemd-tmpfiles-setup.service
```

**Verify**:

```bash
ls -la /dev/mapper/
# /dev/mapper should be writable by disk group

stat /dev/mapper/control
# Expected: Access: (0660/crw-rw----)  Uid: (   0/ root)   Gid: ( X/disk)
```

---

## 3. Package Installation

Install all required tools for LVM image creation.

### Ubuntu/Debian

```bash
sudo apt-get update && sudo apt-get install -y \
    lvm2 \
    cryptsetup \
    e2fsprogs \
    dosfstools \
    parted \
    sgdisk \
    losetup \
    tar \
    dd \
    mount
```

### Fedora/RHEL/CentOS

```bash
sudo dnf install -y \
    lvm2 \
    cryptsetup \
    e2fsprogs \
    dosfstools \
    parted \
    gdisk \
    util-linux \
    tar \
    coreutils \
    util-linux
```

### Alpine

```bash
sudo apk add \
    lvm2 \
    cryptsetup \
    e2fsprogs \
    dosfstools \
    parted \
    gptfdisk
```

---

## 4. Verify Tool Availability

Check that all required tools are in PATH:

```bash
#!/bin/bash

echo "Verifying required tools..."
for tool in losetup lvm cryptsetup mkfs.vfat mkfs.ext4 mount umount dd tar sgdisk; do
    if command -v "$tool" &> /dev/null; then
        echo "✓ $tool found"
    else
        echo "✗ $tool NOT found - install required packages"
    fi
done
```

---

## 5. Complete Host Setup Script

Automate all configuration steps:

```bash
#!/bin/bash
set -e

echo "=== DISTRO Project - Host Setup for WIC LVM ==="
echo ""

# 1. Install required packages
echo "1. Installing required packages..."
if command -v apt-get &> /dev/null; then
    echo "   Detected: Ubuntu/Debian"
    sudo apt-get update
    sudo apt-get install -y \
        lvm2 cryptsetup e2fsprogs dosfstools \
        parted sgdisk tar coreutils util-linux
elif command -v dnf &> /dev/null; then
    echo "   Detected: Fedora/RHEL"
    sudo dnf install -y \
        lvm2 cryptsetup e2fsprogs dosfstools \
        parted gdisk tar coreutils util-linux
elif command -v apk &> /dev/null; then
    echo "   Detected: Alpine"
    sudo apk add \
        lvm2 cryptsetup e2fsprogs dosfstools \
        parted gptfdisk tar coreutils util-linux
else
    echo "ERROR: Unsupported package manager"
    exit 1
fi
echo "   ✓ Packages installed"
echo ""

# 2. Add user to disk group
echo "2. Adding $USER to disk group..."
sudo usermod -a -G disk "$USER" 2>/dev/null || true
echo "   ✓ User added to disk group"
echo ""

# 3. Setup udev rules
echo "3. Setting up udev rules..."
sudo tee /etc/udev/rules.d/99-loop-device.rules > /dev/null <<'EOF'
KERNEL=="loop[0-9]*", GROUP="disk", MODE="0660"
EOF

sudo tee /etc/udev/rules.d/99-device-mapper.rules > /dev/null <<'EOF'
KERNEL=="control", GROUP="disk", MODE="0660"
KERNEL=="dm-*", GROUP="disk", MODE="0660"
EOF
echo "   ✓ Udev rules created"
echo ""

# 4. Setup systemd-tmpfiles
echo "4. Setting up systemd-tmpfiles..."
sudo tee /etc/tmpfiles.d/99-device-mapper.conf > /dev/null <<'EOF'
d /dev/mapper 0755 root root -
z /dev/mapper 0755 root disk -
EOF
echo "   ✓ Tmpfiles configuration created"
echo ""

# 5. Reload udev and tmpfiles
echo "5. Applying configuration..."
sudo udevadm control --reload-rules
sudo udevadm trigger
sudo systemctl restart systemd-tmpfiles-setup.service 2>/dev/null || true
echo "   ✓ Configuration applied"
echo ""

# 6. Verify setup
echo "6. Verifying setup..."
if id "$USER" | grep -q disk; then
    echo "   ✓ User in disk group"
else
    echo "   ✗ User NOT in disk group (requires re-login)"
fi

if [ -c /dev/loop0 ]; then
    PERMS=$(stat -c %A /dev/loop0)
    if [[ "$PERMS" == *"rw"* ]]; then
        echo "   ✓ Loop device is readable/writable"
    else
        echo "   ✗ Loop device permissions incorrect: $PERMS"
    fi
else
    echo "   ✗ /dev/loop0 not found"
fi

if [ -e /dev/mapper/control ]; then
    PERMS=$(stat -c %A /dev/mapper/control)
    if [[ "$PERMS" == *"rw"* ]]; then
        echo "   ✓ Device mapper is readable/writable"
    else
        echo "   ✗ Device mapper permissions incorrect: $PERMS"
    fi
else
    echo "   ✗ /dev/mapper/control not found"
fi

echo ""
echo "=== Setup Complete ==="
echo ""
echo "IMPORTANT: You must logout and login again (or run 'newgrp disk') to apply group changes."
echo ""
echo "After re-login, verify setup with:"
echo "  id | grep disk"
echo "  ls -la /dev/loop0 /dev/mapper/control"
echo ""
echo "Then you can build with:"
echo "  cd <project-root>"
echo "  source layers/poky/oe-init-build-env"
echo "  bitbake core-image-minimal"
```

Save the script:

```bash
# Save to file
cat > ~/setup-wic-host.sh << 'SETUP_EOF'
# ... (paste script above) ...
SETUP_EOF

# Make executable and run
chmod +x ~/setup-wic-host.sh
~/setup-wic-host.sh
```

---

## 6. Verification Checklist

After setup, verify all requirements:

```bash
#!/bin/bash

echo "Verifying WIC LVM host setup..."
echo ""

# 1. Disk group
echo "1. Checking disk group membership..."
if id | grep -q disk; then
    echo "   ✓ User in disk group"
else
    echo "   ✗ User NOT in disk group (run: newgrp disk or re-login)"
fi
echo ""

# 2. Loop devices
echo "2. Checking loop device permissions..."
if [ -c /dev/loop0 ]; then
    PERMS=$(stat -c %A /dev/loop0)
    echo "   /dev/loop0 permissions: $PERMS"
    if [[ "$PERMS" == *"rw"* ]]; then
        echo "   ✓ Loop device is readable/writable by user"
    else
        echo "   ✗ Loop device not writable (run setup script again)"
    fi
else
    echo "   ✗ /dev/loop0 not found (reload udev rules)"
fi
echo ""

# 3. Device mapper
echo "3. Checking device mapper permissions..."
if [ -e /dev/mapper/control ]; then
    PERMS=$(stat -c %A /dev/mapper/control)
    echo "   /dev/mapper/control permissions: $PERMS"
    if [[ "$PERMS" == *"rw"* ]]; then
        echo "   ✓ Device mapper is readable/writable by user"
    else
        echo "   ✗ Device mapper not writable (run setup script again)"
    fi
else
    echo "   ✗ /dev/mapper/control not found"
fi
echo ""

# 4. Required tools
echo "4. Checking required tools..."
TOOLS="losetup lvm cryptsetup mkfs.vfat mkfs.ext4 mount umount dd tar sgdisk"
MISSING=0
for tool in $TOOLS; do
    if command -v "$tool" &> /dev/null; then
        echo "   ✓ $tool found"
    else
        echo "   ✗ $tool NOT found - install lvm2 and related packages"
        MISSING=1
    fi
done
echo ""

# 5. Test loop device setup
echo "5. Testing loop device functionality..."
TEST_FILE=$(mktemp /tmp/wic-test-XXXXX.img)
dd if=/dev/zero of="$TEST_FILE" bs=1M count=0 seek=100 2>/dev/null
LOOP=$(losetup -f --show "$TEST_FILE")
if [ -b "$LOOP" ]; then
    echo "   ✓ Loop device setup works: $LOOP"
    losetup -d "$LOOP"
else
    echo "   ✗ Loop device setup failed"
    MISSING=1
fi
rm -f "$TEST_FILE"
echo ""

# 6. Test LVM operations
echo "6. Testing LVM operations..."
TEST_FILE=$(mktemp /tmp/wic-test-XXXXX.img)
dd if=/dev/zero of="$TEST_FILE" bs=1M count=0 seek=100 2>/dev/null
LOOP=$(losetup -f --show "$TEST_FILE")
if lvm pvcreate --nolocking -ff -y "$LOOP" 2>/dev/null; then
    echo "   ✓ LVM pvcreate works"
    lvm vgcreate --nolocking test-vg "$LOOP" 2>/dev/null || true
    lvm vgchange --nolocking -an test-vg 2>/dev/null || true
    lvm vgremove --nolocking -f test-vg 2>/dev/null || true
    lvm pvremove --nolocking -f "$LOOP" 2>/dev/null || true
else
    echo "   ✗ LVM pvcreate failed"
    MISSING=1
fi
losetup -d "$LOOP" 2>/dev/null || true
rm -f "$TEST_FILE"
echo ""

# Summary
echo "=== Verification Complete ==="
if [ $MISSING -eq 0 ]; then
    echo "✓ All checks passed - ready to build!"
else
    echo "✗ Some checks failed - see above for details"
    exit 1
fi
```

Save and run verification:

```bash
# Save verification script
cat > ~/verify-wic-setup.sh << 'VERIFY_EOF'
# ... (paste script above) ...
VERIFY_EOF

chmod +x ~/verify-wic-setup.sh
~/verify-wic-setup.sh
```

---

## 7. Troubleshooting

### Permission Denied on /dev/loop*

```bash
# Verify udev rules are active
ls -la /dev/loop0
# Should show: crw-rw---- root disk

# If not correct, reload udev
sudo udevadm control --reload-rules
sudo udevadm trigger

# Check disk group membership
id | grep disk
# If missing, run: newgrp disk or re-login
```

### Cannot Access /dev/mapper/control

```bash
# Check permissions
ls -la /dev/mapper/control
stat /dev/mapper/control

# Fix with udev rules (preferred)
sudo tee /etc/udev/rules.d/99-device-mapper.rules > /dev/null <<EOF
KERNEL=="control", GROUP="disk", MODE="0660"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger

# OR fix with systemd-tmpfiles
sudo tee /etc/tmpfiles.d/dm-control.conf > /dev/null <<'EOF'
z /dev/mapper/control 0660 root disk - -
EOF
sudo systemd-tmpfiles --create /etc/tmpfiles.d/dm-control.conf
```

### lvm Command Not Found

```bash
# Verify lvm is installed
which lvm

# Install lvm2 package
# Ubuntu/Debian
sudo apt-get install lvm2

# Fedora/RHEL
sudo dnf install lvm2

# Alpine
sudo apk add lvm2
```

### losetup -P Not Supported

```bash
# The -P flag requires kernel 5.8+
uname -r

# If older kernel, manually create loop partitions
# Or upgrade to newer kernel/OS version
```

### "Operation not permitted" During Mount

```bash
# Non-root mount requires one of:
# 1. User namespace support (WIC usually handles this)
# 2. CAP_SYS_ADMIN capability
# 3. SUID mount (may be disabled for security)

# For WIC builds, this is normally handled by bitbake's build environment
# which has elevated capabilities. Manual testing may fail as regular user.
```

### Device Busy During Cleanup

```bash
# Ensure all mounts are unmounted
mount | grep /dev/mapper/
# Unmount any remaining mounts:
sudo umount /dev/mapper/*

# Ensure LVM is deactivated
lvm vgchange --nolocking -an

# Ensure loop devices are detached
losetup -l
# Detach any remaining:
sudo losetup -d /dev/loopX
```

---

## 8. LVM and Cryptsetup Integration

### LVM Operations with --nolocking

The WIC plugin uses `--nolocking` flag for all LVM operations to support non-root execution:

```bash
# Examples of LVM commands used
lvm pvcreate --nolocking /dev/loopX
lvm vgcreate --nolocking vg0 /dev/loopX
lvm lvcreate --nolocking -L 4096M -n rootlv vg0
lvm vgchange --nolocking -ay vg0
lvm vgchange --nolocking -an vg0
```

The `--nolocking` flag is safe for WIC builds (single-threaded, no concurrency).

### LUKS Encryption Integration

LUKS encryption is managed by the initramfs boot sequence:

```bash
# Encryption parameters
cryptsetup luksFormat --type luks2 /dev/loopX
cryptsetup open /dev/loopX cryptroot

# The root partition UUID is used for automatic unlock
# Primary method: TPM2-sealed keys (sealed with PCR7)
# Fallback method: /dev/null keyfile or passphrase
```

---

## 9. Quick Start

Once host setup is complete:

```bash
# 1. Clone repository
git clone https://github.com/mmitchel/meta-distro.git
cd meta-distro

# 2. Initialize build environment
source setup-build.sh
# OR for subsequent builds:
source layers/poky/oe-init-build-env

# 3. Build verification images (both tested and supported)
bitbake core-image-minimal          # Minimal bootable image
bitbake core-image-full-cmdline     # Full-featured console image with package management

# 4. Find image artifacts
ls -lh build/tmp/deploy/images/qemux86-64/core-image-*qemux86-64.wic*
```

---

## 10. Additional Resources

- **Project README**: `README.md`
- **WIC Plugin Documentation**: `layers/meta-distro/scripts/lib/wic/README.md`
- **Build Instructions**: `CRITICAL-ARCHITECTURAL-REQUIREMENTS.md`
- **Yocto Documentation**: https://docs.yoctoproject.org/
- **LVM Documentation**: https://tldp.org/HOWTO/LVM-HOWTO/

---

**Last Updated**: February 20, 2026
**Version**: 1.0 (Merged HOST-SETUP documentation)
