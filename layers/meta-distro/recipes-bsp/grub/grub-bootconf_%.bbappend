# Deploy grub boot configuration files from /boot for WIC
inherit deploy

do_deploy() {
    # grub-bootconf installs configuration files to /boot
    if [ -d "${D}/boot" ]; then
        bbnote "Deploying grub-bootconf files from /boot"
        cd ${D}/boot
        find . -type f | while read -r file; do
            install -D -m 0644 "$file" "${DEPLOYDIR}/boot/$file"
        done
    fi
}

addtask deploy after do_install before do_build
