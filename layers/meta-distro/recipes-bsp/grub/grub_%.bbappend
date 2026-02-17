# Deploy all grub files from /boot for WIC
inherit deploy

do_deploy() {
    # grub (non-efi) may install files to /boot
    if [ -d "${D}/boot" ]; then
        bbnote "Deploying grub files from /boot"
        cd ${D}/boot
        find . -type f | while read -r file; do
            install -D -m 0644 "$file" "${DEPLOYDIR}/boot/$file"
        done
    fi
}

addtask deploy after do_install before do_build
