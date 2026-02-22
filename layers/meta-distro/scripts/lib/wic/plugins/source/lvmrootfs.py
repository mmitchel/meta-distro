#!/usr/bin/env python3
#
# Copyright (c) 2026 DISTRO Project
#
# SPDX-License-Identifier: MIT
#

"""
WIC Plugin: Create LVM-based disk images with GPT partitions

Architecture:
=============
GPT Partition Table:
  Partition 1: EFI System Partition (512MB, VFAT, unencrypted)
  Partition 2: XBOOTLDR Partition (1GB, ext4, unencrypted)
  Partition 3: LUKS-Encrypted Partition (remaining space)
    └─ LVM Physical Volume (inside LUKS)
       ├─ rootfs Logical Volume (ext4, /rootfs content except /boot and /boot/efi)
       ├─ Additional Logical Volumes (optional)
       └─ varfs Logical Volume (optional, ext4, /var content)       

Execution Sequence (exactly as per reference script):
=====================================================
Phase 1: Create sparse disk image file with dd
Phase 2: Attach loop device WITHOUT --partscan (first attachment)
Phase 3: Zap and create GPT partition table with sgdisk
Phase 4: Detach loop device (force kernel to sync partition table)
Phase 5: Re-attach loop device WITH --partscan (creates /dev/loop0p1, p2, p3)
Phase 6: Format EFI partition (mkfs.vfat)
Phase 7: Format XBOOTLDR partition (mkfs.ext4)
Phase 8: Format and open LUKS on partition 3
Phase 9: Create LVM volume group and logical volumes
Phase 10: Create logical volumes (rootfs + additional volumes)
Phase 11: Mount all filesystems and populate with rootfs content
Phase 12: Unmount all filesystems, close LUKS, deactivate LVM, detach loop
Phase 13: Summary and artifact verification (bonus)

Host Prerequisites:
===================
This plugin requires NO user account escalation during normal WIC execution, BUT requires
PRIOR SUDO CONFIGURATION for the build user to run storage commands without password prompts.

Setup (one-time, requires sudo access):
1. Add user to disk group:
   sudo usermod -a -G disk $USER

2. Configure sudoers for passwordless storage commands:
   sudo visudo -f /etc/sudoers.d/storage
   
   Add these lines (replace USERNAME with actual username):
   -------
   # lvmrootfs.py storage commands with minimal arguments
   Cmnd_Alias LVM_CMDS = \
       /usr/sbin/lvm pvcreate --nolocking -ff -y /dev/loop*, \
       /usr/sbin/lvm vgcreate --nolocking * /dev/loop*, \
       /usr/sbin/lvm lvcreate --nolocking -L * -n * *, \
       /usr/sbin/lvm lvcreate --nolocking -l * -n * *, \
       /usr/sbin/lvm lvchange --nolocking -an /dev/*/*, \
       /usr/sbin/lvm vgchange --nolocking -an *, \
       /usr/sbin/lvm vgchange --nolocking -an -P *, \
       /usr/sbin/lvm vgremove --nolocking -ff -y *
   
   Cmnd_Alias CRYPT_CMDS = \
       /usr/sbin/cryptsetup -q luksFormat --type * /dev/loop*, \
       /usr/sbin/cryptsetup open /dev/loop* *, \
       /usr/sbin/cryptsetup close /dev/mapper/*
   
   Cmnd_Alias LOOP_CMDS = \
       /usr/sbin/losetup --find --show /tmp/*, \
       /usr/sbin/losetup --find --show --partscan /tmp/*, \
       /usr/sbin/losetup --detach /dev/loop*
   
   Cmnd_Alias PART_CMDS = \
       /usr/sbin/sgdisk --zap-all /dev/loop*, \
       /usr/sbin/sgdisk --new=* --typecode=* --change-name=* /dev/loop*
   
   Cmnd_Alias FS_CMDS = \
       /usr/sbin/mkfs.vfat -F 32 /dev/loop*p*, \
       /usr/sbin/mkfs.ext4 -F /dev/loop*p*, \
       /usr/sbin/mkfs.ext4 -F /dev/mapper/*
   
   Cmnd_Alias MOUNT_CMDS = \
       /usr/bin/mount -t vfat -o * /dev/loop*p* /tmp/*, \
       /usr/bin/mount -t ext4 /dev/loop*p* /tmp/*, \
       /usr/bin/mount /dev/mapper/* /tmp/*, \
       /usr/bin/umount /tmp/*/system/boot/efi, \
       /usr/bin/umount /tmp/*/system/boot, \
       /usr/bin/umount /tmp/*/system, \
       /usr/bin/umount /tmp/*
   
   Cmnd_Alias DD_CMDS = \
       /usr/bin/dd if=/dev/zero of=/tmp/* bs=1M count=0 seek=*
   
   USERNAME ALL=(root) NOPASSWD: LVM_CMDS, CRYPT_CMDS, LOOP_CMDS, PART_CMDS, FS_CMDS, MOUNT_CMDS, DD_CMDS
   -------

3. Verify sudo works without password:
   sudo losetup --version
   sudo lvm version
   sudo cryptsetup --version
"""

import os
import sys
import logging
import tempfile
import subprocess
import json
import shutil
from dataclasses import dataclass, field
from typing import Optional, Dict, List, Tuple
from enum import Enum

# Logging setup
logging.basicConfig(
    level=logging.DEBUG,
    format='%(levelname)s: %(message)s',
    stream=sys.stderr
)
logger = logging.getLogger(os.path.basename(__file__))

