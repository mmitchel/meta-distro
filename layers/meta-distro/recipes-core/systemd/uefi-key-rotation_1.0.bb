SUMMARY = "UEFI Secure Boot Key Rotation Update Script"
DESCRIPTION = "Runtime script for updating UEFI Secure Boot keys with exception handling and rollback capability"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade40b6dfe2b11ba542a1f1f1234"

SRC_URI = "file://update-uefi-keys.sh"

S = "${WORKDIR}"

RDEPENDS:${PN} = "bash systemd efitools"

do_install() {
    # Create script directory
    install -d ${D}${prefix}/local/sbin

    # Install update script
    install -m 0750 update-uefi-keys.sh ${D}${prefix}/local/sbin/

    # Create key directories structure
    install -d ${D}/boot/loader/keys/production
    install -d ${D}/boot/loader/keys/rotation
    install -d ${D}/boot/loader/keys/backup
    install -d ${D}/boot/loader/keys/rollback

    # Create log directory
    install -d ${D}${localstatedir}/log/distro

    # Create symlink for easy access
    mkdir -p ${D}${prefix}/bin
    ln -sf ${prefix}/local/sbin/update-uefi-keys.sh ${D}${prefix}/bin/update-uefi-keys 2>/dev/null || true
}

FILES:${PN} = " \
    ${prefix}/local/sbin/update-uefi-keys.sh \
    ${prefix}/bin/update-uefi-keys \
    /boot/loader/keys \
    ${localstatedir}/log/distro \
"

SYSTEMD_AUTO_ENABLE = "disable"

inherit allarch
