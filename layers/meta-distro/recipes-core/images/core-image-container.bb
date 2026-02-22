SUMMARY = "Container image built from core-image-minimal"
DESCRIPTION = "OCI container image based on core-image-minimal rootfs, \
suitable for running as a container. Container runtime tools are NOT included \
in the image. Containers use the host kernel and run on the host system. \
Only iproute2 and similar tools for checking network interface status are included."

LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfdbcc9c4ca079f46a893f1e2d8e"

# Image recipes don't copy license files to avoid rootfs bloat
# Skip license population task which checks dependencies
COPY_LIC_DIRS = "0"

# Disable license population for image recipes (no embedded license files)
do_populate_lic_deploy[noexec] = "1"

# Require core-image-minimal as base
require recipes-core/images/core-image-minimal.bb

inherit image_types_docker

# Use docker image type for container export
IMAGE_FSTYPES = "docker"

# Set container default CMD to exec /bin/sh as UID 1000 (user)
DOCKER_EXTRA_ARGS = "--change 'USER 1000' --change 'CMD [\"/bin/sh\"]'"

# Container-specific configuration: no real kernel needed
# Containers use the host kernel, not their own
PREFERRED_PROVIDER_virtual/kernel = "linux-dummy"

# Remove all kernel-related and initramfs-related packages from the image
IMAGE_INSTALL:remove = "kernel-image kernel-modules kernel-devicetree initramfs-tools initramfs-framework initramfs-module-initramfs initramfs-module-busybox initramfs-module-udev initramfs-module-systemd initramfs-module-cryptsetup initramfs-module-lvm2 initramfs-module-tpm2 initramfs-module-rootfs initramfs-module-ostree initramfs-module-network initramfs-module-nfsroot initramfs-module-debug initramfs-module-rescue initramfs-module-ssh initramfs-module-dropbear initramfs-module-openssh initramfs-module-setup initramfs-module-setup-live initramfs-module-setup-ostree initramfs-module-setup-luks initramfs-module-setup-lvm initramfs-module-setup-tpm2 initramfs-module-setup-network initramfs-module-setup-nfs initramfs-module-setup-debug initramfs-module-setup-rescue initramfs-module-setup-ssh initramfs-module-setup-dropbear initramfs-module-setup-openssh"

# Add user 'user' with UID 1000 and GID 1000
IMAGE_INSTALL:append = " distro-users"

# Don't include machine-essential packages that pull in kernel
MACHINE_ESSENTIAL_EXTRA_RDEPENDS = ""
MACHINE_ESSENTIAL_EXTRA_RRECOMMENDS = ""