# Suppress excessive LVM warnings
os.environ['LVM_SUPPRESS_FD_WARNINGS'] = '1'


# ============================================================================
# Data Models
# ============================================================================

@dataclass
class LogicalVolumeSpec:
    """Specification for a logical volume"""
    name: str
    size_str: str  # "100%FREE", "1024M", "2048", etc.
    size_mb: Optional[int] = None
    uuid: str = ""

    def __post_init__(self):
        if not self.uuid:
            self.uuid = self._generate_uuid()

    @staticmethod
    def _generate_uuid():
        import uuid
        return str(uuid.uuid4())


@dataclass
class MountPointSpec:
    """Specification for mounting a volume"""
    lv_name: str
    mountpoint: str


@dataclass
class DiskConfig:
    """Complete disk configuration"""
    vg_name: str = "vg0"
    luks_name: str = "cryptroot"
    luks_passphrase: Optional[str] = None
    rootfs_lv: LogicalVolumeSpec = field(default_factory=lambda: LogicalVolumeSpec("rootlv", "CALCULATED"))
    additional_lvs: List[LogicalVolumeSpec] = field(default_factory=list)
    mount_points: List[MountPointSpec] = field(default_factory=list)
    luks_enabled: bool = True

    def calculate_rootfs_lv_size(self, crypt_partition_size_mb: int) -> int:
        """Calculate rootfs LV size given LUKS partition size"""
        # Sum fixed-size LVs
        fixed_size = sum(lv.size_mb for lv in self.additional_lvs if lv.size_mb)
        # Reserve 4MB for LVM metadata
        rootfs_size = crypt_partition_size_mb - fixed_size - 4
        if rootfs_size <= 0:
            raise Exception(f"Insufficient space: crypt_partition={crypt_partition_size_mb}MB, fixed_lvs={fixed_size}MB")
        return rootfs_size


@dataclass
class ExecutionPlan:
    """Execution plan with ordered steps and state tracking"""
    steps: List[Tuple] = field(default_factory=list)
    state: Dict = field(default_factory=dict)

    def add_step(self, name: str, func, args: List = None, kwargs: Dict = None):
        """Queue an execution step"""
        self.steps.append((name, func, args or [], kwargs or {}))


# ============================================================================
# Utility Functions
# ============================================================================

