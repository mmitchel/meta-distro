SUMMARY = "DISTRO OSTree image with atomic update support"
DESCRIPTION = "Core image for atomic updates using OSTree from meta-updater. \
Uses single partition with multiple deployments (rollback support)."

LICENSE = "MIT"

require recipes-core/images/core-image-minimal.bb

# Essential packages for OSTree atomic updates
IMAGE_INSTALL:append = " \
    ostree \
    ostree-switchroot \
    systemd \
    systemd-analyze \
    lvm2 \
    e2fsprogs \
"

# Networking for OSTree remote updates
IMAGE_INSTALL:append = " \
    iproute2 \
    iputils \
"

# Docker support
IMAGE_INSTALL:append = " \
    docker-moby \
    docker-compose \
"

# Debugging and utilities
IMAGE_INSTALL:append = " \
    vim \
    less \
    htop \
"

# Secure Boot keys
IMAGE_INSTALL:append = " secureboot-keys"

# Factory /var support - populate factory directory
populate_factory_var() {
    install -d ${IMAGE_ROOTFS}${datadir}/factory/var

    if [ -d "${IMAGE_ROOTFS}/var" ]; then
        cp -a ${IMAGE_ROOTFS}/var/* ${IMAGE_ROOTFS}${datadir}/factory/var/ 2>/dev/null || true
        bbnote "Factory /var populated for OSTree deployments"
    fi
}

ROOTFS_POSTPROCESS_COMMAND += "populate_factory_var; "

# Note: SSH server enabled via defaults.inc EXTRA_IMAGE_FEATURES

# Note: OSTree maintains multiple deployments on a single partition
# Default retention: 2 deployments (current + previous for rollback)
# Bootloader will show available deployments at boot
