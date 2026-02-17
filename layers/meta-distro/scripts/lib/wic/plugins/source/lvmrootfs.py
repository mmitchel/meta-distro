#!/usr/bin/env python3
#
# Copyright (c) 2024 Demo Project
#
# SPDX-License-Identifier: MIT
#

"""
Custom WIC plugin for creating LVM-based images with VFAT boot partition
Uses native Python subprocess to call system binaries directly
"""

import logging
import os
import re
import shutil
import subprocess
import tempfile
import uuid

from wic import WicError
from wic.pluginbase import SourcePlugin
from wic.misc import get_bitbake_var

logger = logging.getLogger('wic')

# Map of system binary paths
TOOLS = {
    'udisksctl': '/usr/bin/udisksctl',
    'lvm': '/sbin/lvm',
    'mkfs.ext4': '/sbin/mkfs.ext4',
    'mount': '/bin/mount',
    'umount': '/bin/umount',
    'cryptsetup': '/sbin/cryptsetup',
    'dd': '/bin/dd',
    'tar': '/bin/tar',
    'blkid': '/sbin/blkid',
}


def _run_cmd(cmd, check=True, capture=False):
    """
    Run a command using subprocess directly

    Args:
        cmd: Command string or list
        check: Whether to check return code
        capture: Whether to capture and return output

    Returns:
        stdout string if capture=True, else None
    """
    if isinstance(cmd, str):
        cmd = cmd.split()

    try:
        logger.debug(f"Executing: {' '.join(cmd)}")
        result = subprocess.run(
            cmd,
            check=False,
            stdout=subprocess.PIPE if capture else None,
            stderr=subprocess.PIPE,
            universal_newlines=True
        )

        if result.returncode != 0 and check:
            raise WicError(
                f"Command failed with code {result.returncode}: {' '.join(cmd)}\n"
                f"stderr: {result.stderr}"
            )

        if capture:
            return result.stdout.strip()
        return None
    except Exception as e:
        if check:
            raise WicError(f"Failed to execute command: {e}")
        logger.warning(f"Command warning: {e}")
        return None


def _tool_path(name):
    """Get path for a tool, with fallback to search PATH"""
    if name in TOOLS:
        path = TOOLS[name]
        if os.path.exists(path):
            return path

    # Fallback: search in PATH
    for directory in os.environ.get('PATH', '/bin:/sbin:/usr/bin:/usr/sbin').split(':'):
        path = os.path.join(directory, name)
        if os.path.exists(path):
            return path

    raise WicError(f"Tool '{name}' not found in TOOLS map or PATH")

# Static UUID mapping for known logical volume names
# These UUIDs are predictable and consistent across builds
LV_UUID_MAP = {
    'rootlv': '44479540-f297-41b2-9af7-d131d5f0458a',
    'varfs': '773b7d1b-1cc8-4a8f-8e9c-3c4d4f7f7cbb',
    'datafs': 'a4e8e5c8-6e8f-4d2a-8b1f-9c8d5e6f7a8b',
    'logfs': 'b5f9f6d9-7f9g-5e3b-9c2g-ad9e6f8g8b9c',
}

