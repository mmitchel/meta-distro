# Deploy Secure Boot keys for WIC image creation
do_deploy() {
    install -d ${DEPLOYDIR}/boot/efi/EFI/keys

    # Deploy all key files
    install -m 0600 ${D}/boot/efi/EFI/keys/*.esl ${DEPLOYDIR}/boot/efi/EFI/keys/
    install -m 0600 ${D}/boot/efi/EFI/keys/*.auth ${DEPLOYDIR}/boot/efi/EFI/keys/
    install -m 0644 ${D}/boot/efi/EFI/keys/*.crt ${DEPLOYDIR}/boot/efi/EFI/keys/
    install -m 0644 ${D}/boot/efi/EFI/keys/README.txt ${DEPLOYDIR}/boot/efi/EFI/keys/
}

addtask deploy after do_install before do_build
