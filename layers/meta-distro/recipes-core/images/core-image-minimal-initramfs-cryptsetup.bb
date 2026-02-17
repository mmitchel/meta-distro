SUMMARY = "Minimal initramfs with LUKS/cryptsetup support"
DESCRIPTION = "Extended core-image-minimal-initramfs with cryptsetup for unlocking encrypted LVM volumes at boot"
LICENSE = "MIT"

# Base on core-image-minimal-initramfs
require recipes-core/images/core-image-minimal-initramfs.bb

# Add cryptsetup for LUKS volume unlocking
IMAGE_INSTALL += "cryptsetup"

# Add LVM tools for volume activation after unlock
IMAGE_INSTALL += "lvm2"

# Ensure systemd is available for cryptsetup integration
IMAGE_INSTALL += "systemd"

# Add crypttab configuration with /dev/null key fallback
IMAGE_INSTALL += "systemd-cryptsetup"

# Add busybox for shell access if unlock fails (recovery)
IMAGE_INSTALL += "busybox"

# Keep initramfs small
IMAGE_FSTYPES = "${INITRAMFS_FSTYPES}"

# Deploy initramfs files from /boot for WIC
inherit deploy

do_deploy() {
    # initramfs image may install files to /boot
    if [ -d "${IMAGE_ROOTFS}/boot" ]; then
        bbnote "Deploying initramfs files from /boot"
        cd ${IMAGE_ROOTFS}/boot
        find . -type f | while read -r file; do
            install -D -m 0644 "$file" "${DEPLOYDIR}/boot/$file"
        done
    fi
}

addtask deploy after do_image_complete before do_build

# Skip license deployment check for images
# License validation is enforced at package level, not image level
# All dependencies have been license-checked during build
do_populate_lic_deploy[noexec] = "1"
