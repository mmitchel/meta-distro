FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://factory-var.conf"
SRC_URI += "file://ostree-bootloader-update.service"
SRC_URI += "file://ostree-cleanup-deployments.service"
SRC_URI += "file://ostree-pull-updates.service"
SRC_URI += "file://ostree-pull-updates.timer"

do_install:append() {
    # Install systemd-tmpfiles configuration for factory /var restoration
    # Place in /usr/lib/tmpfiles.d/ for early initialization during boot
    install -d ${D}${prefix}/lib/tmpfiles.d
    install -m 0644 ${WORKDIR}/factory-var.conf ${D}${prefix}/lib/tmpfiles.d/factory-var.conf

    # Install OSTree bootloader update service
    if ${@bb.utils.contains('DISTRO_FEATURES', 'sota', 'true', 'false', d)}; then
        install -d ${D}${systemd_system_unitdir}
        install -m 0644 ${WORKDIR}/ostree-bootloader-update.service ${D}${systemd_system_unitdir}/
        install -m 0644 ${WORKDIR}/ostree-cleanup-deployments.service ${D}${systemd_system_unitdir}/
        install -m 0644 ${WORKDIR}/ostree-pull-updates.service ${D}${systemd_system_unitdir}/
        install -m 0644 ${WORKDIR}/ostree-pull-updates.timer ${D}${systemd_system_unitdir}/
    fi
}

FILES:${PN} += "${prefix}/lib/tmpfiles.d/factory-var.conf"
FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sota', '${systemd_system_unitdir}/ostree-bootloader-update.service', '', d)}"
FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sota', '${systemd_system_unitdir}/ostree-cleanup-deployments.service', '', d)}"
FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sota', '${systemd_system_unitdir}/ostree-pull-updates.service', '', d)}"
FILES:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sota', '${systemd_system_unitdir}/ostree-pull-updates.timer', '', d)}"

SYSTEMD_SERVICE:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sota', 'ostree-bootloader-update.service', '', d)}"
SYSTEMD_SERVICE:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sota', 'ostree-cleanup-deployments.service', '', d)}"
SYSTEMD_SERVICE:${PN} += "${@bb.utils.contains('DISTRO_FEATURES', 'sota', 'ostree-pull-updates.timer', '', d)}"
