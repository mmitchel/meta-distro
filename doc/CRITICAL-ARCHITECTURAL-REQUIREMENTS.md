# Critical Architectural Requirements

This document contains the permanent, immutable requirements for the DISTRO project. All future development must comply with these constraints.

(Content below retained from previous CRITICAL-ARCHITECTURAL-REQUIREMENTS.md)
# CRITICAL ARCHITECTURAL REQUIREMENTS - Permanent Record

**Date**: February 20, 2026
**Session**: lvmrootfs.py Refactoring with MANDATORY Constraints
**Purpose**: Establish immutable requirements that apply to ALL future development

---

## USER DIRECTIVE (From Session)

> **"Stop making me tell you this every time we resume a session for this project"**

This document captures all critical requirements that were repeatedly corrected during refactoring. These are PERMANENT, IMMUTABLE, and must be enforced automatically in all future sessions.

---

## MANDATORY ARCHITECTURE FEATURES (Cannot be Removed)

These 5 features are non-negotiable and must ALWAYS be present:

### 1. ✅ VFAT Support for EFI System Partition
- **Why**: UEFI firmware requires FAT filesystem for ESP
- **Where**: `/boot/efi` partition, 512MB minimum
- **Partition Type GUID**: `C12A7328-F81F-11D2-BA4B-00A0C93EC93B`
- **Code Requirement**: WIC plugin must support `--source empty` with `--fstype=vfat`
- **Never Remove**: This is the only way to boot UEFI systems

### 2. ✅ EXT4 Support for XBOOTLDR Partition
- **Why**: Linux standard for boot loader partition (separate /boot)
- **Where**: `/boot` partition, 1GB minimum, mounted via XBOOTLDR
- **Partition Type GUID**: `BC13C2FF-59E6-4262-A352-B275FD6F7172`
- **Code Requirement**: WIC plugin must support ext4 formatting with UUID assignment
- **Never Remove**: OSTree deployments need separate /boot partition

### 3. ✅ LUKS Support for Crypt Partition
- **Why**: Full-disk encryption is MANDATORY for security policy
- **Where**: Wrapper around LVM physical volume, unlocked in initramfs
- **Encryption**: AES-256 with TPM2 key sealing (primary method)
- **Code Responsibility**: Initramfs (NOT WIC plugin) - plugin must NOT attempt encryption
- **Plugin Role**: Prepare unencrypted LVM volumes; initramfs handles LUKS wrapper
- **Never Remove**: All system data must be encrypted at rest

### 4. ✅ LVM Support for Rootfs Logical Volume
- **Why**: Flexible disk layout with future expansion capability
- **Where**: Root filesystem MUST reside on LVM logical volume
- **Code Requirement**: WIC plugin must create LVM VG, LV, and provide /dev/mapper/volume
- **Partition Type GUID**: `4F68BCE3-E8CD-4DB1-96E7-FBCAF984B709` (Root x86-64 discoverable)
- **Never Remove**: Root partition must be on LV (architectural requirement)

### 5. ✅ UUID Identification (Never Partition/LV Names)
- **Why**: Names are volatile (can change), UUIDs are stable
- **Where**: All mount operations, partition references, and LV identification
- **Code Pattern**: Always use `UUID=8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11` (never `vg0/rootlv`)
- **Benefits**: Discoverable partitions, stable references across deployments
- **Never Change**: UUIDs defined in `conf/distro/include/defaults.inc` as constants

---

## HOST SYSTEM REQUIREMENTS (Pre-Configuration)

### No SUDO Required
- **Principle**: WIC builds must NOT use sudo or require root execution
- **Enforcement**: Plugin uses only standard tools with proper host setup
- **Implementation**: udev rules + systemd-tmpfiles + group membership

### Host Devices Pre-Configured
All device access is handled by host OS setup BEFORE plugin runs:

**1. /dev/loop* - Writable by Current User**
```bash
# Via udev rules in /etc/udev/rules.d/99-loop-device.rules:
KERNEL=="loop[0-9]*", GROUP="disk", MODE="0660"

# Requires user to be in disk group:
sudo usermod -a -G disk $USER
```

