# Ensure all grub-efi files from /boot are deployed for WIC
do_deploy:append() {
    # grub-efi already deploys the main image, but ensure any other files
    # that might be installed to /boot are also deployed
    if [ -d "${D}/boot" ]; then
        bbnote "Deploying grub-efi files from /boot"
        cd ${D}/boot
        find . -type f | while read -r file; do
            install -D -m 0644 "$file" "${DEPLOYDIR}/boot/$file"
        done
    fi
}
