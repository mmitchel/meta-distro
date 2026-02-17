# Deploy kexecboot configuration files from /boot for WIC
inherit deploy

do_deploy() {
    # kexecboot-cfg installs boot.cfg and icon.xpm to /boot
    if [ -d "${D}/boot" ]; then
        bbnote "Deploying kexecboot-cfg files from /boot"
        cd ${D}/boot
        find . -type f | while read -r file; do
            install -D -m 0644 "$file" "${DEPLOYDIR}/boot/$file"
        done
    fi
}

addtask deploy after do_install before do_build
