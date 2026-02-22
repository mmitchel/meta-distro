# UEFI Secure Boot Rotation Key Generation Guide

## Overview

The `generate-rotation-keys.sh` script generates rotation-capable UEFI Secure Boot keys based on existing production keys. This enables organizations to extend key validity from the current 10-year production keys (PK, KEK, DB, DBX from meta-secure-core) to 25-year rotation keys (PK_next, KEK_next, db_next, dbx_next).

**Key Architecture**:

```
Production Keys (Current)          Rotation Keys (Next Generation)
├── PK.key/crt (2017-2027)         ├── PK_next.key/crt (2025-2050)
├── KEK.key/crt                    ├── KEK_next.key/crt
├── DB.key/crt                     ├── db_next.key/crt
└── DBX.key/crt                    └── dbx_next.key/crt
  (uppercase, 10-year)             (lowercase, 25-year)
```

**Purpose**: Enable seamless transition from current production keys (expiring August 2027) to extended rotation keys (valid through 2050)

## Prerequisites

### Required Tools

```bash
# OpenSSL for certificate operations
openssl version
# OpenSSL 1.1.1+ required

# efitools for UEFI-specific operations
which efi-readvar
which cert-to-efi-sig-list
which sign-efi-sig-list

# Standard utilities
which openssl sed grep
```

**Installation**:
```bash
# Ubuntu/Debian
sudo apt-get install openssl efitools

# Fedora/RHEL
sudo dnf install openssl efitools

# Alpine
apk add openssl efitools
```

### Required Source Keys

The script requires reading existing production keys from meta-secure-core:

```
/path/to/meta-secure-core/meta-signing-key/files/uefi_sb_keys/
├── PK.key
├── PK.crt
├── KEK.key
├── KEK.crt
├── DB.key
├── DB.crt
├── DBX/
│   ├── DBX.key
│   └── DBX.crt
└── ms-DB.crt  (Microsoft secondary signature)
```

**Location in DISTRO Project**:
```bash
layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys/
```

### Output Requirements

- Output directory needs ≥ 10MB free space
- Write permissions required
- Optional: 500MB+ for backups/archives

## Quick Start

### Basic Usage

```bash
# Generate rotation keys from production keys
./generate-rotation-keys.sh \
  layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys \
  11111111-2222-3333-4444-123456789abc

# Output created in: ./rotation/
```

### With Custom GUID

```bash
# Use specific UEFI GUID (e.g., your organization's GUID)
./generate-rotation-keys.sh \
  /path/to/production/keys \
  "your-org-guid-1234-5678-90abcdef"

# GUID format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
```

### Dry-Run Mode

```bash
# Validate without generating keys
DRY_RUN=1 ./generate-rotation-keys.sh /path/to/keys
```

## Output Structure

The script generates 20 files (4 keys × 5 formats):

```
rotation/
├── PK_next.key              # RSA private key (keep secure)
├── PK_next.crt              # X.509 certificate
├── PK_next.esl              # EFI Signature List format
├── PK_next.auth             # Authenticated variable format (for enrollment)
├── PK_next.der              # DER format (firmware compatibility)
├── KEK_next.key
├── KEK_next.crt
├── KEK_next.esl
├── KEK_next.auth
├── KEK_next.der
├── db_next.key
├── db_next.crt
├── db_next.esl
├── db_next.auth
├── db_next.der
├── dbx_next.key
├── dbx_next.crt
├── dbx_next.esl
├── dbx_next.auth
└── dbx_next.der
```

### File Format Explanation

| Format | Purpose | Usage |
|--------|---------|-------|
| `.key` | RSA private key (2048-bit) | Key signing operations, key storage |
| `.crt` | X.509 certificate | Distribution, audit, verification |
| `.esl` | EFI Signature List | UEFI firmware format, portable |
| `.auth` | Authenticated variable | UEFI key enrollment via efi-updatevar |
| `.der` | DER binary format | Direct firmware updates, compatibility |

**Security Note**: `.key` files contain sensitive private keys - protect with appropriate file permissions (mode 0600)

## Key Generation Process

### Phase 1: Validation

```bash
# Check tools available
openssl version
efi-readvar --version

# Verify source keys exist and are readable
ls -la /path/to/production/keys/PK.key
ls -la /path/to/production/keys/KEK.key
ls -la /path/to/production/keys/DB.key
ls -la /path/to/production/keys/DBX/DBX.key
```

