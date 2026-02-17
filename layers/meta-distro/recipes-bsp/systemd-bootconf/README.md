# systemd-boot Configuration and Secure Boot Keys

This directory contains the bbappend for systemd-bootconf to integrate Secure Boot keys.

## Overview

The `systemd-bootconf_%.bbappend` extends the systemd-boot configuration recipe to:
1. Copy Secure Boot keys from `layers/meta-distro/files/secureboot/` to the boot partition
2. Place keys in `/boot/loader/keys/` where systemd-boot expects them
3. Include keys in WIC images automatically

## Key Locations

### Source (in layer):
```
layers/meta-distro/files/secureboot/
├── PK.auth, PK.esl, PK.crt      # Platform Key
├── KEK.auth, KEK.esl, KEK.crt   # Key Exchange Key
├── db.auth, db.esl, db.crt      # Signature Database
├── dbx.auth, dbx.esl            # Forbidden Database
└── db.key                       # Private key (optional, dev only)
```

### Target (on boot partition):
```
/boot/loader/keys/
├── PK.auth, PK.esl, PK.crt
├── KEK.auth, KEK.esl, KEK.crt
├── db.auth, db.esl, db.crt
├── dbx.auth, dbx.esl
└── README.txt
```

## Usage

### 1. Generate Keys

First, generate Secure Boot keys:

```bash
cd layers/meta-distro/files/secureboot
./generate-keys.sh
```

This creates all necessary key files in the `files/secureboot/` directory.

### 2. Build Image

Build your Yocto image as normal:

```bash
bitbake core-image-minimal
```

The bbappend automatically:
- Detects keys in `files/secureboot/`
- Copies them to the boot partition during image creation
- Includes them in WIC images

### 3. Verify Keys

After building, verify keys are in the image:

```bash
# Mount the boot partition from WIC image
mkdir -p /tmp/boot
loopdev=$(sudo udisksctl loop-setup --file tmp/deploy/images/qemux86-64/core-image-minimal-qemux86-64.wic --no-user-interaction | awk '{print $NF}' | tr -d '.')
sudo udisksctl mount -b ${loopdev}p1

# Check keys directory
ls -la /tmp/boot/loader/keys/

# Cleanup
sudo udisksctl unmount -b ${loopdev}p1
sudo udisksctl loop-delete -b ${loopdev} --no-user-interaction
```

## Key Files Explained

### Authentication Files (*.auth)
- Used for enrolling keys in UEFI firmware
- Signed with parent key in hierarchy
- Can be applied using `efi-updatevar`

### EFI Signature Lists (*.esl)
- Raw EFI signature data
- Used by UEFI firmware
- Can be loaded directly in some UEFI implementations

### Certificates (*.crt)
- X.509 certificates in PEM format
- For reference and verification
- Used with `sbverify` to check signatures

### Private Keys (*.key)
- **Development only!**
- Used to sign kernel and bootloader
- **Never deploy to production!**

## Signing Kernel and Bootloader

To enable automatic signing during build, add to `local.conf`:

```bitbake
# Enable UEFI Secure Boot signing
UEFI_SB_SIGN_ENABLE = "1"

# Path to signing key (db.key)
UEFI_SB_SIGN_KEY = "${LAYERDIR_meta-distro}/files/secureboot/db.key"
UEFI_SB_SIGN_CERT = "${LAYERDIR_meta-distro}/files/secureboot/db.crt"
```

This will automatically sign:
- systemd-boot EFI bootloader
- Linux kernel
- Any additional EFI binaries

## Manual Signing

To manually sign the bootloader and kernel:

```bash
# Sign systemd-boot
sbsign --key files/secureboot/db.key \
       --cert files/secureboot/db.crt \
       --output systemd-bootx64.efi.signed \
       systemd-bootx64.efi

# Sign kernel
sbsign --key files/secureboot/db.key \
       --cert files/secureboot/db.crt \
       --output vmlinuz.signed \
       vmlinuz
```

## Enrolling Keys in UEFI

### Method 1: Using efi-updatevar (Recommended)

Boot the system and run:

```bash
# Mount boot partition if not already mounted
mount /boot

# Enroll keys in order: dbx, db, KEK, PK (last)
efi-updatevar -f /boot/loader/keys/dbx.auth dbx
efi-updatevar -f /boot/loader/keys/db.auth db
efi-updatevar -f /boot/loader/keys/KEK.auth KEK
efi-updatevar -f /boot/loader/keys/PK.auth PK

# Verify enrollment
efi-readvar
```