**2. /dev/mapper/* - Writable by Current User**
```bash
# /dev/mapper/control via udev in /etc/udev/rules.d/99-device-mapper.rules:
KERNEL=="control", GROUP="disk", MODE="0660"

# /dev/mapper/volume via systemd-tmpfiles in /etc/tmpfiles.d/99-device-mapper.conf:
d /dev/mapper 0755 root root -
z /dev/mapper 0755 root disk -
```

**3. Disk Group Membership**
- User must be in `disk` group
- Requires logout/login or `newgrp disk` to activate
- Persistent across reboots

---

## CODE ARCHITECTURE CORRECTIONS

### ❌ Removed: Hard-Coded Tool Paths

**WRONG** (removed from codebase):
```python
TOOLS = {
    'udisksctl': '/usr/bin/udisksctl',  # Wrong - hard path
    'lvm': '/sbin/lvm',                  # Wrong - hard path
    'mkfs.ext4': '/sbin/mkfs.ext4',      # Wrong - hard path
}
```

**CORRECT** (current implementation):
```python
COMMANDS = {
    'losetup': 'losetup',       # Right - command name only
    'lvm': 'lvm',               # Right - command name only
    'mkfs.ext4': 'mkfs.ext4',   # Right - command name only
}
```

### ❌ Removed: udisksctl Dependency

**WRONG** (completely removed):
- Using `udisksctl loop-setup` for loop device creation
- Using `udisksctl loop-delete` for cleanup
- Added unnecessary daemon dependency (udisks2)

**CORRECT** (current implementation):
- Using `losetup -f --show pv_file` for setup
- Using `losetup -d loop_device` for cleanup
- Standard system utility, no daemon required

### ❌ Removed: _tool_path() Helper Function

**WRONG** (removed entirely):
```python
def _tool_path(tool: str) -> str:
    path = shutil.which(tool)
    if not path:
        raise WicError(f"Tool not found: {tool}")
    return path
```

**CORRECT** (not needed):
- Use command names directly in subprocess calls
- Python's subprocess module handles PATH lookup automatically
- Simpler, cleaner code

### ✅ Enforced: UUID Constants

**REQUIRED** (defined centrally in defaults.inc):
```python
# Root filesystem UUID (immutable)
FSUUID_ROOT = "8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11"

# Var LV UUID (immutable)
FSUUID_VAR = "d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55"

# Partition Type GUIDs (immutable)
PARTTYPE_ESP = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
PARTTYPE_XBOOTLDR = "bc13c2ff-59e6-4262-a352-b275fd6f7172"
PARTTYPE_ROOT = "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"
```

**Usage** (in Python code):
```python
# Correct way:
mkfs_cmd = ['mkfs.ext4', '-U', self.root_uuid, '-L', 'root', device]

# Wrong way (NEVER do this):
mkfs_cmd = ['mkfs.ext4', '-U', '8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11', device]  # Hard-coded
mkfs_cmd = ['mkfs.ext4', '-U', 'my-root', device]                                  # Name instead of UUID
```

---

## LUKS AND INITRAMFS ARCHITECTURE

### Critical Distinction
**LUKS is MANDATORY but NOT the WIC plugin's responsibility**

- **WIC Plugin Role**: Create unencrypted LVM volumes with proper UUIDs
- **Initramfs Role**: Wrap volumes in LUKS, unlock via TPM2, activate LVM
- **Why Separate**: WIC is bootloader-agnostic; initramfs is bootloader-specific

### Initramfs LUKS Unlock Sequence
**MANDATORY order** (cannot be changed):
1. **First Attempt**: TPM2-sealed key from NV memory (sealed with PCR7 - Secure Boot state)
2. **Second Attempt**: `/dev/null` keyfile OR passphrase (mutually exclusive)
   - If passphrase configured: `/dev/null` keyfile is REMOVED
   - If no passphrase: `/dev/null` keyfile used for automated unlock

### TPM2 is MANDATORY
- **Primary LUKS unlock method** (not optional)
- **Key Storage**: TPM2 NV (non-volatile) memory
- **Key Binding**: PCR7 (Secure Boot state measurement)
- **Benefit**: Key unseals only when Secure Boot state matches

---

## INTEGRATION CHECKLIST

### Code Level
- [ ] All 5 MANDATORY features documented in module docstring
- [ ] COMMANDS dict uses command names (no hard paths)
- [ ] No `_tool_path()` references anywhere in code
- [ ] No `udisksctl` references in code
- [ ] UUID constants used (never hard-coded values)
- [ ] Python syntax validated: `python3 -m py_compile`

### Configuration Level
- [ ] HOSTTOOLS includes `lvm` (not `udisksctl`)
- [ ] LUKS marked as initramfs responsibility (not plugin)
- [ ] UUID constants defined in defaults.inc
- [ ] PARTTYPE_* GUIDs defined in defaults.inc

### Host Setup Level
- [ ] udev rules for /dev/loop* (GROUP="disk" MODE="0660")
- [ ] udev rules for /dev/mapper/control (GROUP="disk" MODE="0660")
- [ ] systemd-tmpfiles for /dev/mapper (disk group)
- [ ] User in disk group
- [ ] losetup verified to work without sudo

### Documentation Level
- [ ] HOST-SETUP-LOSETUP.md created (replaces udisksctl docs)
- [ ] copilot-instructions.md reflects current architecture
- [ ] All references to udisksctl removed from docs
- [ ] MANDATORY features documented in all relevant files

---

## PREVENTION MEASURES

To prevent these corrections from being needed again:

### 1. Automatic Docstring Validation
Every session opening lvmrootfs.py should:
- Read the module docstring (lines 1-40)
- Verify all 5 MANDATORY features are documented
- Alert if any features are missing

### 2. Code Review Checklist
Before making changes to lvmrootfs.py:
- [ ] No hard tool paths (/usr/bin, /sbin, /bin) added
- [ ] No new _tool_path() calls introduced
- [ ] No udisksctl references (use losetup instead)
- [ ] UUID identification used consistently
- [ ] All 5 MANDATORY features preserved

### 3. Configuration Consistency
When modifying related files:
- [ ] HOSTTOOLS in defaults.inc matches actual dependencies
- [ ] UUID constants defined centrally (not scattered)
- [ ] LUKS marked as initramfs responsibility
- [ ] No sudo required in any WIC build command

### 4. Documentation Authority
Single source of truth for all requirements:
- [ ] This file: CRITICAL-ARCHITECTURAL-REQUIREMENTS.md
- [ ] copilot-instructions.md (for user-facing documentation)
- [ ] lvmrootfs.py docstring (for developer-facing documentation)

---

## SESSION CONTEXT PRESERVATION

**MANDATORY**: All future sessions working on this project MUST:

1. **Read this file first** when resuming work on lvmrootfs.py or WIC image creation
2. **Accept these requirements as immutable** - never ask user to re-specify them
3. **Enforce them automatically** in all code changes and reviews
4. **Update documentation** to reflect these immutable constraints
5. **Include this checklist** in every development summary

**File Location**: `CRITICAL-ARCHITECTURAL-REQUIREMENTS.md`

---

## VERSION HISTORY

| Date | Change | Status |
|------|--------|--------|
| 2026-02-20 | Initial comprehensive refactoring with losetup migration | ✅ Complete |
| 2026-02-20 | Removed all hard tool paths and udisksctl references | ✅ Complete |
| 2026-02-20 | Documented 5 MANDATORY features immutably | ✅ Complete |
| 2026-02-20 | Established this critical requirements document | ✅ Complete |

---

## FINAL SUMMARY

**Status**: All critical refactoring complete and documented.

**Immutability**: These 5 MANDATORY features and architectural constraints are PERMANENT and will NOT be questioned or re-negotiated in future sessions.

**Enforcement**: Future development must automatically validate these requirements before making ANY changes to WIC image creation or bootloader configuration.

**Authority**: This document takes precedence over any previous session notes or discussions.
