# Ensure package is created and installable
FILES_${PN} = "/etc/passwd /etc/group /home/user"
SUMMARY = "Add user 'user' with UID 1000 and GID 1000 to image"
DESCRIPTION = "Creates a user 'user' with UID 1000 and GID 1000 for container and system images."
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfdbcc9c4ca079f46a893f1e2d8e"

inherit useradd

USERADD_PACKAGES = "${PN}"

USERADD_PARAM:${PN} += "-u 1000 -g 1000 -m user;"
GROUPADD_PARAM:${PN} += "-g 1000 user;"

do_install() {
	install -d ${D}/home/user
}

FILES:${PN} += "/home/user/"
