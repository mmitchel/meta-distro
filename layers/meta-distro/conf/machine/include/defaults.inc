#
# Machine defaults for DISTRO distribution
# This file contains common machine settings that can be included
# by any machine configuration or in local.conf
#

# Image output formats - WIC for disk image, bmap for efficient copying, OSTree for deployments
IMAGE_FSTYPES = "wic wic.bmap ostree.tar.bz2"

# WIC configuration - LVM layout with LUKS encryption
# Use forcevariable to override meta-updater's sota.bbclass
# Use .wks.in template for variable substitution of partition UUIDs
WKS_FILE:forcevariable = "lvm-boot-encrypted.wks.in"
WKS_FILE_DEPENDS = "lvm2-native e2fsprogs-native dosfstools-native mtools-native"

# EFI Boot Configuration - u-boot (MANDATORY for all device types)
EFI_PROVIDER = "u-boot"

# Secure Boot support
MACHINE_FEATURES:append = " secureboot"

# Remove GUI and multimedia features
MACHINE_FEATURES:remove = " x11 wayland opengl vulkan egl directfb sdl gtk qt5 qt6 gnome kde"
MACHINE_FEATURES:remove = " alsa pulseaudio gstreamer bluez"

# Use initramfs with cryptsetup, lvm2, tpm2-tools, and busybox support (NO systemd - MANDATORY)
# LUKS encryption is MANDATORY - INITRAMFS unlocks LUKS before LVM activation
INITRAMFS_IMAGE = "core-image-minimal-initramfs-cryptsetup"
INITRAMFS_IMAGE_BUNDLE = "0"
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