### Method 2: UEFI Firmware Setup

1. Boot into UEFI firmware setup (usually F2, Del, or Esc during boot)
2. Navigate to Secure Boot configuration
3. Select "Enroll keys from disk"
4. Browse to `/boot/loader/keys/`
5. Load each key file (PK, KEK, db, dbx)
6. Enable Secure Boot
7. Save and exit

### Method 3: Automatic Enrollment

Some UEFI firmware implementations support automatic key enrollment:
- Keys in `/boot/loader/keys/` may be auto-detected
- Check your firmware documentation

## Troubleshooting

### Keys not found during build

**Problem**: Build warns "Secure Boot keys not found"

**Solution**:
```bash
cd layers/meta-distro/files/secureboot
./generate-keys.sh
bitbake core-image-minimal -c cleanall
bitbake core-image-minimal
```

### Keys not in boot partition

**Problem**: `/boot/loader/keys/` is empty

**Check**:
1. Verify keys exist: `ls layers/meta-distro/files/secureboot/`
2. Check bbappend is applied: `bitbake-layers show-appends | grep systemd-boot`
3. Check build log: `grep "Secure Boot keys" tmp/log/cooker/*/console-latest.log`

### Boot fails with Secure Boot enabled

**Problem**: System doesn't boot when Secure Boot is enabled

**Solutions**:
1. Verify kernel is signed: `sbverify --cert db.crt /boot/vmlinuz`
2. Verify bootloader is signed: `sbverify --cert db.crt /boot/efi/EFI/systemd/systemd-bootx64.efi`
3. Check keys are enrolled: `efi-readvar`
4. Verify signature database contains your db certificate

### Wrong signature on bootloader

**Problem**: "Signature verification failed" error

**Solutions**:
1. Ensure bootloader was signed with correct db.key
2. Verify db certificate is enrolled in UEFI
3. Re-sign bootloader: `sbsign --key db.key --cert db.crt ...`
4. Check certificate hasn't expired: `openssl x509 -in db.crt -text`

## Security Best Practices

### Development Environment

For development and testing:
- ✅ Store keys in `files/secureboot/`
- ✅ Include db.key for automatic signing
- ✅ Test key enrollment and Secure Boot
- ⚠️  Add `*.key` to `.gitignore` before committing

### Production Environment

For production systems:
- ❌ **NEVER** include private keys (*.key) in layer
- ✅ Generate keys on secure, offline system
- ✅ Store private keys in HSM or secure vault
- ✅ Only include public keys (*.crt, *.esl, *.auth)
- ✅ Sign bootloader/kernel on secure build server
- ✅ Use separate keys per product/customer

### Key Rotation

To rotate keys:
1. Generate new keys with new GUID
2. Sign new KEK with old PK
3. Sign new db with old KEK
4. Update UEFI firmware with new keys
5. Re-sign bootloader and kernel
6. Deploy updated image

## Testing Secure Boot

### Verify Keys on Running System

```bash
# Check Secure Boot status
mokutil --sb-state

# Read enrolled keys
efi-readvar

# Check specific key
efi-readvar -v PK

# Verify boot components
sbverify --cert /boot/loader/keys/db.crt /boot/efi/EFI/systemd/systemd-bootx64.efi
sbverify --cert /boot/loader/keys/db.crt /boot/vmlinuz
```

### Test Unsigned Boot (Should Fail)

To verify Secure Boot is working:
1. Create unsigned copy of kernel: `cp /boot/vmlinuz /boot/vmlinuz-unsigned`
2. Update boot entry to use unsigned kernel
3. Reboot - should fail to boot
4. This confirms Secure Boot is enforcing signatures

## Integration with OSTree

For OSTree-based systems (using meta-updater):
- Keys persist across updates (stored in separate boot partition)
- Each OSTree deployment can be signed separately
- Update process: sign → deploy → verify signature → boot
- Keys remain in `/boot/loader/keys/` across deployments

## References

- [systemd-boot Documentation](https://www.freedesktop.org/software/systemd/man/systemd-boot.html)
- [UEFI Secure Boot Specification](https://uefi.org/specifications)
- [sbsigntools Documentation](https://git.kernel.org/pub/scm/linux/kernel/git/jejb/sbsigntools.git)
- [Yocto Secure Boot](https://docs.yoctoproject.org/)
