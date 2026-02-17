FILESEXTRAPATHS:prepend := "${THISDIR}/${PN}:"

# Prevent conflict with shadow-securetty
# base-files provides /etc/securetty, shadow-securetty should not be installed
RDEPENDS:${PN}:remove = "shadow-securetty"
RCONFLICTS:${PN} = "shadow-securetty"

# Disable volatile directories (/var is on separate LVM volume)
dirs1777 = "/tmp"
volatiles = ""

# Lock root account from console and serial port logins
# This prevents direct root login while allowing SSH key-based access
do_install:append() {
    # Create securetty with no entries to block root console logins
    # Empty securetty means no TTYs are considered secure for root login
    install -d ${D}${sysconfdir}
    echo "# No secure TTYs - root console login disabled" > ${D}${sysconfdir}/securetty
    echo "# Root can still login via SSH with authorized keys" >> ${D}${sysconfdir}/securetty
}
