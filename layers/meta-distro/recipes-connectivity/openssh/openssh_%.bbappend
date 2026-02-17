FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

SRC_URI += "file://sshd_config_custom"

do_install:append() {
    # Append custom SSH server settings (key-based auth, root login)
    cat ${WORKDIR}/sshd_config_custom >> ${D}${sysconfdir}/ssh/sshd_config
}