**Output**:
```
✓ OpenSSL available: OpenSSL 1.1.1 11 Sep 2018 (OpenSSL)
✓ efitools available
✓ Source keys directory readable
✓ All required key files present
```

### Phase 2: Certificate Analysis

```bash
# Examine production key validity
openssl x509 -in PK.crt -text -noout | grep -A2 "Validity\|Public-Key"
# Output:
#     Validity
#         Not Before: Aug 14 17:00:00 2017 GMT
#         Not After : Aug 12 17:00:00 2027 GMT  ← Expires in ~2 years
#     Public-Key: (2048 bit, RSA)
```

### Phase 3: Key Generation

For each key (PK_next, KEK_next, db_next, dbx_next):

1. **Generate private key**:
   ```bash
   openssl genrsa -out PK_next.key 2048
   ```

2. **Create certificate**:
   ```bash
   # Self-signed with 25-year validity (9125 days)
   openssl req -new -x509 \
     -key PK_next.key \
     -days 9125 \
     -out PK_next.crt \
     -subj "/CN=PK_next"
   ```

3. **Extract UUID/GUID**:
   ```bash
   # Generate EFI GUID from certificate
   openssl x509 -in PK_next.crt -fingerprint -noout | \
     sed 's/.*://;s/://g' | head -c32
   ```

4. **Convert to EFI formats**:
   ```bash
   # EFI Signature List format
   cert-to-efi-sig-list -g GUID PK_next.crt PK_next.esl

   # Authenticated variable (for UEFI enrollment)
   sign-efi-sig-list -k PK_parent.key PK_next PK_next.esl PK_next.auth

   # DER format for firmware
   openssl x509 -in PK_next.crt -outform DER -out PK_next.der
   ```

### Phase 4: Signing Hierarchy

Rotation keys maintain proper UEFI hierarchy:

```
PK_next (self-signed, root of trust)
  │
  ├── KEK_next (signed by PK_next)
  │   │
  │   ├── db_next (signed by KEK_next)
  │   └── dbx_next (signed by KEK_next)
```

**Key Relationships**:
- **PK_next**: Self-signed root key
  - Signs: KEK_next
  - Enrolls via: PK_next.auth (special handling, requires existing PK)

- **KEK_next**: Signed by PK_next
  - Signs: db_next, dbx_next
  - Enrolls via: KEK_next.auth (signed by PK_next)

- **db_next**: Signed by KEK_next
  - Purpose: Authorize boot components (u-boot, kernel)
  - Enrolls via: db_next.auth (signed by KEK_next)

- **dbx_next**: Signed by KEK_next
  - Purpose: Revocation list (forbidden/compromised keys)
  - Enrolls via: dbx_next.auth (signed by KEK_next)

### Phase 5: Output & Verification

```bash
# List generated files
ls -lh rotation/ | wc -l
# Output: 20 files

# Verify file integrity
openssl x509 -in rotation/PK_next.crt -noout -dates
# Output:
# notBefore=Jan 15 10:00:00 2025 GMT
# notAfter=Dec 31 23:59:59 2049 GMT

# Check private key strength
openssl rsa -in rotation/PK_next.key -noout -text | grep "Public-Key"
# Output: Public-Key: (2048 bit, RSA)
```

## Integration with DISTRO Build System

### Option 1: Build-Time Generation (Recommended)

Generate rotation keys during image build:

```bash
# During BitBake build
source layers/poky/oe-init-build-env

# Build with rotation key generation
GENERATE_ROTATION_KEYS=1 bitbake core-image-minimal

# Rotation keys deployed to:
# /boot/loader/keys/rotation/ in final image
```

**BitBake Recipe Integration**:
```bitbake
GENERATE_ROTATION_KEYS ?= "0"

do_image_append() {
    if [ "${GENERATE_ROTATION_KEYS}" = "1" ]; then
        ${STAGING_BINDIR_NATIVE}/generate-rotation-keys.sh \
            /path/to/production/keys \
            "${ROTATION_KEY_GUID}"
    fi
}
```

### Option 2: Standalone Generation

Generate separately and copy to image:

```bash
# 1. Generate rotation keys
./generate-rotation-keys.sh \
  layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys

# 2. Archive for distribution
tar czf distro-rotation-keys-$(date +%Y%m%d).tar.gz rotation/

# 3. Deploy to systems
scp distro-rotation-keys-*.tar.gz root@target:/boot/loader/keys/
tar xzf /boot/loader/keys/distro-rotation-keys-*.tar.gz -C /boot/loader/keys/
```

