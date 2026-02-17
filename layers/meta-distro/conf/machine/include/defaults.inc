#
# Machine defaults for demo distribution
# This file contains common machine settings that can be included
# by any machine configuration or in local.conf
#

# Image output formats - WIC for disk image, bmap for efficient copying, OSTree for deployments
IMAGE_FSTYPES = "wic wic.bmap ostree.tar.bz2"

# WIC configuration - LVM layout with LUKS encryption
# Use forcevariable to override meta-updater's sota.bbclass
# Use .wks.in template for variable substitution of partition UUIDs
WKS_FILE:forcevariable = "lvm-simple.wks.in"
WKS_FILE_DEPENDS = "lvm2-native e2fsprogs-native dosfstools-native mtools-native"

# EFI Boot Configuration - systemd-boot
EFI_PROVIDER = "systemd-boot"

# Secure Boot support
MACHINE_FEATURES:append = " secureboot"

# Remove GUI and multimedia features
MACHINE_FEATURES:remove = " x11 wayland opengl vulkan egl directfb sdl gtk qt5 qt6 gnome kde"
MACHINE_FEATURES:remove = " alsa pulseaudio gstreamer bluez"

# Use initramfs with cryptsetup support bundled into the kernel
# Change to "core-image-minimal-initramfs" if LUKS encryption is not needed
INITRAMFS_IMAGE = "core-image-minimal-initramfs-cryptsetup"
INITRAMFS_IMAGE_BUNDLE = "1"
INITRAMFS_MAXSIZE = "262144"

# Kernel configuration for Docker and virtualization
MACHINE_ESSENTIAL_EXTRA_RDEPENDS += "\
    kernel-module-xt-nat \
    kernel-module-iptable-nat \
"

# Secure Boot keys installation
MACHINE_ESSENTIAL_EXTRA_RDEPENDS += "secureboot-keys"

# Do not bundle kernel and initramfs
INITRAMFS_IMAGE_BUNDLE = "0"
