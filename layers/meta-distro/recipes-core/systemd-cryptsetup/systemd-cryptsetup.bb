SUMMARY = "systemd cryptsetup configuration for LUKS volumes"
DESCRIPTION = "Provides crypttab configuration for unlocking LUKS-encrypted LVM at boot"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://crypttab"

S = "${WORKDIR}"

do_install() {
    # Install crypttab for systemd-cryptsetup
    install -d ${D}${sysconfdir}
    install -m 0600 ${WORKDIR}/crypttab ${D}${sysconfdir}/crypttab
}

FILES:${PN} = "${sysconfdir}/crypttab"

# Only install if using encrypted volumes
RRECOMMENDS:${PN} = "cryptsetup"
