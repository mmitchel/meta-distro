# Boot File Deployment bbappends

This directory contains bbappends for GRUB recipes that ensure all files installed to `/boot` are properly deployed to `${DEPLOYDIR}/boot` for WIC image creation.

## Created bbappends

### grub-efi_%.bbappend
- **Purpose**: Deploy GRUB EFI bootloader files from `/boot`
- **Task**: `do_deploy:append()` - recursively copies all files from `${D}/boot` to `${DEPLOYDIR}/boot`
- **Note**: grub-efi already has a `do_deploy` task for the main EFI image; this extends it for any additional files

### grub_%.bbappend
- **Purpose**: Deploy GRUB (legacy/BIOS) files from `/boot`
- **Task**: `do_deploy()` - recursively copies all files from `${D}/boot` to `${DEPLOYDIR}/boot`
- **Inherits**: deploy class
- **Task order**: `after do_install before do_build`

### grub-bootconf_%.bbappend
- **Purpose**: Deploy GRUB boot configuration files from `/boot`
- **Task**: `do_deploy()` - recursively copies all files from `${D}/boot` to `${DEPLOYDIR}/boot`
- **Inherits**: deploy class
- **Task order**: `after do_install before do_build`

## Integration with WIC

All deployed files in `${DEPLOYDIR}/boot` become available to WIC's bootimg-efi and bootimg plugins for creating boot partition images. This ensures:

1. All bootloader files are included in the boot partition
2. Configuration files are properly placed
3. Custom boot scripts or additional files are preserved
4. Consistent behavior across different bootloader implementations

## Related Files

- [systemd-bootconf_%.bbappend](../systemd-bootconf/systemd-bootconf_%.bbappend): Deploys systemd-boot files and Secure Boot keys
- [secureboot-keys.bbappend](../secureboot-keys/secureboot-keys.bbappend): Deploys UEFI Secure Boot keys
- [linux-yocto_%.bbappend](../../recipes-kernel/linux/linux-yocto_%.bbappend): Deploys kernel and additional boot files

## Architecture

```
Recipe do_install         Recipe do_deploy           WIC Image Creation
     ↓                          ↓                           ↓
${D}/boot/*        →    ${DEPLOYDIR}/boot/*     →    Boot Partition
(rootfs staging)         (deployment area)           (final image)
```

## Usage

These bbappends are automatically applied when building images that include GRUB. No additional configuration is required.

To verify deployed files:
```bash
ls -laR tmp/deploy/images/${MACHINE}/boot/
```

## Notes

- All file permissions are preserved as 0644 (readable by all, writable by owner)
- Directory structure under `/boot` is preserved in `${DEPLOYDIR}/boot`
- Empty directories are not copied (only files)
- Symbolic links are not followed (only regular files are copied)
