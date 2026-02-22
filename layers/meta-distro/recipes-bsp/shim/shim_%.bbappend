# Deploy all shim files from /boot for WIC
do_deploy:append() {
    # Ensure all files installed to /boot are also deployed
    if [ -d "${D}/boot" ]; then
        bbnote "Deploying shim files from /boot"
        cd ${D}/boot
        find . -type f | while read -r file; do
            install -D -m 0644 "$file" "${DEPLOYDIR}/boot/$file"
        done
    fi
}
