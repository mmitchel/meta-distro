FILESEXTRAPATHS:prepend := "${THISDIR}/linux:"

# Kernel configuration fragments for LVM, Docker, and cgroups v2
SRC_URI += " \
    file://docker-support.cfg \
    file://builtin-drivers.cfg \
    file://cgroups-v2.cfg \
"

# Deploy kernel and related files from /boot to DEPLOYDIR for WIC
inherit deploy

do_deploy:append() {
    # The kernel class already deploys kernel image, but we ensure
    # any additional files placed in /boot by other recipes are also deployed
    if [ -d "${PKGD}/boot" ]; then
        bbnote "Deploying additional files from /boot"
        cd ${PKGD}/boot
        find . -type f -not -name "vmlinuz*" -not -name "bzImage*" | while read -r file; do
            if [ -f "$file" ]; then
                install -D -m 0644 "$file" "${DEPLOYDIR}/boot/$file"
            fi
        done
    fi
}
