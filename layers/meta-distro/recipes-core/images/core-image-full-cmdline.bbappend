# Core image customizations common to all meta-distro images
require recipes-core/images/core-image-distro.inc

# Remove .rootfs suffix from image names
IMAGE_NAME = "${IMAGE_BASENAME}-${MACHINE}"