class LvmRootfsPlugin(SourcePlugin):
    """
    Create a partition with LVM containing rootfs and additional volumes

    This plugin creates an LVM physical volume that contains:
    - A rootfs logical volume
    - Optional additional logical volumes as specified

    Uses native Python subprocess to call system binaries directly

    Usage in WKS file:
        part / --source lvmrootfs --fstype=ext4 --label rootfs --size 4096M
                --extra-space=1024M --lvm-vg-name=vg0 --lvm-volumes="datafs:2G,logfs:1G"
                --lvm-mountpoints="datafs:/mnt/data,logfs:/var/log"
                --luks-passphrase="mysecret" --luks-name="cryptlvm"
    """

    name = 'lvmrootfs'

    @classmethod
    def do_configure_partition(cls, part, source_params, cr, cr_workdir,
                               oe_builddir, bootimg_dir, kernel_dir,
                               native_sysroot):
        """
        Called before do_prepare_partition(), sets up LVM configuration
        """
        if not part.size:
            raise WicError("partition size is required for LVM rootfs")

        # Get LVM configuration from source parameters
        part.lvm_vg_name = source_params.get('lvm-vg-name', 'vg0')
        part.lvm_rootfs_name = source_params.get('lvm-rootfs-name', 'rootlv')
        part.lvm_volumes = source_params.get('lvm-volumes', '')
        part.lvm_mountpoints = source_params.get('lvm-mountpoints', '')

        # Get LUKS encryption configuration
        part.luks_passphrase = source_params.get('luks-passphrase', '')
        part.luks_name = source_params.get('luks-name', 'cryptlvm')

        logger.debug(f"LVM VG name: {part.lvm_vg_name}")
        logger.debug(f"LVM rootfs LV name: {part.lvm_rootfs_name}")
        logger.debug(f"Additional LVM volumes: {part.lvm_volumes}")
        logger.debug(f"LVM mount points: {part.lvm_mountpoints}")
        logger.debug(f"LUKS encryption: {'enabled' if part.luks_passphrase else 'disabled'}")
        if part.luks_passphrase:
            logger.debug(f"LUKS device name: {part.luks_name}")

    @classmethod
    def do_prepare_partition(cls, part, source_params, cr, cr_workdir,
                            oe_builddir, bootimg_dir, kernel_dir,
                            native_sysroot):
        """
        Called to do the actual content population for a partition
        Creates LVM physical volume with logical volumes using native subprocess
        """
        rootfs_dir = get_bitbake_var("IMAGE_ROOTFS")
        if not rootfs_dir:
            raise WicError("Couldn't find IMAGE_ROOTFS")

        logger.info("Using native subprocess to call system binaries for LVM structure")

        # Create temporary directory for LVM operations
        lvm_workdir = tempfile.mkdtemp(dir=cr_workdir, prefix='lvm-')

        # Calculate sizes
        rootfs_size = part.size
        if part.extra_space:
            rootfs_size += part.extra_space

        # Create sparse file for LVM physical volume
        pv_file = os.path.join(lvm_workdir, 'lvm-pv.img')
        dd_cmd = [_tool_path('dd'), f'if=/dev/zero', f'of={pv_file}', 'bs=1M', f'count=0', f'seek={int(rootfs_size)}']
        _run_cmd(dd_cmd)

        # Calculate rootfs logical volume size
        additional_space = 0
        if part.lvm_volumes:
            for vol_spec in part.lvm_volumes.split(','):
                if ':' in vol_spec:
                    name, size = vol_spec.split(':', 1)
                    size_mb = cls._parse_size_to_mb(size.strip())
                    additional_space += size_mb

        rootfs_lv_size = int(rootfs_size) - additional_space - 4  # Reserve 4MB for LVM metadata

        if rootfs_lv_size <= 0:
            raise WicError("LVM rootfs size is non-positive after reserving additional volumes")

        loop_device = None
        luks_opened = False
        rootfs_mount = None
        try:
            # Attach loop device via udisksctl
            loop_device = cls._loop_setup(pv_file)
            logger.info(f"Loop device attached: {loop_device}")
            luks_device = loop_device

            # Setup LUKS encryption if passphrase provided
            if part.luks_passphrase:
                logger.info(f"Setting up LUKS encryption for LVM (device: {part.luks_name})")
                luks_device = cls._luks_format_and_open(
                    loop_device,
                    part.luks_name,
                    part.luks_passphrase,
                    lvm_workdir
                )
                luks_opened = True
                logger.info(f"LUKS container created: {luks_device}")

            # Create LVM PV/VG
            cls._lvm_create_vg(luks_device, part.lvm_vg_name)
            logger.info(f"LVM VG '{part.lvm_vg_name}' created")

            # Create rootfs logical volume
            rootfs_dev = cls._lvm_create_lv(
                part.lvm_vg_name,
                part.lvm_rootfs_name,
                rootfs_lv_size
            )
            logger.info(f"Created rootfs LV: {rootfs_dev}")

            # Format rootfs with deterministic filesystem UUID
            rootfs_uuid = cls._get_lv_uuid(part.lvm_rootfs_name)
            cls._format_partition(
                rootfs_dev,
                rootfs_uuid,
                part.label or 'rootfs'
            )
            logger.info(f"Formatted rootfs LV with UUID: {rootfs_uuid}")

            # Mount rootfs and populate
            rootfs_mount = cls._mount_partition(rootfs_dev, lvm_workdir)
            logger.info(f"Rootfs mounted at: {rootfs_mount}")

            logger.info("Copying rootfs content via tar")
            tar_file = os.path.join(lvm_workdir, 'rootfs.tar')
            tar_cmd = [_tool_path('tar'), '-cf', tar_file, '-C', rootfs_dir, '.']
            _run_cmd(tar_cmd)
            tar_extract = [_tool_path('tar'), '-xf', tar_file, '-C', rootfs_mount]
            _run_cmd(tar_extract)
            if os.path.exists(tar_file):
                os.remove(tar_file)

            # Update fstab if mount points specified
            if part.lvm_mountpoints:
                cls._update_fstab(rootfs_mount, part.lvm_vg_name, part.lvm_mountpoints)

            # Unmount rootfs before creating additional volumes
            cls._unmount_partition(rootfs_dev)
            rootfs_mount = None

            # Create additional logical volumes if specified
            if part.lvm_volumes:
                for vol_spec in part.lvm_volumes.split(','):
                    if ':' in vol_spec:
                        name, size = vol_spec.split(':', 1)
                        name = name.strip()
                        size = size.strip()
                        size_mb = cls._parse_size_to_mb(size)

                        logger.info(f"Creating additional LV: {name} ({size})")
                        vol_dev = cls._lvm_create_lv(
                            part.lvm_vg_name,
                            name,
                            size_mb
                        )

                        vol_uuid = cls._get_lv_uuid(name)
                        cls._format_partition(vol_dev, vol_uuid, name)
                        logger.info(f"Formatted LV '{name}' with UUID: {vol_uuid}")

            # Deactivate VG and close LUKS
            cls._lvm_deactivate_vg(part.lvm_vg_name)
            if luks_opened:
                cls._luks_close(part.luks_name)
                luks_opened = False

            # Detach loop device
            if loop_device:
                cls._loop_teardown(loop_device)
                loop_device = None

        except Exception as e:
            raise WicError(f"Failed to create LVM structure: {e}")
        finally:
            # Best-effort cleanup
            if rootfs_mount:
                try:
                    cls._unmount_partition(rootfs_dev)
                except Exception:
                    pass
            try:
                cls._lvm_deactivate_vg(part.lvm_vg_name)
            except Exception:
                pass
            if luks_opened:
                try:
                    cls._luks_close(part.luks_name)
                except Exception:
                    pass
            if loop_device:
                try:
                    cls._loop_teardown(loop_device)
                except Exception:
                    pass


        # Set the partition source file to the LVM PV image
        part.source_file = pv_file
        part.size = rootfs_size

    @classmethod
    def _generate_fstab_entries(cls, vg_name, mountpoints_str):
        """
        Generate fstab entries for LVM volumes

        Args:
            vg_name: Volume group name
            mountpoints_str: Comma-separated "lvname:mountpoint" pairs

        Returns:
            String containing fstab entries or empty string
        """
        entries = []

        for mp_spec in mountpoints_str.split(','):
            if ':' in mp_spec:
                lv_name, mountpoint = mp_spec.split(':', 1)
                lv_name = lv_name.strip()
                mountpoint = mountpoint.strip()

                if not mountpoint.startswith('/'):
                    logger.warning(f"Mount point '{mountpoint}' for LV '{lv_name}' is not absolute, skipping")
                    continue

                # Create fstab entry
                device = f"/dev/{vg_name}/{lv_name}"
                entry = f"{device}\t{mountpoint}\text4\tdefaults\t0\t2"
                entries.append(entry)

                logger.info(f"Generated fstab entry: {lv_name} -> {mountpoint}")

        return '\n'.join(entries) if entries else ""

    @classmethod
    def _update_fstab(cls, rootfs_mount, vg_name, mountpoints_str):
        """
        Update /etc/fstab in the rootfs with LVM volume mount points

        Args:
            rootfs_mount: Path to mounted rootfs
            vg_name: Volume group name
            mountpoints_str: Comma-separated "lvname:mountpoint" pairs
        """
        fstab_path = os.path.join(rootfs_mount, 'etc', 'fstab')

        # Parse mount points
        mount_entries = []
        for mp_spec in mountpoints_str.split(','):
            if ':' in mp_spec:
                lv_name, mountpoint = mp_spec.split(':', 1)
                lv_name = lv_name.strip()
                mountpoint = mountpoint.strip()

                if not mountpoint.startswith('/'):
                    logger.warning(f"Mount point '{mountpoint}' for LV '{lv_name}' is not absolute, skipping")
                    continue

                # Create fstab entry
                device = f"/dev/{vg_name}/{lv_name}"
                entry = f"{device}\t{mountpoint}\text4\tdefaults\t0\t2\n"
                mount_entries.append((mountpoint, entry))

                logger.info(f"Adding fstab entry: {lv_name} -> {mountpoint}")

        if not mount_entries:
            logger.debug("No valid mount points to add to fstab")
            return

        # Read existing fstab or create new one
        fstab_content = []
        if os.path.exists(fstab_path):
            with open(fstab_path, 'r') as f:
                fstab_content = f.readlines()

        # Add header comment if adding entries
        if mount_entries and not any('LVM volumes' in line for line in fstab_content):
            fstab_content.append('\n# LVM volumes\n')

        # Add mount entries
        for mountpoint, entry in mount_entries:
            # Check if mount point already exists
            if not any(mountpoint in line and not line.strip().startswith('#') for line in fstab_content):
                fstab_content.append(entry)
            else:
                logger.warning(f"Mount point '{mountpoint}' already exists in fstab, skipping")

        # Write updated fstab
        os.makedirs(os.path.dirname(fstab_path), exist_ok=True)
        with open(fstab_path, 'w') as f:
            f.writelines(fstab_content)

        logger.info(f"Updated {fstab_path} with {len(mount_entries)} LVM mount points")

    @classmethod
    def _get_lv_uuid(cls, lv_name):
        """
        Get UUID for a logical volume by name.
        Returns static UUID for known volume names, random UUID for unknown names.

        Args:
            lv_name: Name of the logical volume

        Returns:
            UUID string
        """
        if lv_name in LV_UUID_MAP:
            lv_uuid = LV_UUID_MAP[lv_name]
            logger.debug(f"Using static UUID for LV '{lv_name}': {lv_uuid}")
            return lv_uuid
        else:
            lv_uuid = str(uuid.uuid4())
            logger.debug(f"Generated random UUID for LV '{lv_name}': {lv_uuid}")
            return lv_uuid

    @staticmethod
    def _parse_size_to_mb(size_str):
        """
        Parse size string (e.g., "2G", "512M", "1024K") to megabytes
        """
        size_str = size_str.upper().strip()
        if size_str.endswith('G'):
            return int(float(size_str[:-1]) * 1024)
        elif size_str.endswith('M'):
            return int(float(size_str[:-1]))
        elif size_str.endswith('K'):
            return int(float(size_str[:-1]) / 1024)
        else:
            # Assume MB if no unit
            return int(size_str)

    # ========== Native subprocess Helper Methods ==========

    @staticmethod
    def _loop_setup(pv_file):
        """
        Setup loop device using udisksctl loop-setup

        Args:
            pv_file: path to the sparse image file

        Returns:
            loop device path (e.g., /dev/loop0)
        """
        try:
            logger.debug(f"Setting up loop device for {pv_file}")
            cmd = [_tool_path('udisksctl'), 'loop-setup', '--file', pv_file, '--no-user-interaction']
            output = _run_cmd(cmd, capture=True)
            match = re.search(r"(/dev/loop\d+)", output or "")
            if not match:
                raise WicError(f"Unexpected udisksctl output: {output}")
            loop_dev = match.group(1)
            logger.info(f"Loop device setup: {loop_dev}")
            return loop_dev
        except Exception as e:
            raise WicError(f"Failed to setup loop device: {e}")

    @staticmethod
    def _luks_format_and_open(device, mapper_name, passphrase, workdir):
        """
        Format device with LUKS and open it using cryptsetup

        Args:
            device: block device path
            mapper_name: name for the mapped device
            passphrase: encryption passphrase (or "NULL" for /dev/null key)
            workdir: working directory for key files

        Returns:
            path to opened LUKS device
        """
        try:
            logger.debug(f"Formatting LUKS on {device}")

            if passphrase.upper() == "NULL":
                logger.info("Using /dev/null as LUKS key")
                cmd = [_tool_path('cryptsetup'), 'luksFormat', '--type', 'luks2', '--batch-mode',
                       '--key-file', '/dev/null', device]
                _run_cmd(cmd)
                cmd = [_tool_path('cryptsetup'), 'open', '--key-file', '/dev/null', device, mapper_name]
                _run_cmd(cmd)
            else:
                # Write passphrase to file
                key_file = os.path.join(workdir, 'luks.key')
                with open(key_file, 'w') as f:
                    f.write(passphrase)
                os.chmod(key_file, 0o600)

                cmd = [_tool_path('cryptsetup'), 'luksFormat', '--type', 'luks2', '--batch-mode',
                       '--key-file', key_file, device]
                _run_cmd(cmd)
                cmd = [_tool_path('cryptsetup'), 'open', '--key-file', key_file, device, mapper_name]
                _run_cmd(cmd)

            return f"/dev/mapper/{mapper_name}"
        except Exception as e:
            raise WicError(f"Failed to format/open LUKS device: {e}")

    @staticmethod
    def _lvm_create_vg(pv_device, vg_name):
        """
        Create LVM volume group using lvm pvcreate/lvm vgcreate

        Args:
            pv_device: physical volume device path
            vg_name: volume group name
        """
        try:
            logger.debug(f"Creating LVM PV on {pv_device}")
            cmd = [_tool_path('lvm'), 'pvcreate', '-ff', '-y', pv_device]
            _run_cmd(cmd)

            logger.debug(f"Creating LVM VG {vg_name}")
            cmd = [_tool_path('lvm'), 'vgcreate', vg_name, pv_device]
            _run_cmd(cmd)

            cmd = [_tool_path('lvm'), 'vgchange', '-ay', vg_name]
            _run_cmd(cmd)
        except Exception as e:
            raise WicError(f"Failed to create LVM VG: {e}")

    @staticmethod
    def _lvm_create_lv(vg_name, lv_name, size_mb):
        """
        Create logical volume using lvm lvcreate

        Args:
            vg_name: volume group name
            lv_name: logical volume name
            size_mb: size in megabytes

        Returns:
            path to the logical volume device
        """
        try:
            logger.debug(f"Creating LV {lv_name} in VG {vg_name} ({size_mb}M)")
            cmd = [_tool_path('lvm'), 'lvcreate', '-L', f'{size_mb}M', '-n', lv_name, vg_name]
            _run_cmd(cmd)
            return f"/dev/{vg_name}/{lv_name}"
        except Exception as e:
            raise WicError(f"Failed to create LVM LV: {e}")

    @staticmethod
    def _format_partition(device, uuid, label):
        """
        Format partition with ext4 using mkfs.ext4

        Args:
            device: block device path
            uuid: filesystem UUID
            label: filesystem label
        """
        try:
            logger.debug(f"Formatting {device} with ext4 UUID={uuid} LABEL={label}")
            cmd = [_tool_path('mkfs.ext4'), '-U', uuid, '-L', label, device]
            _run_cmd(cmd)
        except Exception as e:
            raise WicError(f"Failed to format partition: {e}")

    @staticmethod
    def _mount_partition(device, workdir):
        """
        Mount partition using native mount

        Args:
            device: block device path
            workdir: working directory for mount point

        Returns:
            mount point path
        """
        try:
            logger.debug(f"Mounting {device}")
            mount_point = tempfile.mkdtemp(dir=workdir, prefix='rootfs-mnt-')
            cmd = [_tool_path('mount'), '-t', 'ext4', device, mount_point]
            _run_cmd(cmd)
            logger.info(f"Mounted at: {mount_point}")
            return mount_point
        except Exception as e:
            raise WicError(f"Failed to mount partition: {e}")

    @staticmethod
    def _unmount_partition(device):
        """
        Unmount partition using native umount

        Args:
            device: block device path
        """
        try:
            logger.debug(f"Unmounting {device}")
            cmd = [_tool_path('umount'), device]
            _run_cmd(cmd)
            logger.info(f"Unmounted: {device}")
        except Exception as e:
            logger.warning(f"Failed to unmount {device}: {e}")

    @staticmethod
    def _luks_close(mapper_name):
        """
        Close LUKS device using cryptsetup

        Args:
            mapper_name: mapper device name
        """
        try:
            logger.debug(f"Closing LUKS device {mapper_name}")
            cmd = [_tool_path('cryptsetup'), 'close', mapper_name]
            _run_cmd(cmd)
            logger.info(f"Closed LUKS device: {mapper_name}")
        except Exception as e:
            logger.warning(f"Failed to close LUKS device: {e}")

    @staticmethod
    def _lvm_deactivate_vg(vg_name):
        """
        Deactivate LVM volume group using lvm vgchange

        Args:
            vg_name: volume group name
        """
        try:
            logger.debug(f"Deactivating LVM VG {vg_name}")
            cmd = [_tool_path('lvm'), 'vgchange', '-an', vg_name]
            _run_cmd(cmd)
        except Exception as e:
            logger.warning(f"Failed to deactivate VG: {e}")

    @staticmethod
    def _loop_teardown(loop_device):
        """
        Detach loop device using udisksctl loop-delete

        Args:
            loop_device: loop device path
        """
        try:
            logger.debug(f"Tearing down loop device {loop_device}")
            cmd = [_tool_path('udisksctl'), 'loop-delete', '-b', loop_device, '--no-user-interaction']
            _run_cmd(cmd)
            logger.info(f"Loop device detached: {loop_device}")
        except Exception as e:
            logger.warning(f"Failed to detach loop device: {e}")