def _run_cmd(cmd, check=True, capture=False):
    """
    Execute a system command with proper PATH search

    Args:
        cmd: Command string or list
        check: Whether to check return code and raise on failure
        capture: Whether to capture and return stdout

    Returns:
        stdout string if capture=True, else None
    """
    if isinstance(cmd, str):
        cmd = cmd.split()

    try:
        logger.debug(f"Executing: {' '.join(cmd)}")
        env = os.environ.copy()
        env['LVM_SUPPRESS_FD_WARNINGS'] = '1'

        # Ensure we have a complete PATH including sbin directories
        if 'PATH' not in env:
            env['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        else:
            # Prepend sbin directories if missing
            path_parts = env['PATH'].split(':')
            sbin_paths = [p for p in path_parts if 'sbin' in p]
            if not sbin_paths:
                env['PATH'] = '/usr/sbin:/usr/bin:/sbin:/bin:' + env['PATH']

        # Resolve command path using shutil.which() to handle sbin locations
        # This handles cases where subprocess.run() can't find executables in sbin
        # For LVM commands, prefer host system version to avoid library issues
        resolved_cmd = list(cmd)
        if resolved_cmd and not os.path.isabs(resolved_cmd[0]):
            # For LVM, explicitly search in host system paths first (/usr/sbin, /sbin)
            if resolved_cmd[0] == 'lvm':
                # Try host system lvm first
                host_lvm = None
                for path_dir in ['/usr/sbin', '/sbin', '/usr/bin', '/bin']:
                    candidate = os.path.join(path_dir, 'lvm')
                    if os.path.isfile(candidate) and os.access(candidate, os.X_OK):
                        host_lvm = candidate
                        logger.debug(f"Found host lvm at {host_lvm}")
                        break
                if host_lvm:
                    resolved_cmd[0] = host_lvm
                else:
                    # Fallback to shutil.which
                    found_path = shutil.which(resolved_cmd[0], path=env['PATH'])
                    if found_path:
                        resolved_cmd[0] = found_path
                        logger.debug(f"Resolved {cmd[0]} to {found_path}")
            else:
                # For non-LVM commands, use standard shutil.which
                found_path = shutil.which(resolved_cmd[0], path=env['PATH'])
                if found_path:
                    resolved_cmd[0] = found_path
                    logger.debug(f"Resolved {cmd[0]} to {found_path}")

        result = subprocess.run(
            resolved_cmd,
            check=False,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            env=env
        )

        if result.returncode != 0 and check:
            raise Exception(
                f"Command failed with code {result.returncode}: {' '.join(cmd)}\n"
                f"stderr: {result.stderr}"
            )

        if capture:
            return result.stdout.strip()
        return None
    except Exception as e:
        if check:
            raise Exception(f"Failed to execute command: {e}")
        logger.warning(f"Command warning: {e}")
        return None


def _run_cmd_sudo(cmd, check=True, capture=False):
    """
    Execute a system command with sudo for elevated privileges.
    
    This is required for storage commands that need root access:
    - lvm operations
    - cryptsetup operations
    - losetup operations
    - mount/umount operations
    
    Assumes the user has been configured with NOPASSWD sudoers rules.

    Args:
        cmd: Command string or list
        check: Whether to check return code and raise on failure
        capture: Whether to capture and return stdout

    Returns:
        stdout string if capture=True, else None
    """
    if isinstance(cmd, str):
        cmd = cmd.split()

    # Prepend sudo
    sudo_cmd = ['sudo'] + cmd

    try:
        logger.debug(f"Executing with sudo: {' '.join(sudo_cmd)}")
        env = os.environ.copy()
        env['LVM_SUPPRESS_FD_WARNINGS'] = '1'

        # Ensure we have a complete PATH including sbin directories
        if 'PATH' not in env:
            env['PATH'] = '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
        else:
            # Prepend sbin directories if missing
            path_parts = env['PATH'].split(':')
            sbin_paths = [p for p in path_parts if 'sbin' in p]
            if not sbin_paths:
                env['PATH'] = '/usr/sbin:/usr/bin:/sbin:/bin:' + env['PATH']

        # Don't resolve 'sudo' itself, let system find it
        resolved_cmd = list(sudo_cmd)

        result = subprocess.run(
            resolved_cmd,
            check=False,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE,
            universal_newlines=True,
            env=env
        )

        if result.returncode != 0 and check:
            raise Exception(
                f"Command failed with code {result.returncode}: {' '.join(sudo_cmd)}\n"
                f"stderr: {result.stderr}"
            )

        if capture:
            return result.stdout.strip()
        return None
    except Exception as e:
        if check:
            raise Exception(f"Failed to execute sudo command: {e}")
        logger.warning(f"Sudo command warning: {e}")
        return None



# ============================================================================
# Initialization and Cleanup
# ============================================================================

def _init_cleanup_orphaned_loop_devices():
    """Cleanup Phase: Enumerate and remove orphaned loop devices

    This initialization phase runs at the start to clean up any loop devices
    that are attached to image files that no longer exist. This can happen if:
    - A previous WIC build was interrupted
    - An image file was deleted but losetup wasn't called
    - The system crashed while a loop device was attached
    """
    try:
        # Get list of all loop devices and their backing files
        cmd = ['losetup', '-a']
        output = _run_cmd(cmd, capture=True, check=False)

        if not output or output.strip() == '':
            logger.debug("No loop devices currently attached")
            return

        logger.info("=== Cleanup Phase: Checking for orphaned loop devices ===")

        # Parse losetup output: /dev/loop0: [0805]:0 (/path/to/file)
        lines = output.strip().split('\n')
        orphaned_count = 0

        for line in lines:
            if not line.strip():
                continue

            # Extract loop device and file path
            # Format: /dev/loopX: [...]  (/path/to/file)
            if '(' not in line or ')' not in line:
                continue

            loop_device = line.split(':')[0].strip()
            file_path = line[line.rfind('(') + 1:line.rfind(')')].strip()

            # Check if the backing file still exists
            if not os.path.exists(file_path):
                logger.info(f"Found orphaned loop device: {loop_device} → {file_path} (DELETED)")

                try:
                    # Detach the orphaned loop device
                    cmd = ['losetup', '-d', loop_device]
                    _run_cmd(cmd, check=False)
                    logger.info(f"  ✓ Detached orphaned loop device: {loop_device}")
                    orphaned_count += 1
                except Exception as e:
                    logger.warning(f"  ✗ Failed to detach {loop_device}: {e}")
            else:
                logger.debug(f"Loop device {loop_device} → {file_path} (exists, keeping)")

        if orphaned_count > 0:
            logger.info(f"✓ Cleanup complete: removed {orphaned_count} orphaned loop device(s)")
        else:
            logger.debug("No orphaned loop devices found")

    except Exception as e:
        logger.warning(f"Cleanup phase warning (non-fatal): {e}")


def _check_sudo_access():
    """Verify sudo is properly configured by checking version info for required commands
    
    This function tests that all required storage commands can be executed with sudo
    and without password prompts. It checks version information from each command.
    
    Raises:
        Exception if any required command is not accessible via sudo
    """
    required_commands = {
        'lvm': ['lvm', 'version'],
        'cryptsetup': ['cryptsetup', '--version'],
        'losetup': ['losetup', '--version'],
        'sgdisk': ['sgdisk', '--version'],
        'mkfs.vfat': ['mkfs.vfat', '--help'],  # Some systems don't have --version
        'mkfs.ext4': ['mkfs.ext4', '-V'],
        'mount': ['mount', '--version'],
        'umount': ['umount', '--version'],
    }
    
    logger.info("=== Verifying Sudo Access ===")
    logger.debug("Checking sudo access for storage commands...")
    
    failed_commands = []
    
    for cmd_name, cmd_list in required_commands.items():
        try:
            # Try to get version/help from command via sudo
            result = subprocess.run(
                ['sudo'] + cmd_list,
                capture_output=True,
                universal_newlines=True,
                timeout=5,
                check=False
            )
            
            if result.returncode == 0 or result.returncode == 1:  # Some commands return 1 for --version
                # Extract first line of output for logging
                output_line = (result.stdout or result.stderr).split('\n')[0][:60]
                logger.debug(f"  ✓ {cmd_name}: {output_line}")
            else:
                failed_commands.append((cmd_name, result.returncode, result.stderr))
                logger.error(f"  ✗ {cmd_name}: Failed with code {result.returncode}")
        
        except subprocess.TimeoutExpired:
            failed_commands.append((cmd_name, 'timeout', 'Command timeout'))
            logger.error(f"  ✗ {cmd_name}: Timeout (possibly waiting for password)")
        
        except FileNotFoundError:
            failed_commands.append((cmd_name, 'not_found', 'Command not found'))
            logger.error(f"  ✗ {cmd_name}: Command not found in PATH")
        
        except Exception as e:
            failed_commands.append((cmd_name, 'error', str(e)))
            logger.error(f"  ✗ {cmd_name}: {e}")
    
    if failed_commands:
        error_msg = "Sudo access verification failed for:\n"
        for cmd_name, error_code, error_detail in failed_commands:
            error_msg += f"  - {cmd_name}: {error_code} ({error_detail})\n"
        error_msg += "\nEnsure sudoers is configured with NOPASSWD for storage commands:\n"
        error_msg += "  sudo visudo -f /etc/sudoers.d/storage\n"
        error_msg += "  # Add: USERNAME ALL=(root) NOPASSWD: /usr/sbin/lvm, /usr/sbin/cryptsetup, etc."
        raise Exception(error_msg)
    
    logger.info("✓ All required sudo commands are accessible")



# ============================================================================
# Phase Implementations
# ============================================================================

def _phase1_create_sparse_file(pv_file: str, total_size_mb: int):
    """Phase 1: Create sparse disk image file"""
    try:
        cmd = ['dd', 'if=/dev/zero', f'of={pv_file}', 'bs=1M', 'count=0', f'seek={total_size_mb}']
        _run_cmd(cmd)
        logger.info(f"✓ Sparse disk image created: {pv_file} ({total_size_mb}MB)")
    except Exception as e:
        raise Exception(f"Failed to create sparse disk image: {e}")


def _phase2_loop_attach(pv_file: str) -> str:
    """Phase 2: Attach loop device WITHOUT --partscan"""
    try:
        cmd = ['losetup', '--find', '--show', pv_file]
        loop_device = _run_cmd(cmd, capture=True).strip()
        logger.info(f"✓ Phase 2: Loop device attached (no partscan): {loop_device}")
        return loop_device
    except Exception as e:
        raise Exception(f"Failed to attach loop device: {e}")


def _phase3_create_gpt_partition_table(loop_device: str) -> Dict:
    """Phase 3: Zap and create GPT partition table with sgdisk"""
    try:
        # Zap all (erase old partition table if any)
        cmd = ['sgdisk', '--zap-all', loop_device]
        _run_cmd(cmd, check=False)

        # Create all partitions in one sgdisk call
        # Using exact layout from reference script
        cmd = ['sgdisk',
               '--new=1:1MiB:+512MiB', '--typecode=1:EF00', '--change-name=1:efi',
               '--new=2:0:+1024MiB', '--typecode=2:EA00', '--change-name=2:xbootldr',
               '--new=3:0:0', '--typecode=3:8304', '--change-name=3:crypt_lvm',
               loop_device]
        _run_cmd(cmd)

        logger.info(f"✓ Phase 3: GPT partition table created with sgdisk")

        return {
            'efi_partition': f"{loop_device}p1",
            'boot_partition': f"{loop_device}p2",
            'luks_partition': f"{loop_device}p3",
        }
    except Exception as e:
        raise Exception(f"Failed to create GPT partition table: {e}")


def _phase4_detach_loop(loop_device: str):
    """Phase 4: Detach loop device to force kernel to sync partition table"""
    try:
        cmd = ['losetup', '--detach', loop_device]
        _run_cmd(cmd)
        logger.info(f"✓ Phase 4: Loop device detached")
    except Exception as e:
        raise Exception(f"Failed to detach loop device: {e}")


def _phase5_reattach_with_partscan(pv_file: str) -> str:
    """Phase 5: Re-attach loop device WITH --partscan to create partition devices"""
    import time
    try:
        cmd = ['losetup', '--find', '--show', '--partscan', pv_file]
        loop_device = _run_cmd(cmd, capture=True).strip()
        logger.info(f"✓ Phase 5: Loop device re-attached with --partscan: {loop_device}")
        
        # Wait for partition devices to be created
        time.sleep(1)
        
        # Verify partition devices exist
        base = os.path.basename(loop_device)
        parent_dir = os.path.dirname(loop_device) or '/dev'
        
        for i in range(1, 4):
            partition_dev = os.path.join(parent_dir, f"{base}p{i}")
            if not os.path.exists(partition_dev):
                raise Exception(f"Partition device {partition_dev} not created after --partscan")
            logger.debug(f"    ✓ {partition_dev} exists")
        
        return loop_device
    except Exception as e:
        raise Exception(f"Failed to re-attach loop device with --partscan: {e}")


def _phase6_format_efi_partition(efi_device: str):
    """Phase 6: Format EFI System Partition"""
    try:
        # Format as VFAT (requires sudo)
        cmd = ['mkfs.vfat', '-F', '32', '-n', 'efi', efi_device]
        _run_cmd_sudo(cmd)
        logger.info(f"✓ Phase 6: EFI partition formatted")
    except Exception as e:
        raise Exception(f"Failed to format EFI partition: {e}")


def _phase7_format_boot_partition(boot_device: str):
    """Phase 7: Format XBOOTLDR Partition"""
    try:
        # Format as ext4 (requires sudo)
        boot_uuid = "5d7e1b2c-3f4a-4c8d-9e22-1a6b7c8d9e33"
        cmd = ['mkfs.ext4', '-U', boot_uuid, '-L', 'xbootldr', boot_device]
        _run_cmd_sudo(cmd)
        logger.info(f"✓ Phase 7: XBOOTLDR partition formatted")
    except Exception as e:
        raise Exception(f"Failed to format XBOOTLDR partition: {e}")


def _phase8_create_luks_volume(luks_partition: str, luks_name: str, luks_passphrase: Optional[str]):
    """Phase 8: Format and open LUKS on partition 3
    
    When luks_passphrase is None (from "NULL" in sourceparams), uses empty passphrase ("\n")
    instead of /dev/null keyfile (cryptsetup has issues with /dev/null)
    
    All cryptsetup operations require sudo for device access.
    """
    try:
        if luks_passphrase:
            # With explicit passphrase (requires sudo)
            cmd = ['sudo', 'cryptsetup', '-q', 'luksFormat', '--type', 'luks2', luks_partition]
            result = subprocess.run(cmd, input=luks_passphrase + '\n' + luks_passphrase + '\n',
                                  universal_newlines=True, capture_output=True, check=False)
            if result.returncode != 0:
                raise Exception(result.stderr)
        else:
            # With empty passphrase for automated unlock (no /dev/null due to cryptsetup issues, requires sudo)
            cmd = ['sudo', 'cryptsetup', '-q', 'luksFormat', '--type', 'luks2', luks_partition]
            result = subprocess.run(cmd, input='\n\n',
                                  universal_newlines=True, capture_output=True, check=False)
            if result.returncode != 0:
                raise Exception(result.stderr)

        # Open LUKS volume (requires sudo)
        if luks_passphrase:
            cmd = ['sudo', 'cryptsetup', 'open', luks_partition, luks_name]
            result = subprocess.run(cmd, input=luks_passphrase + '\n',
                                  universal_newlines=True, capture_output=True, check=False)
            if result.returncode != 0:
                raise Exception(result.stderr)
        else:
            # Open with empty passphrase (requires sudo)
            cmd = ['sudo', 'cryptsetup', 'open', luks_partition, luks_name]
            result = subprocess.run(cmd, input='\n',
                                  universal_newlines=True, capture_output=True, check=False)
            if result.returncode != 0:
                raise Exception(result.stderr)

        logger.info(f"✓ LUKS volume created and opened: /dev/mapper/{luks_name}")
        return f"/dev/mapper/{luks_name}"
    except Exception as e:
        raise Exception(f"Failed to create LUKS volume: {e}")


def _phase9_create_lvm_in_luks(luks_device: str, vg_name: str) -> str:
    """Phase 9: Create LVM physical volume inside LUKS volume"""
    try:
        # Create physical volume (requires sudo)
        cmd = ['lvm', 'pvcreate', '--nolocking', '-ff', '-y', luks_device]
        _run_cmd_sudo(cmd)

        # Create volume group (requires sudo)
        cmd = ['lvm', 'vgcreate', '--nolocking', vg_name, luks_device]
        _run_cmd_sudo(cmd)

        logger.info(f"✓ LVM volume group '{vg_name}' created inside LUKS")
        return vg_name
    except Exception as e:
        raise Exception(f"Failed to create LVM in LUKS: {e}")


def _phase10_create_logical_volumes(vg_name: str, rootfs_lv: LogicalVolumeSpec, additional_lvs: List[LogicalVolumeSpec]):
    """Phase 10: Create logical volumes and format with ext4"""
    try:
        # Create rootfs LV (requires sudo)
        if isinstance(rootfs_lv.size_mb, int):
            size_arg = f"-L {rootfs_lv.size_mb}M"
        else:
            size_arg = "-l 100%FREE"

        cmd = ['lvm', 'lvcreate', '--nolocking', '-n', rootfs_lv.name] + size_arg.split() + [vg_name]
        _run_cmd_sudo(cmd)

        rootfs_device = f"/dev/{vg_name}/{rootfs_lv.name}"
        cmd = ['mkfs.ext4', '-U', rootfs_lv.uuid, '-L', rootfs_lv.name, rootfs_device]
        _run_cmd_sudo(cmd)
        logger.info(f"✓ Rootfs LV created and formatted: {rootfs_device}")

        # Create additional LVs (requires sudo)
        for lv in additional_lvs:
            size_arg = f"-l {lv.size_str}" if '%' in lv.size_str else f"-L {lv.size_mb}M"
            cmd = ['lvm', 'lvcreate', '--nolocking', '-n', lv.name] + size_arg.split() + [vg_name]
            _run_cmd_sudo(cmd)

            lv_device = f"/dev/{vg_name}/{lv.name}"
            cmd = ['mkfs.ext4', '-U', lv.uuid, '-L', lv.name, lv_device]
            _run_cmd_sudo(cmd)
            logger.info(f"✓ Additional LV created and formatted: {lv_device}")

        return rootfs_device
    except Exception as e:
        raise Exception(f"Failed to create logical volumes: {e}")


def _phase11_mount_and_populate_volumes(vg_name: str, rootfs_lv: LogicalVolumeSpec, rootfs_dir: str, mount_base: str) -> Dict:
    """Phase 10: Format and prepare logical volumes (WIC will populate content)"""
    try:
        mounts = {}
        # Just format the rootfs LV, don't mount it
        # WIC will handle populating the rootfs via direct writes to the LV device
        rootfs_device = f"/dev/{vg_name}/{rootfs_lv.name}"
        logger.info(f"✓ Rootfs LV formatted and ready for WIC population: {rootfs_device}")
        return mounts
    except Exception as e:
        raise Exception(f"Failed to prepare volumes: {e}")


def _phase12_cleanup(mounts: Dict, loop_device: str, luks_name: str, vg_name: str):
    """Phase 11: Cleanup - unmount, luks close, detach loop"""
    try:
        # Unmount all filesystems in reverse order
        logger.info("=== Phase 12: Cleanup ===")

        # Unmount rootfs and boot (requires sudo)
        for name, mount_path in reversed(mounts.items()):
            if os.path.ismount(mount_path):
                cmd = ['umount', mount_path]
                _run_cmd_sudo(cmd, check=False)
                logger.info(f"✓ Unmounted {mount_path}")

        # Deactivate LVM (requires sudo)
        cmd = ['lvm', 'vgchange', '--nolocking', '-an', vg_name]
        _run_cmd_sudo(cmd, check=False)
        logger.info(f"✓ LVM VG deactivated")

        # Close LUKS (requires sudo)
        if luks_name:
            cmd = ['cryptsetup', 'close', luks_name]
            _run_cmd_sudo(cmd, check=False)
            logger.info(f"✓ LUKS volume closed")

        # Detach loop device (requires sudo)
        if loop_device:
            cmd = ['losetup', '-d', loop_device]
            _run_cmd_sudo(cmd, check=False)
            logger.info(f"✓ Loop device detached")

        logger.info("✓ Cleanup complete")
    except Exception as e:
        logger.warning(f"Cleanup warning: {e}")


def _phase13_summary(config: DiskConfig, partitions: Dict):
    """Phase 12 (bonus): Output execution summary"""
    logger.info("=== Disk Image Creation Summary ===")
    logger.info(f"Volume Group: {config.vg_name}")
    logger.info(f"LUKS Encryption: {'enabled' if config.luks_enabled else 'disabled'}")
    logger.info(f"Partitions:")
    logger.info(f"  1. EFI System: {partitions.get('efi_size_mb', 512)}MB")
    logger.info(f"  2. XBOOTLDR: {partitions.get('boot_size_mb', 1024)}MB")
    logger.info(f"  3. LUKS + LVM: {partitions.get('crypt_size_mb', 'remaining')}MB")
    logger.info(f"Logical Volumes:")
    logger.info(f"  - {config.rootfs_lv.name}: {config.rootfs_lv.size_str}")
    for lv in config.additional_lvs:
        logger.info(f"  - {lv.name}: {lv.size_str}")


def _generate_shell_script(config, total_size_mb, efi_size_mb, boot_size_mb, crypt_size_mb,
                           vg_name, luks_name, luks_passphrase, luks_enabled, rootfs_name,
                           rootfs_uuid, additional_lvs):
    """Generate a standalone shell script for post-build LVM disk creation
    
    This script can be executed after BitBake completes with proper sudoers configuration:
    sudo ./create-lvm-*.sh <rootfs_dir> <output_wic>
    """
    
    # Build LV creation commands
    lv_create_cmds = []
    lv_mount_cmds = []
    lv_unmount_cmds = []
    
    # Rootfs LV
    lv_create_cmds.append(
        f'lvm lvcreate --nolocking -L {config.rootfs_lv.size_mb}M -n {rootfs_name} {vg_name}'
    )
    lv_create_cmds.append(
        f'mkfs.ext4 -U {config.rootfs_lv.uuid} -L {rootfs_name} /dev/{vg_name}/{rootfs_name}'
    )
    
    # Additional LVs
    for lv in additional_lvs:
        if '%' in lv.size_str:
            size_arg = f'-l {lv.size_str}'
        else:
            size_arg = f'-L {lv.size_mb}M'
        lv_create_cmds.append(f'lvm lvcreate --nolocking {size_arg} -n {lv.name} {vg_name}')
        lv_create_cmds.append(f'mkfs.ext4 -U {lv.uuid} -L {lv.name} /dev/{vg_name}/{lv.name}')
    
    # LUKS passphrase handling
    if luks_passphrase:
        luks_fmt_cmd = f'echo -e "{luks_passphrase}\\n{luks_passphrase}" | cryptsetup -q luksFormat --type luks2'
        luks_open_cmd = f'echo "{luks_passphrase}" | cryptsetup open'
    else:
        luks_fmt_cmd = 'echo -e "\\n" | cryptsetup -q luksFormat --type luks2'
        luks_open_cmd = 'echo "" | cryptsetup open'
    
    script = f'''#!/bin/bash
# LVM + LUKS Disk Image Creation Script
# Generated by lvmrootfs WIC plugin
# 
# Usage: sudo ./create-lvm-{vg_name}.sh <rootfs_dir> <output_wic_path>

set -e

ROOTFS_DIR="${{1:-.}}"
WIC_PATH="${{2:-./disk.wic}}"

if [ ! -d "$ROOTFS_DIR" ]; then
    echo "Error: Rootfs directory not found: $ROOTFS_DIR"
    exit 1
fi

echo "=== LVM Disk Image Creation ==="
echo "VG Name: {vg_name}"
echo "LUKS Enabled: {luks_enabled}"
echo "Total Size: {total_size_mb}MB"
echo "Output: $WIC_PATH"
echo ""

# Cleanup function
cleanup() {{
    echo "Cleaning up..."
    
    # Unmount volumes
    for mp in $(mount | grep "/mnt/lvm-" | awk '{{print $3}}' | tac); do
        echo "Unmounting $mp..."
        umount "$mp" || true
    done
    
    # Deactivate LVM
    echo "Deactivating LVM..."
    lvm vgchange --nolocking -an {vg_name} || true
    
    # Close LUKS
    echo "Closing LUKS..."
    cryptsetup close {luks_name} || true
    
    # Detach loop device
    if [ -n "$LOOP_DEVICE" ]; then
        echo "Detaching loop device..."
        losetup -d "$LOOP_DEVICE" || true
    fi
}}

trap cleanup EXIT

# Create sparse disk image
echo "Phase 1: Creating sparse disk image..."
PV_FILE="/tmp/lvm-pv-$$.img"
dd if=/dev/zero of="$PV_FILE" bs=1M count=0 seek={total_size_mb}
echo "✓ Sparse image created: $PV_FILE"

# Attach loop device (no partscan)
echo "Phase 2: Attaching loop device..."
LOOP_DEVICE=$(losetup --find --show "$PV_FILE")
echo "✓ Loop device: $LOOP_DEVICE"

# Create GPT partition table
echo "Phase 3: Creating GPT partitions..."
sgdisk --zap-all "$LOOP_DEVICE"
sgdisk --new=1:1MiB:+{efi_size_mb}MiB --typecode=1:EF00 --change-name=1:efi \\
       --new=2:0:+{boot_size_mb}MiB --typecode=2:EA00 --change-name=2:xbootldr \\
       --new=3:0:0 --typecode=3:8304 --change-name=3:crypt_lvm \\
       "$LOOP_DEVICE"
echo "✓ Partitions created"

# Detach and re-attach with --partscan
echo "Phase 4: Detaching loop device..."
losetup --detach "$LOOP_DEVICE"

echo "Phase 5: Re-attaching with --partscan..."
LOOP_DEVICE=$(losetup --find --show --partscan "$PV_FILE")
echo "✓ Loop device with partitions: $LOOP_DEVICE"

# Verify partition devices exist
for i in 1 2 3; do
    if [ ! -e "${{LOOP_DEVICE}}p$i" ]; then
        echo "Error: Partition device ${{LOOP_DEVICE}}p$i not created"
        exit 1
    fi
done

# Format EFI partition
echo "Phase 6: Formatting EFI partition..."
mkfs.vfat -F 32 -n efi "${{LOOP_DEVICE}}p1"
echo "✓ EFI partition formatted"

# Format XBOOTLDR partition
echo "Phase 7: Formatting XBOOTLDR partition..."
mkfs.ext4 -U 5d7e1b2c-3f4a-4c8d-9e22-1a6b7c8d9e33 -L xbootldr "${{LOOP_DEVICE}}p2"
echo "✓ XBOOTLDR partition formatted"

# Create LUKS volume
echo "Phase 8: Setting up LUKS encryption..."
{luks_fmt_cmd} "${{LOOP_DEVICE}}p3"
{luks_open_cmd} "${{LOOP_DEVICE}}p3" {luks_name}
echo "✓ LUKS volume opened: /dev/mapper/{luks_name}"

# Create LVM
echo "Phase 9: Creating LVM..."
lvm pvcreate --nolocking -ff -y /dev/mapper/{luks_name}
lvm vgcreate --nolocking {vg_name} /dev/mapper/{luks_name}
echo "✓ LVM VG created: {vg_name}"

# Create logical volumes
echo "Phase 10: Creating logical volumes..."
{chr(10).join(lv_create_cmds)}
echo "✓ Logical volumes created"

# Mount and populate
echo "Phase 11: Mounting and populating volumes..."
mkdir -p /mnt/lvm-$$
mount /dev/{vg_name}/{rootfs_name} /mnt/lvm-$$
rsync -avx "$ROOTFS_DIR/" /mnt/lvm-$$/
umount /mnt/lvm-$$
rmdir /mnt/lvm-$$
echo "✓ Volumes populated with rootfs"

# Mount other volumes if needed
for lv_name in {' '.join([lv.name for lv in additional_lvs])}; do
    if [ ! -z "$lv_name" ]; then
        mkdir -p "/mnt/lvm-$lv_name-$$"
        mount "/dev/{vg_name}/$lv_name" "/mnt/lvm-$lv_name-$$"
        # Populate empty volume
        sync
        umount "/mnt/lvm-$lv_name-$$"
        rmdir "/mnt/lvm-$lv_name-$$"
    fi
done

# Copy sparse image to output location
echo "Phase 12: Finalizing disk image..."
cp "$PV_FILE" "$WIC_PATH"
echo "✓ Disk image finalized: $WIC_PATH"

echo ""
echo "=== Disk Image Creation Complete ==="
echo "Image: $WIC_PATH"
echo "Size: {total_size_mb}MB"
echo "VG: {vg_name}"
echo "Partitions: EFI ({efi_size_mb}MB) + XBOOTLDR ({boot_size_mb}MB) + LUKS+LVM ({crypt_size_mb}MB)"
'''
    
    return script


# ============================================================================
# WIC Plugin Implementation
# ============================================================================

from wic import WicError
from wic.pluginbase import SourcePlugin
from wic.misc import get_bitbake_var


class LvmRootfsPlugin(SourcePlugin):
    """
    WIC source plugin for creating LVM-based disk images with GPT partitions

    Usage in WKS file:
      part /boot/efi --source lvmrootfs --sourceparams="lvm-vg-name=vg0,lvm-rootfs-name=rootlv,lvm-volumes=varfs:100%FREE,luks-passphrase=NULL" --size <partition_size>
    """

    name = 'lvmrootfs'

    @classmethod
    def do_prepare_partition(cls, part, source_params, cr, cr_workdir, oe_builddir, bootimg_dir, kernel_dir, rootfs_dir, native_sysroot):
        """Main entry point for WIC plugin
        
        This plugin generates a standalone shell script for post-build execution
        instead of running privileged operations within BitBake's namespace.
        """
        try:
            logger.info("=== LVM RootFS WIC Plugin (Generate Shell Script Mode) ===")
            logger.info("=== PHASE 1: Parsing WKS Configuration ===")

            # Parse WKS parameters
            vg_name = source_params.get('lvm-vg-name', 'vg0')
            rootfs_name = source_params.get('lvm-rootfs-name', 'rootlv')
            rootfs_uuid = source_params.get('lvm-rootfs-uuid', '')
            luks_name = source_params.get('luks-name', 'cryptroot')
            luks_passphrase = source_params.get('luks-passphrase')
            
            # Support both 'NULL' and 'NONE' for disabling LUKS
            if luks_passphrase in ('NULL', 'NONE'):
                luks_passphrase = None
                luks_enabled = False
            else:
                luks_enabled = True

            volumes_str = source_params.get('lvm-volumes', '')
            volumes_uuids_str = source_params.get('lvm-volumes-uuids', '')
            
            # Parse LV UUIDs
            volume_uuids = {}
            if volumes_uuids_str:
                for uuid_pair in volumes_uuids_str.split(','):
                    vol_name, vol_uuid = uuid_pair.split(':')
                    volume_uuids[vol_name.strip()] = vol_uuid.strip()
            
            additional_lvs = []
            if volumes_str:
                for vol in volumes_str.split(','):
                    name, size = vol.split(':')
                    name = name.strip()
                    size = size.strip()
                    vol_uuid = volume_uuids.get(name, '')
                    lv = LogicalVolumeSpec(name, size)
                    if vol_uuid:
                        lv.uuid = vol_uuid
                    additional_lvs.append(lv)

            # Configuration
            config = DiskConfig(
                vg_name=vg_name,
                luks_name=luks_name,
                luks_passphrase=luks_passphrase,
                rootfs_lv=LogicalVolumeSpec(rootfs_name, 'CALCULATED', uuid=rootfs_uuid),
                additional_lvs=additional_lvs,
                luks_enabled=luks_enabled
            )

            logger.info(f"Configuration validated: VG={vg_name}, LVs={1+len(additional_lvs)}")

            # Calculate sizes
            total_size_mb = int(part.size) + (int(part.extra_space) if part.extra_space else 0)
            efi_size_mb = 512
            boot_size_mb = 1024
            crypt_size_mb = total_size_mb - efi_size_mb - boot_size_mb - 10

            # Calculate rootfs LV size
            rootfs_lv_size_mb = config.calculate_rootfs_lv_size(crypt_size_mb)
            config.rootfs_lv.size_mb = rootfs_lv_size_mb
            config.rootfs_lv.size_str = f"{rootfs_lv_size_mb}M"

            logger.info(f"Total disk size: {total_size_mb}MB")
            logger.info(f"  EFI: {efi_size_mb}MB")
            logger.info(f"  BOOT: {boot_size_mb}MB")
            logger.info(f"  LUKS + LVM: {crypt_size_mb}MB (Rootfs LV: {rootfs_lv_size_mb}MB)")

            # Get directories
            # Write script to /tmp for easy access (avoids BitBake file conflicts)
            script_dir = os.path.join('/tmp', f'wic-lvm-{os.getpid()}')
            os.makedirs(script_dir, exist_ok=True)
            
            script_path = os.path.join(script_dir, f'create-lvm-{config.vg_name}.sh')
            
            logger.info(f"=== PHASE 2: Generating Shell Script ===")
            logger.info(f"Script path: {script_path}")

            # Generate the shell script
            shell_script = _generate_shell_script(
                config=config,
                total_size_mb=total_size_mb,
                efi_size_mb=efi_size_mb,
                boot_size_mb=boot_size_mb,
                crypt_size_mb=crypt_size_mb,
                vg_name=vg_name,
                luks_name=luks_name,
                luks_passphrase=luks_passphrase,
                luks_enabled=luks_enabled,
                rootfs_name=rootfs_name,
                rootfs_uuid=rootfs_uuid,
                additional_lvs=additional_lvs
            )

            # Write script to file
            with open(script_path, 'w') as f:
                f.write(shell_script)
            os.chmod(script_path, 0o755)

            logger.info(f"✓ Shell script generated: {script_path}")
            
            logger.info("")
            logger.info("=== POST-BUILD INSTRUCTIONS ===")
            logger.info(f"To finalize the LVM disk image, run:")
            logger.info(f"  sudo {script_path} <rootfs_dir> <output_wic_path>")
            logger.info(f"")
            logger.info(f"Example:")
            logger.info(f"  sudo {script_path} {rootfs_dir} ./disk.wic")
            logger.info(f"")
            logger.info("This will create the complete disk image with LVM and LUKS encryption.")

        except Exception as e:
            logger.error(f"✗ Failed to generate LVM disk creation script: {e}")
            raise WicError(str(e))