### Option 3: Manual Copy to Image Source

```bash
# Copy to image build directory
mkdir -p meta-distro/recipes-core/images/files/rotation-keys
cp rotation/* meta-distro/recipes-core/images/files/rotation-keys/

# Image recipe includes in postprocess:
do_rootfs_postprocess_append() {
    mkdir -p ${IMAGE_ROOTFS}/boot/loader/keys/rotation
    cp ${THISDIR}/files/rotation-keys/* \
        ${IMAGE_ROOTFS}/boot/loader/keys/rotation/
}
```

## Usage Scenarios

### Scenario 1: Initial Rotation Key Generation

**Context**: Preparing for key transition in 2025

```bash
# 1. Generate rotation keys from production keys
./generate-rotation-keys.sh \
  layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys \
  "7f1b3a4c-5d6e-7f8a-9b0c-1d2e3f4a5b6c"

# 2. Verify output
ls -la rotation/ | wc -l
# Output: 20 files

# 3. Archive for backup
tar czf rotation-keys-backup-2025-01-15.tar.gz rotation/
cp rotation-keys-backup-*.tar.gz /archive/

# 4. Deploy to image build
./layers/meta-distro/files/secureboot/generate-rotation-keys.sh \
  ./layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys

# 5. Build image with rotation keys
bitbake core-image-minimal

# 6. Verify keys in image
wic ls build/tmp/deploy/images/*/core-image-minimal*.wic | grep /boot/loader/keys/rotation
```

### Scenario 2: Re-generating Lost Rotation Keys

**Context**: Need to regenerate if keys were lost/corrupted

```bash
# 1. Verify production keys still accessible
ls -la layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys/

# 2. Regenerate rotation keys
./generate-rotation-keys.sh \
  layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys

# 3. Verify regenerated keys match originals
diff <(openssl x509 -in old-rotation/PK_next.crt -noout -dates) \
     <(openssl x509 -in rotation/PK_next.crt -noout -dates)

# 4. Use for recovery/redistribution
tar czf rotation-keys-recovered-$(date +%Y%m%d).tar.gz rotation/
```

### Scenario 3: Multiple Organizational Units

**Context**: Different departments with separate rotation schedules

```bash
# Generate for department A
./generate-rotation-keys.sh \
  layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys \
  "aaaa1111-bbbb-cccc-dddd-eeee22223333" | tee rotation-dept-a.log

mv rotation rotation-dept-a
mkdir rotation

# Generate for department B
./generate-rotation-keys.sh \
  layers/meta-secure-core/meta-signing-key/files/uefi_sb_keys \
  "bbbb2222-cccc-dddd-eeee-ffff33334444" | tee rotation-dept-b.log

mv rotation rotation-dept-b

# Archive separately
tar czf distro-rotation-keys-dept-a-2025.tar.gz rotation-dept-a/
tar czf distro-rotation-keys-dept-b-2025.tar.gz rotation-dept-b/
```

## Verification & Testing

### Verify Key Generation

```bash
# 1. Check all files created
test -d rotation/ && echo "✓ Output directory created"
test $(ls -1 rotation/ | wc -l) -eq 20 && echo "✓ All 20 files generated"

# 2. Validate certificate format
for cert in rotation/*.crt; do
  openssl x509 -in "$cert" -noout -dates >/dev/null && echo "✓ $(basename $cert)"
done

# 3. Check key strengths
for key in rotation/*.key; do
  openssl rsa -in "$key" -noout -text | grep -q "2048 bit" && echo "✓ $(basename $key)"
done

# 4. Verify EFI formats
for esl in rotation/*.esl; do
  file "$esl" | grep -q "data" && echo "✓ $(basename $esl)"
done

# 5. Verify authenticated variables
for auth in rotation/*.auth; do
  file "$auth" | grep -q "data" && echo "✓ $(basename $auth)"
done
```

### Test in QEMU Environment

