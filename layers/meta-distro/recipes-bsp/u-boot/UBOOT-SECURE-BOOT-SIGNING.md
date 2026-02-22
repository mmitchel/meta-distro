# U-Boot EFI Secure Boot Signing Configuration

## Overview

This document explains how u-boot.efi is signed for EFI Secure Boot in the DISTRO project, based on the signing methodology used by grub-efi in meta-secure-core.

## Architecture

### EFI Secure Boot Signing Model

The EFI Secure Boot architecture uses a hierarchical key structure:

```
Platform Key (PK)
    └── Key Exchange Key (KEK)
        ├── db (Authorized Signatures Database)
        │   └── Signs bootloader binaries (grub-efi, u-boot.efi)
        │
        └── dbx (Forbidden Signatures Database)
            └── Revocation list for compromised binaries
```

### u-boot.efi Signing Flow

```
1. u-boot binary compiled to EFI format (u-boot.efi)
   ↓
2. Check if EFI Secure Boot enabled (efi-secure-boot in DISTRO_FEATURES)
   ↓
3. Locate Secure Boot keys (DB.key, DB.crt)
   ↓
4. Sign u-boot.efi with sbsign tool:
   sbsign --key DB.key --cert DB.crt --output u-boot.efi.signed u-boot.efi
   ↓
5. Deploy signed binary as BOOTx64.EFI or BOOTAA64.EFI
   ↓
6. At boot: UEFI firmware verifies signature using db certificate
```

## Configuration

### 1. Recipe Configuration (u-boot_%.bbappend)

The u-boot recipe now includes:

```bitbake
# Enable EFI Secure Boot support inheritance
inherit ${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', 'user-key-store', '', d)}

# Add sbsigntool dependency for signing
DEPENDS:append = "${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot', ' sbsigntool-native', '', d)}"

# Add task to sign u-boot.efi after compilation
addtask efi_sign_uboot after do_compile before do_deploy
```

### 2. Distribution Features

Enable EFI Secure Boot signing in `conf/distro/include/defaults.inc`:

```bitbake
# Enable EFI Secure Boot feature
DISTRO_FEATURES:append = " efi-secure-boot"

# Optional: Enable MOK (Machine Owner Key) mode for shim boot chain
MOK_SB = "1"  # If using shim bootloader

# Optional: Enable UEFI SB mode for direct u-boot verification
UEFI_SB = "1"
```

## Signing Models

### Model 1: UEFI Secure Boot (Direct)

**Configuration:** `UEFI_SB = "1"`, `MOK_SB = "0"`

**Flow:**
1. u-boot.efi signed with DB.key/DB.crt
2. UEFI firmware verifies signature directly using db certificate
3. No intermediate bootloader (shim) required

**Keys Used:**
- `DB.key` - Private key for signing
- `DB.crt` - Public certificate in db database

**Deployment:**
```bash
# Signed binary deployed as bootloader
/boot/efi/BOOTx64.EFI (x86-64)
/boot/efi/BOOTAA64.EFI (ARM64)
```

### Model 2: MOK Secure Boot (Shim Chain)

**Configuration:** `MOK_SB = "1"`, `UEFI_SB = "1"`

**Flow:**
1. shim signed with Microsoft/vendor key (db certificate)
2. u-boot.efi signed with vendor_cert.key/vendor_cert.crt
3. shim verifies u-boot.efi signature before executing
4. Allows intermediate key rotation without UEFI firmware updates

**Keys Used:**
- `vendor_cert.key` - Private key for signing
- `vendor_cert.crt` - Public certificate verified by shim

**Deployment:**
```bash
# shim (Microsoft-signed) as primary bootloader
/boot/efi/BOOTx64.EFI (shim)

# u-boot.efi signed with vendor key
/boot/efi/grubx64.efi (u-boot.efi in MOK mode)
```

## Key Files and Locations

### Source Key Location
```
layers/meta-distro/files/secureboot/
├── PK.key / PK.crt          - Platform Key (root of trust)
├── KEK.key / KEK.crt        - Key Exchange Key
├── DB.key / DB.crt          - Database key (signs bootloaders)
├── DBX.key / DBX.crt        - Revocation key (optional)
├── shim_cert.key / shim_cert.crt   - Shim verification cert (MOK mode)
└── vendor_cert.key / vendor_cert.crt - Vendor signing cert (MOK mode)
```

