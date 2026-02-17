# Recipe to create systemd mount unit for /var on LVM volume
# This ensures /var is automatically mounted from /dev/vg0/varfs at boot

SUMMARY = "Systemd mount unit for /var on LVM"
DESCRIPTION = "Creates a systemd mount unit to mount /var from LVM logical volume"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcab651e8f7761e65559d3f617"

inherit allarch systemd features_check

REQUIRED_DISTRO_FEATURES = "systemd"

SRC_URI = "file://var.mount"

S = "${WORKDIR}"

SYSTEMD_SERVICE:${PN} = "var.mount"
SYSTEMD_AUTO_ENABLE = "enable"

do_install() {
    install -d ${D}${systemd_system_unitdir}
    install -m 0644 ${WORKDIR}/var.mount ${D}${systemd_system_unitdir}/
}

FILES:${PN} = "${systemd_system_unitdir}/var.mount"
