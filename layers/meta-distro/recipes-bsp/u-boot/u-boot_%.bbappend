# U-Boot configuration for DISTRO Project
# Copyright (c) 2026 DISTRO Project
# SPDX-License-Identifier: MIT
#
# This bbappend adds EFI support to U-Boot
#
# Features:
# - EFI configuration
# - Deployment as BOOTx64.EFI (x86-64) or BOOTAA64.EFI (ARM64)

FILESEXTRAPATHS:prepend := "${THISDIR}/files:"

# Add EFI Secure Boot configuration fragment
SRC_URI += "file://efi-secure-boot.cfg"

# U-Boot needs to be built as EFI application for x86-64
UBOOT_BINARY:qemux86-64 = "u-boot.efi"

# For ARM64/aarch64
UBOOT_BINARY:qemuarm64 = "u-boot.efi"

# Enable building u-boot tools for the target
PROVIDES += "u-boot-tools"

# Ensure EFI support is enabled
EXTRA_OEMAKE:append = " EFI_LOADER=y"

# Add dependencies for Secure Boot key integration
DEPENDS += "openssl-native"

# ============================================================================
# Deploy u-boot.efi as BOOTx64.EFI (x86-64)
# ============================================================================

do_deploy:append:qemux86-64() {
    # Install u-boot.efi as BOOTx64.EFI for UEFI boot
    if [ -f ${B}/u-boot.efi ]; then
        install -m 0644 ${B}/u-boot.efi ${DEPLOYDIR}/BOOTx64.EFI
        bbnote "Deployed u-boot.efi as BOOTx64.EFI"
    else
        bbwarn "u-boot.efi not found at ${B}/u-boot.efi, skipping BOOTx64.EFI deployment"
    fi
}

# ============================================================================
# Deploy u-boot.efi as BOOTAA64.EFI (ARM64)
# ============================================================================

do_deploy:append:qemuarm64() {
    # Install u-boot.efi as BOOTAA64.EFI for UEFI boot
    if [ -f ${B}/u-boot.efi ]; then
        install -m 0644 ${B}/u-boot.efi ${DEPLOYDIR}/BOOTAA64.EFI
        bbnote "Deployed u-boot.efi as BOOTAA64.EFI"
    else
        bbwarn "u-boot.efi not found at ${B}/u-boot.efi, skipping BOOTAA64.EFI deployment"
    fi
}

# ============================================================================
# Optional: Deploy Secure Boot keys if they exist
# ============================================================================

do_deploy:append() {
    # Check if Secure Boot keys are available in the project
    KEYS_DIR="${TOPDIR}/../layers/meta-distro/files/secureboot"

    if [ -d "${KEYS_DIR}" ] && [ -f "${KEYS_DIR}/db.crt" ]; then
        bbnote "Secure Boot keys available at: ${KEYS_DIR}"
        bbnote "Keys can be enrolled for EFI Secure Boot"
    else
        bbnote "Secure Boot keys not found - skipping optional key deployment"
    fi
}
