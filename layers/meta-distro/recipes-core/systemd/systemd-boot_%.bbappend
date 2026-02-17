# systemd-boot EFI files are automatically deployed by the systemd-boot recipe
# The bootimg-efi WIC plugin will find them in ${DEPLOYDIR}
# Files deployed: systemd-bootx64.efi (or bootx64.efi if EFI_PROVIDER="systemd-boot"),
# linuxx64.efi.stub, and addonx64.efi.stub

# No additional deployment needed - systemd-boot recipe's do_deploy task handles this
