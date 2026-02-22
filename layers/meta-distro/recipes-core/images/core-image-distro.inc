# Common core-image customizations for meta-distro
#
# This include file contains shared settings and functions used by all
# core-image* bbappends in the meta-distro layer, including:
# - core-image-minimal.bbappend
# - core-image-full-cmdline.bbappend
# - demo-image-ostree.bbappend
#
# Purpose: Centralize OSTree, security, and rootfs management settings
# to avoid duplication and ensure consistency across image variants.

# OSTree Configuration
# Suppress OSTree warnings for directories on separate partitions/volumes
# /var is mounted from LVM, /home is in /var/roothome
OSTREE_BOOT_DEVICE ?= "LABEL=boot"

# Suppress warnings from ostree_rmdir_helper for /var, /home (expected with separate volumes)
OSTREE_RMDIR_HELPER_MSGTYPE = "bbnote"

# Remove warning about systemd does not support ROOT_HOME at /home/root, set ROOT_HOME=/root
populate_root_home_softlink () {
    if [[  "${ROOT_HOME}" != "/home/root" ]] ; then
        mkdir =p ${IMAGE_ROOTFS}/home/root
        ln -sfr ${IMAGE_ROOTFS}/home/root ${IMAGE_ROOTFS}${ROOT_HOME}
    fi
}
ROOTFS_PREPROCESS_COMMAND += "populate_root_home_softlink;"

# Remove empty_var_volatile since /var is on separate LVM volume
ROOTFS_POSTPROCESS_COMMAND:remove = "empty_var_volatile"

# Factory /var Management
# Populate ${datadir}/factory/var with contents of /var
# This allows systemd-tmpfiles to restore /var if empty (e.g., on separate LVM volume)
populate_factory_var() {
    # Create factory directory structure
    install -d ${IMAGE_ROOTFS}${datadir}/factory/var

    # Copy all /var contents to factory location
    if [ -d "${IMAGE_ROOTFS}/var" ]; then
        cp -a ${IMAGE_ROOTFS}/var/* ${IMAGE_ROOTFS}${datadir}/factory/var/ 2>/dev/null || true

        bbnote "Factory /var populated with initial contents"
        bbnote "Directory structure:"
        ls -la ${IMAGE_ROOTFS}${datadir}/factory/var/ || true
    else
        bbwarn "No /var directory found in rootfs"
    fi
}

# Remove /var from rootfs for OSTree (it's mounted separately at runtime)
remove_var_for_ostree() {
    if [ -d "${IMAGE_ROOTFS}/var" ]; then
        bbnote "Removing /var from OSTree rootfs (factory copy preserved in /usr/share/factory/var)"
        rm -rf ${IMAGE_ROOTFS}/var/*
        # Keep empty /var directory for mount point
    fi
}

# Security Settings
# Lock root password during rootfs creation
lock_root_account() {
    # Lock the root account password for console/serial login
    # Root can still login via SSH using authorized keys
    # This prevents password-based authentication for root
    sed -i 's/^root:[^:]*:/root:!:/' ${IMAGE_ROOTFS}/etc/shadow

    bbnote "Root account password locked - SSH key authentication only"
    bbnote "Users can login on console/serial with passwords"
}

# Run all customizations after rootfs is populated but before it's packaged
ROOTFS_POSTPROCESS_COMMAND += "populate_factory_var; remove_var_for_ostree; lock_root_account; "

# Ensure systemd-tmpfiles is available for factory /var restoration
IMAGE_INSTALL:append = " systemd"

# License Deployment
# Skip license deployment check for images
# License validation is enforced at package level, not image level
# All dependencies have been license-checked during build
do_populate_lic_deploy[noexec] = "1"