### Generated Keys Directory
```
${UEFI_SB_KEYS_DIR}/ or ${MOK_SB_KEYS_DIR}/
```

### Deployed Keys Location
```
/boot/loader/keys/
├── *.auth               - EFI Authenticode format
├── *.esl                - EFI Signature List format
└── *.crt                - X.509 Certificates
```

## Signing Process Details

### 1. Key Verification

Before signing, the recipe verifies key availability:

```bash
# Check UEFI_SB keys
for key in PK KEK DB; do
  test -f "${UEFI_SB_KEYS_DIR}/${key}.key" || error "Missing ${key}.key"
  test -f "${UEFI_SB_KEYS_DIR}/${key}.crt" || error "Missing ${key}.crt"
done

# Check MOK_SB keys (if enabled)
for key in shim_cert vendor_cert; do
  test -f "${MOK_SB_KEYS_DIR}/${key}.key" || error "Missing ${key}.key"
  test -f "${MOK_SB_KEYS_DIR}/${key}.crt" || error "Missing ${key}.crt"
done
```

### 2. Signing Command

The actual signing is performed using `sbsign`:

```bash
# UEFI_SB mode
sbsign --key DB.key \
       --cert DB.crt \
       --output u-boot.efi.signed \
       u-boot.efi

# MOK_SB mode
sbsign --key vendor_cert.key \
       --cert vendor_cert.crt \
       --output u-boot.efi.signed \
       u-boot.efi
```

### 3. Signature Verification

At boot time, UEFI firmware verifies the signature:

```bash
# Verify with sbverify (diagnostic)
sbverify --cert DB.crt u-boot.efi.signed
# Output: Signature verification OK
```

## Comparison with grub-efi

### grub-efi Signing (Reference Implementation)

From `meta-secure-core/meta-efi-secure-boot/recipes-bsp/grub/grub-efi-efi-secure-boot.inc`:

```bitbake
DEPENDS += "sbsigntool-native"

GRUB_SIGNING_MODULES += "${@'pgp gcry_rsa gcry_sha256 gcry_sha512 --pubkey %s' \
  if d.getVar('GRUB_SIGN_VERIFY') == '1' else ''}"

do_compile:append() {
  grub-mkimage ... ${GRUB_SIGNING_MODULES} ...
}

do_install:append() {
  install -m 0644 "${B}/${GRUB_IMAGE}" "${D}${EFI_BOOT_PATH}/${GRUB_IMAGE}"
}
```

### u-boot.efi Signing (This Implementation)

Follows same pattern:

```bitbake
DEPENDS:append = "${@bb.utils.contains('DISTRO_FEATURES', 'efi-secure-boot',
  'sbsigntool-native', '', d)}"

addtask efi_sign_uboot after do_compile before do_deploy

do_efi_sign_uboot() {
  sbsign --key DB.key --cert DB.crt --output u-boot.efi.signed u-boot.efi
}

do_deploy:append() {
  install -m 0644 ${B}/u-boot.efi.signed ${DEPLOYDIR}/BOOTx64.EFI
}
```

## Building with EFI Secure Boot

### Prerequisites

1. **Meta-secure-core layer enabled** in `bblayers.conf`:
   ```
   BBLAYERS += "${TOPDIR}/../layers/meta-secure-core/..."
   ```

2. **EFI Secure Boot feature enabled** in `local.conf`:
   ```
   DISTRO_FEATURES:append = " efi-secure-boot"
   ```

3. **Secure Boot keys generated** in `files/secureboot/`:
   ```bash
   cd layers/meta-distro/files/secureboot
   ./generate-keys.sh
   ```

4. **sbsigntool installed** (automatically via sbsigntool-native recipe):
   ```bash
   bitbake sbsigntool-native
   ```

### Build Command

```bash
source setup-build.sh
source layers/poky/oe-init-build-env

# Build u-boot with Secure Boot signing
bitbake u-boot
```

### Build Output

```
...
do_efi_sign_uboot: Signing u-boot.efi with EFI Secure Boot key
do_efi_sign_uboot: ✓ Successfully signed u-boot.efi
do_deploy: ✓ Deployed u-boot.efi (signed: YES) as BOOTx64.EFI
...
```

