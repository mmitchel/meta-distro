# UEFI Secure Boot Configuration

This layer includes support for UEFI Secure Boot with systemd-boot bootloader.

## Bootloader

The layer uses **systemd-boot** instead of GRUB for UEFI boot:
- Faster boot times
- Simpler configuration
- Native Secure Boot support
- Integrated with systemd ecosystem

## Secure Boot Keys

Secure Boot keys are installed to `/boot/loader/keys/` for systemd-boot integration:

### Key Hierarchy

```
PK (Platform Key)
  └─ KEK (Key Exchange Key)
      ├─ db (Signature Database) - Authorized signatures
      └─ dbx (Forbidden Database) - Revoked signatures
```

### Generated Files

For each key type (PK, KEK, db, dbx):
- `*.key` - Private key (RSA 2048-bit)
- `*.crt` - X.509 certificate
- `*.der` - DER-encoded certificate
- `*.esl` - EFI Signature List
- `*.auth` - Authenticated variable (for UEFI updates)

### Key Locations

On the target system:
- `/boot/loader/keys/` - All Secure Boot keys and certificates
- `/boot/loader/keys/README.txt` - Key usage documentation

### Security Considerations

**⚠️ IMPORTANT:**
- Private keys (`*.key`) are included for development/testing
- **DO NOT deploy private keys to production systems**
- For production:
  - Generate keys on secure, offline system
  - Only deploy public keys (`*.crt`, `*.esl`, `*.auth`)
  - Store private keys in HSM or secure key storage
  - Sign bootloader and kernel with your production keys

### Customizing Keys

To use custom Secure Boot keys:

1. **Generate your own keys:**
   ```bash
   # Edit the GUID in the recipe
   # layers/meta-distro/recipes-bsp/secureboot-keys/secureboot-keys.bb
   GUID = "your-custom-guid-here"
   ```

2. **Use existing keys:**
   - Replace files in `recipes-bsp/secureboot-keys/secureboot-keys/`
   - Or create a bbappend with your key files

3. **Sign kernel and bootloader:**
   ```bitbake
   # In local.conf or machine config
   UEFI_SB_SIGN_ENABLE = "1"
   UEFI_SB_SIGN_KEY = "/path/to/db.key"
   UEFI_SB_SIGN_CERT = "/path/to/db.crt"
   ```

### Enrolling Keys in UEFI

Keys can be enrolled in UEFI firmware using several methods:

**Method 1: Using efi-updatevar (Linux)**
   ```bash
   # From running system with mounted /boot
   efi-updatevar -f /boot/loader/keys/PK.auth PK
   efi-updatevar -f /boot/loader/keys/KEK.auth KEK
   efi-updatevar -f /boot/loader/keys/db.auth db
   efi-updatevar -f /boot/loader/keys/dbx.auth dbx
   ```

**Method 2: UEFI Setup Menu**
- Boot into UEFI firmware setup
- Navigate to Secure Boot configuration
- Load keys from `/boot/loader/keys/` directory
- Enable Secure Boot

**Method 3: Automated enrollment**
- Some UEFI implementations auto-enroll keys from specific paths
- Check your firmware documentation

### Verifying Secure Boot Status

```bash
# Check if Secure Boot is enabled
mokutil --sb-state

# Or check UEFI variable directly
cat /sys/firmware/efi/efivars/SecureBoot-*
```

### Signing Bootloader and Kernel

The systemd-boot bootloader and kernel must be signed with the db key:

```bitbake
# Machine configuration or local.conf
UEFI_SIGN_ENABLE = "1"
UEFI_SIGN_KEYDIR = "${DEPLOY_DIR}/secureboot-keys"
```

For manual signing:
```bash
# Sign systemd-boot
sbsign --key db.key --cert db.crt \
       --output systemd-bootx64.efi.signed systemd-bootx64.efi

# Sign kernel
sbsign --key db.key --cert db.crt \
       --output vmlinuz.signed vmlinuz
```

### Troubleshooting

**Keys not found in /boot/loader/keys/**
- Ensure `secureboot-keys` is in `CORE_IMAGE_EXTRA_INSTALL`
- Check that `/boot` partition is properly mounted
- Verify WKS file uses systemd-boot: `loader=systemd-boot`

**Secure Boot verification failed**
- Ensure bootloader and kernel are signed with db key
- Check key enrollment in UEFI: `efi-readvar`
- Verify signatures: `sbverify --cert db.crt bootx64.efi`

**Boot fails with Secure Boot enabled**
- Disable Secure Boot temporarily in UEFI setup
- Check kernel/bootloader signatures
- Verify correct keys are enrolled
- Check UEFI logs for signature verification errors

## References

- [UEFI Secure Boot Specification](https://uefi.org/specifications)
- [systemd-boot Documentation](https://www.freedesktop.org/software/systemd/man/systemd-boot.html)
- [Yocto Project - UEFI Secure Boot](https://docs.yoctoproject.org/)
