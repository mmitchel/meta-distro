# DISTRO = "distro"
DISTRO_NAME = "DISTRO Distribution"
DISTRO_VERSION = "1.0"
DISTRO_CODENAME = "scarthgap"

MAINTAINER = "DISTRO Project <distro@example.com>"

inherit sota

# Inherit classes globally
INHERIT += "source-date-epoch"
INHERIT += "rm_work"

# Distribution features - systemd only, no sysvinit
DISTRO_FEATURES:append = " systemd usrmerge"
DISTRO_FEATURES_NATIVE:append = " systemd usrmerge"
DISTRO_FEATURES_BACKFILL_CONSIDERED += "sysvinit"
DISTRO_FEATURES:remove = "sysvinit"

# Init manager - systemd only
# VIRTUAL-RUNTIME_base-utils = "busybox"
VIRTUAL-RUNTIME_dev_manager = "systemd"
VIRTUAL-RUNTIME_init_manager = "systemd"
VIRTUAL-RUNTIME_initscripts = ""
VIRTUAL-RUNTIME_login_manager = "shadow-base"
VIRTUAL-RUNTIME_syslog = "systemd"

# Remove GUI and multimedia features
DISTRO_FEATURES:remove = " x11 wayland opengl vulkan egl directfb sdl gtk qt5 qt6 gnome kde"
DISTRO_FEATURES:remove = " alsa pulseaudio gstreamer bluez"

# Remove ptest support
DISTRO_FEATURES:remove = " ptest"
EXTRA_IMAGE_FEATURES:remove = " ptest"

# OSTree and OTA update support (single partition with multiple deployments)
DISTRO_FEATURES:append = " sota"

# Network manager
PREFERRED_RPROVIDER_network-configuration = "networkd-dhcp-conf"

# Container runtime providers
PREFERRED_RPROVIDER_util-linux-nsenter-native = "util-linux-native"

# Virtualization and Docker support
DISTRO_FEATURES:append = " virtualization"

# Seccomp support for container builds
DISTRO_FEATURES:append = " seccomp"
DISTRO_FEATURES_NATIVE:append = " seccomp"

# Make host docker available for container image creation
HOSTTOOLS += "docker"

# Partition GUID and UUID Configuration (Discoverable Partitions + Static Filesystem UUIDs)
# These values are MANDATORY and must not be changed
# Reference: .mandatory-requirements.md

# GPT Partition Type GUIDs
PARTTYPE_ESP = "c12a7328-f81f-11d2-ba4b-00a0c93ec93b"
PARTTYPE_XBOOTLDR = "bc13c2ff-59e6-4262-a352-b275fd6f7172"
PARTTYPE_ROOT = "4f68bce3-e8cd-4db1-96e7-fbcaf984b709"

# Static Filesystem UUIDs (Preassigned)
FSUUID_ESP = "3a4f2c1e-9b8d-4c3f-8e1a-7d2b9f4c6a11"
FSUUID_XBOOTLDR = "5d7e1b2c-3f4a-4c8d-9e22-1a6b7c8d9e33"
FSUUID_ROOT = "8e8c2c0a-4f0e-4b8a-9e1a-2b6d9f3e7c11"
FSUUID_VAR = "d3b4a1f2-6c9e-4f8b-9c22-0f7b8e1a4d55"

# OSTree configuration for atomic updates
OSTREE_OSNAME ?= "distro"
OSTREE_BRANCHNAME ?= "${DISTRO_VERSION}"
OSTREE_REPO ?= "${DEPLOY_DIR_IMAGE}/ostree_repo"

# Explicitly disable aktualizr and garage from meta-updater (MANDATORY REQUIREMENT)
# This project uses OSTree for atomic updates, NOT aktualizr as the OTA client
# Remove all aktualizr* and garage* packages from images
SOTA_CLIENT_PROV = ""
IMAGE_INSTALL:remove:sota = "aktualizr aktualizr-info"

# Bootloader configuration for OSTree - u-boot is MANDATORY for all device types
OSTREE_BOOTLOADER ?= "u-boot"
OSTREE_DEPLOY_DEVICETREE ?= "0"

# Package management
PACKAGE_CLASSES ?= "package_rpm"

# Image features - add SSH server to all images
EXTRA_IMAGE_FEATURES:append = " ssh-server-openssh"

# SDK configuration
SDK_VENDOR = "-distrosdk"
SDK_VERSION = "${@d.getVar('DISTRO_VERSION').replace('snapshot-${METADATA_REVISION}', 'snapshot')}"
SDK_NAME = "${DISTRO}-${TCLIBC}-${SDKMACHINE}-${IMAGE_BASENAME}-${TUNE_PKGARCH}-${MACHINE}"
SDKPATHINSTALL = "/opt/${DISTRO}/${SDK_VERSION}"

# Target OS
TARGET_VENDOR = "-distro"

# Host configured tools for use during wic image creation
# Note: losetup and other standard tools are available in PATH and don't need HOSTTOOLS declaration
HOSTTOOLS:append = " sudo losetup lvm cryptsetup mount umount "

ROOT_HOME = "/root"