```bash
# Build image with rotation keys
bitbake core-image-minimal

# Boot in QEMU with OVMF (UEFI firmware)
runqemu qemux86-64 nographic \
  qemuparams="-global spapr-ovec.ov5-fdt=false -bios /usr/share/OVMF/OVMF_CODE.fd"

# Inside QEMU, verify rotation keys
cat /proc/cmdline | grep -q "loader.keys" && echo "✓ Keys accessible"

# Run rotation script in dry-run mode
/usr/local/sbin/update-uefi-keys.sh --action dry-run
```

### Compare Production and Rotation Keys

```bash
# Show validity periods
echo "Production Keys (current):"
openssl x509 -in /original/path/PK.crt -noout -dates

echo ""
echo "Rotation Keys (next generation):"
openssl x509 -in rotation/PK_next.crt -noout -dates

# Compare validity windows
echo ""
echo "Summary:"
echo "Production: 2017-08-14 to 2027-08-12 (10 years, ~1 year remaining)"
echo "Rotation:   2025-01-15 to 2049-12-31 (25 years, extends support to 2049)"
```

## Security Considerations

### Private Key Protection

```bash
# Rotation key files contain private keys - protect accordingly
chmod 0600 rotation/*.key

# Encrypt for storage
gpg --symmetric --cipher-algo AES256 rotation/PK_next.key
# Enter passphrase (strong, unique, backed-up separately)

# Archive and distribute securely
tar czf distro-rotation-keys-encrypted.tar.gz rotation/
# Transfer via secure channel (TLS, ssh, physical media)
```

### Key Material Handling

1. **Generation**: On secure, isolated system
2. **Storage**: Encrypted, access-controlled location
3. **Distribution**: Signed, verified channels only
4. **Deployment**: Direct from secured image build
5. **Archival**: Encrypted, multiple geographic locations

### Audit Trail

```bash
# Log key generation
./generate-rotation-keys.sh ... 2>&1 | tee rotation-keys-generation-$(date +%Y%m%d-%H%M%S).log

# Archive audit log
tar czf rotation-audit-$(date +%Y%m%d).tar.gz *.log

# Retain for compliance (typically 7 years)
```

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| "openssl: command not found" | Missing OpenSSL | `sudo apt-get install openssl` |
| "cert-to-efi-sig-list: command not found" | Missing efitools | `sudo apt-get install efitools` |
| "No such file or directory" (PK.key) | Wrong path to source keys | Verify path to meta-secure-core keys |
| "Invalid certificate format" | Corrupted source keys | Regenerate from meta-secure-core layer |
| "Permission denied" (writing rotation/) | No write access to output | Use `chmod 755` on script directory |
| "Keys directory already exists" | Output directory exists | Rename or use: `rm -rf rotation/` first |

## Deployment Checklist

- [ ] Tools installed (openssl, efitools)
- [ ] Source keys accessible from meta-secure-core
- [ ] Output directory writable
- [ ] Dry-run completes without errors
- [ ] All 20 files generated
- [ ] Private keys protected (mode 0600)
- [ ] Archive created for distribution
- [ ] Keys validated in test environment
- [ ] Image builds successfully with rotation keys
- [ ] System boots with rotation keys in QEMU
- [ ] Audit log retained
- [ ] Backup of rotation keys created
- [ ] Documentation updated
- [ ] Team trained on rotation procedure

## Next Steps

After generating rotation keys:

1. **Deploy rotation keys to image**: Include in core-image-minimal build
2. **Test deployment**: Run in QEMU with OVMF firmware
3. **Train operators**: Review update-uefi-keys.sh script and procedures
4. **Plan rotation timeline**: Schedule enrollment for 2025-2026
5. **Create runbook**: Document your organization's rotation procedure
6. **Schedule dry-runs**: Test --action dry-run on sample systems
7. **Plan rollout**: Staging (test → pilot → fleet)

## References

- [UEFI Specification](https://uefi.org/sites/default/files/resources/UEFI_Spec_2_9_2021Q1.pdf)
- [efitools Documentation](https://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git)
- [OpenSSL Manual](https://www.openssl.org/docs/)
- [Secure Boot Implementation](https://docs.microsoft.com/en-us/windows-hardware/manufacture/desktop/secure-boot-overview)
- [UEFI Secure Boot Key Rotation Runtime Guide](./UEFI-KEY-ROTATION-RUNTIME.md)

---

**Document Version**: 1.0
**Last Updated**: January 2025
**Applicable Version**: DISTRO with generate-rotation-keys.sh >= 1.0
**Key Rotation Timeline**: Generation complete, enrollment expected 2025-2026