## Verification

### 1. Check Signed Binary

```bash
# List deployed artifacts
ls -lh build/tmp/deploy/images/qemux86-64/BOOTx64.EFI

# File size should match original + signature (~100 bytes)
du -h BOOTx64.EFI
```

### 2. Verify Signature (On Build Host)

```bash
# Verify with sbverify
sbverify --cert layers/meta-distro/files/secureboot/DB.crt \
         build/tmp/deploy/images/qemux86-64/BOOTx64.EFI
# Output: Signature verification OK
```

### 3. Check Signature at Boot (In QEMU/Hardware)

```bash
# From u-boot console
=> efi query var db
=> sbverify BOOTx64.EFI

# From Linux after boot
# dmesg | grep -i secureboot
# mokutil --sb-state
```

## Troubleshooting

### Issue: "Secure Boot keys not found"

**Cause:** Keys not generated or in wrong location

**Solution:**
```bash
cd layers/meta-distro/files/secureboot
./generate-keys.sh
# Verify: ls -la DB.key DB.crt
```

### Issue: "sbsign not found"

**Cause:** sbsigntool-native not built

**Solution:**
```bash
bitbake sbsigntool-native
# Or clean and rebuild:
bitbake -c cleanall u-boot
bitbake u-boot
```

### Issue: "Signature verification failed at boot"

**Cause:** Signature doesn't match firmware's db certificate

**Solution:**
1. Verify signing was successful: `sbverify --cert DB.crt BOOTx64.EFI`
2. Check UEFI firmware has correct db certificate enrolled
3. Ensure DB.crt in firmware matches key used for signing

### Issue: "u-boot.efi deployment shows unsigned"

**Cause:** Signing failed (keys missing) but build continued

**Solution:**
1. Check build log for signing errors
2. Verify keys exist: `ls -la files/secureboot/DB.key DB.crt`
3. Check sbsign output: `sbsign --key DB.key --cert DB.crt -o test.efi u-boot.efi`

## Security Considerations

### 1. Key Management

- **PK (Platform Key):** Root of trust, controls all other keys
  - Store securely, preferably offline or on HSM
  - Rotation requires firmware update

- **KEK (Key Exchange Key):** Controls db/dbx updates
  - Can be rotated without firmware update
  - Sign with PK

- **DB (Database):** Used to verify bootloader signatures
  - Can be updated via KEK
  - Bootloaders must be signed with corresponding private key

### 2. Signature Verification

- **Bootloader verification:** UEFI firmware verifies BOOTx64.EFI signature before execution
- **Chain of trust:** UEFI firmware → BOOTx64.EFI (u-boot) → Linux kernel → OS
- **Measurement:** PCR7 extends with Secure Boot state for attestation

### 3. Revocation List (dbx)

- Keep updated with revoked bootloader signatures
- Prevents execution of compromised binaries even if keys match
- Signed by KEK for updates

## Related Documentation

- [meta-secure-core EFI Secure Boot](../../../meta-secure-core/meta-efi-secure-boot/README.md)
- [u-boot Secure Boot Integration](https://u-boot.readthedocs.io/en/latest/develop/uefi_secure_boot.html)
- [UEFI Secure Boot Specification](https://uefi.org/specs/UEFI/2.10/Chapter_28_Secure_Boot_and_Driver_Signing.html)
- [sbsigntool Documentation](https://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git)
- [EFI Signature List Format](https://github.com/rhboot/shim/blob/main/docs/sbat.md)

## Version Information

- **u-boot:** 2024.01+
- **sbsigntool:** 0.9.5+
- **OpenSSL:** 1.1.1+ or 3.0+
- **DISTRO:** DISTRO Project (February 2026)

## Contributing

To improve this Secure Boot signing implementation:

1. Test with different u-boot versions
2. Verify with various UEFI implementations (OVMF, EDK2, firmware)
3. Add TPM integration for measured boot
4. Implement key rotation procedures
5. Add signing to other EFI binaries (kernel, shim)

---

**Document Version:** 1.0
**Last Updated:** February 20, 2026
**Author:** DISTRO Project Contributors
**License:** MIT
