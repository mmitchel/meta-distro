# UEFI Secure Boot Key Rotation - Quick Reference Card

## TL;DR - Key Rotation in 3 Steps

```bash
# 1. Validate (no changes made)
sudo /usr/local/sbin/update-uefi-keys.sh --action dry-run

# 2. Rotate (create checkpoint, enroll keys)
sudo /usr/local/sbin/update-uefi-keys.sh --action rotate

# 3. Reboot
sudo reboot

# System boots with new rotation keys. If problems, rollback available.
```

## Quick Command Reference

| Action | Command | Safe? | Changes |
|--------|---------|-------|---------|
| **Test Rotation** | `update-uefi-keys.sh --action dry-run` | ✅ Safe | None |
| **Perform Rotation** | `update-uefi-keys.sh --action rotate` | ⚠️ Risky | Enrolls keys |
| **Rollback Keys** | `update-uefi-keys.sh --action rollback` | ✅ Safe | Restores production |
| **View Audit Log** | `tail -50 /var/log/distro/uefi-key-rotation.log` | ✅ Safe | Read-only |
| **Check UEFI Keys** | `efi-readvar PK; efi-readvar KEK` | ✅ Safe | Read-only |
| **Verbose Mode** | `update-uefi-keys.sh --verbose --action <action>` | ✅ Safe | Debug info |

## Key Locations

```
/boot/loader/keys/production/        ← Current production keys (fallback)
/boot/loader/keys/rotation/          ← Rotation keys (ready to enroll)
/boot/loader/keys/backup/            ← Automatic backups (created during rotation)
/boot/loader/keys/rollback/          ← Rollback checkpoints (auto-created)
/usr/share/distro/keys/production/   ← Emergency fallback (embedded in image)
/var/log/distro/uefi-key-rotation.log ← Audit trail
```
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_KEK/ \
        -keyout KEK.key -out KEK.crt -nodes -days 3650

cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc \
        KEK.crt KEK.esl

# ⚠️ NOTE: Signed with PK, not KEK itself
sign-efi-sig-list -c PK.crt -k PK.key KEK KEK.esl KEK.auth
```

### db (Signature Database)

```bash
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_db/ \
        -keyout db.key -out db.crt -nodes -days 3650

cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc \
        db.crt db.esl

# ⚠️ NOTE: Signed with KEK, not db itself
sign-efi-sig-list -c KEK.crt -k KEK.key db db.esl db.auth
```

### dbx (Forbidden Database)

```bash
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_dbx/ \
        -keyout dbx.key -out dbx.crt -nodes -days 3650

cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc \
        dbx.crt dbx.esl

# ⚠️ NOTE: Signed with KEK, not dbx itself
sign-efi-sig-list -c KEK.crt -k KEK.key dbx dbx.esl dbx.auth
```

## Key Signing Relationships

```
PK.auth
├── Certificate: PK.crt
├── Signed with: PK.key (self-signed)
└── Parent: None (root of trust)

KEK.auth
├── Certificate: KEK.crt (from KEK.esl)
├── Signed with: PK.key (NOT KEK.key)
└── Parent: PK (via PK.key)

db.auth
├── Certificate: db.crt (from db.esl)
├── Signed with: KEK.key (NOT db.key)
└── Parent: KEK (via KEK.key)

dbx.auth
├── Certificate: dbx.crt (from dbx.esl)
├── Signed with: KEK.key (NOT dbx.key)
└── Parent: KEK (via KEK.key)
```

## Critical Sign Command Details

### Parameter Order in sign-efi-sig-list

```bash
sign-efi-sig-list -c <CERT> -k <KEY> <NAME> <INPUT.esl> <OUTPUT.auth>
                     ↑         ↑       ↑      ↑           ↑
                   cert      key    varname  input      output
```

- `-c` flag: Certificate file (.crt) - the public cert of the signer
- `-k` flag: Private key file (.key) - the private key of the signer
- First positional arg: Variable name (PK, KEK, db, dbx)
- Second positional arg: Input EFI Signature List (.esl)
- Third positional arg: Output authenticated variable (.auth)

### Key Point: What Gets Signed

The **.auth file** contains:
1. The EFI Signature List (.esl) from the input
2. A digital signature using the specified key (-k)
3. A timestamp

The signature proves the .esl hasn't been tampered with and was signed by the holder of the private key.

## Security Checklist

- [ ] Keys generated with 2048-bit RSA (or stronger)
- [ ] All *.key files backed up to secure vault
- [ ] *.key files added to .gitignore
- [ ] *.key files have 600 permissions (read-only by owner)
- [ ] .crt and .auth files can be safely committed/deployed
- [ ] PK.auth enrolled first in UEFI
- [ ] KEK.auth enrolled after PK
- [ ] db.auth enrolled after KEK
- [ ] dbx.auth enrolled after db
- [ ] Keys backed up offline

## Deployment

### To Yocto Image

Keys are automatically deployed during build:

```bash
bitbake core-image-minimal
```

Keys deployed to: `/boot/loader/keys/`

### To UEFI Firmware (Manual)

1. Boot to UEFI setup menu
2. Navigate to Security → Secure Boot
3. Set to "Custom" mode
4. Provision keys:
   - Platform Key: **PK.auth**
   - Key Exchange Key: **KEK.auth**
   - Signature Database: **db.auth**
   - Revocation List: **dbx.auth**
5. Enable Secure Boot
6. Save and exit

## Troubleshooting

### Verify .auth File Signature

```bash
# Show contents of .auth file (binary format)
hexdump -C PK.auth | head -20

# Verify certificate in .esl
cert-to-efi-sig-list -l PK.esl
```

### Regenerate Specific Key

```bash
cd layers/meta-distro/files/secureboot

# Remove specific key set
rm -f db.* dbx.*

# Regenerate just db and dbx
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_db/ \
        -keyout db.key -out db.crt -nodes -days 3650
cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc db.crt db.esl
sign-efi-sig-list -c KEK.crt -k KEK.key db db.esl db.auth
```

## Files Included in This Directory

- **generate-keys.sh** - Automated key generation script
- **SECURE-BOOT-KEYS.md** - Full documentation
- **QUICK-REFERENCE.md** - This file
- *.key - Private keys (generated, KEEP SECURE)
- *.crt - Public certificates (generated)
- *.der - DER format certificates (generated)
- *.esl - EFI Signature Lists (generated)
- *.auth - Authenticated variables (generated)

## References

- https://wiki.ubuntu.com/SecurityTeam/SecureBootKeyGeneration
- https://uefi.org/specifications
- https://docs.u-boot.org/en/latest/develop/uefi/uefi.html
