# UEFI Secure Boot Key Generation

## Overview

This directory contains scripts and recipes for generating UEFI Secure Boot keys with authenticated variable files (.auth) for the DISTRO Project.

**Status**: ✅ Ready to generate keys

## What Gets Generated

The `generate-keys.sh` script creates four sets of keys following the UEFI Secure Boot standard:

### 1. Platform Key (PK)
- **Role**: Root of trust for Secure Boot
- **Files Generated**:
  - `PK.key` - Private key (KEEP SECURE)
  - `PK.crt` - Public certificate
  - `PK.der` - DER format certificate
  - `PK.esl` - EFI Signature List
  - `PK.auth` - Authenticated variable (self-signed)

### 2. Key Exchange Key (KEK)
- **Role**: Authorizes updates to db and dbx
- **Files Generated**:
  - `KEK.key` - Private key (KEEP SECURE)
  - `KEK.crt` - Public certificate
  - `KEK.der` - DER format certificate
  - `KEK.esl` - EFI Signature List
  - `KEK.auth` - Authenticated variable (signed by PK)

### 3. Signature Database (db)
- **Role**: Authorizes boot components and drivers
- **Files Generated**:
  - `db.key` - Private key (KEEP SECURE)
  - `db.crt` - Public certificate
  - `db.der` - DER format certificate
  - `db.esl` - EFI Signature List
  - `db.auth` - Authenticated variable (signed by KEK)

### 4. Forbidden Database (dbx)
- **Role**: Revocation list for blacklisting components
- **Files Generated**:
  - `dbx.key` - Private key (KEEP SECURE)
  - `dbx.crt` - Public certificate
  - `dbx.der` - DER format certificate
  - `dbx.esl` - EFI Signature List
  - `dbx.auth` - Authenticated variable (signed by KEK)

## Key Hierarchy

```
PK (Platform Key) - Root of Trust
├── Self-signed with PK.key
│   └── Creates: PK.auth
│
└── Signs KEK updates
    └── Creates: KEK.auth (from KEK.esl + PK.crt + PK.key)

KEK (Key Exchange Key)
├── Signed by PK
├── Signs db updates
│   └── Creates: db.auth (from db.esl + KEK.crt + KEK.key)
│
└── Signs dbx updates
    └── Creates: dbx.auth (from dbx.esl + KEK.crt + KEK.key)
```

## Generation Process

### Step 1: Generate Platform Key (PK)

```bash
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_PK/ \
        -keyout PK.key -out PK.crt -nodes -days 3650
cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc \
        PK.crt PK.esl
sign-efi-sig-list -c PK.crt -k PK.key PK PK.esl PK.auth
```

**Output Files**:
- `PK.key`, `PK.crt`, `PK.esl`, `PK.auth`

### Step 2: Generate Key Exchange Key (KEK)

```bash
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_KEK/ \
        -keyout KEK.key -out KEK.crt -nodes -days 3650
cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc \
        KEK.crt KEK.esl
sign-efi-sig-list -c PK.crt -k PK.key KEK KEK.esl KEK.auth
```

**Output Files**:
- `KEK.key`, `KEK.crt`, `KEK.esl`, `KEK.auth`

**Note**: KEK.auth is signed using PK (not KEK itself)

### Step 3: Generate Signature Database (db)

```bash
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_db/ \
        -keyout db.key -out db.crt -nodes -days 3650
cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc \
        db.crt db.esl
sign-efi-sig-list -c KEK.crt -k KEK.key db db.esl db.auth
```

**Output Files**:
- `db.key`, `db.crt`, `db.esl`, `db.auth`

**Note**: db.auth is signed using KEK (not db itself)

### Step 4: Generate Forbidden Database (dbx)

```bash
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_dbx/ \
        -keyout dbx.key -out dbx.crt -nodes -days 3650
cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc \
        dbx.crt dbx.esl
sign-efi-sig-list -c KEK.crt -k KEK.key dbx dbx.esl dbx.auth
```

**Output Files**:
- `dbx.key`, `dbx.crt`, `dbx.esl`, `dbx.auth`

**Note**: dbx.auth is signed using KEK (not dbx itself), initially empty revocation list

## Tool Usage

### cert-to-efi-sig-list

Converts an X.509 certificate to an EFI Signature List (.esl) file:

```bash
cert-to-efi-sig-list -g <GUID> <certificate> <output.esl>
```

**Parameters**:
- `-g <GUID>` - GUID to embed in signature list (default: 11111111-2222-3333-4444-123456789abc)
- `<certificate>` - Input X.509 certificate file (.crt)
- `<output.esl>` - Output EFI Signature List file

**Example**:
```bash
cert-to-efi-sig-list -g 11111111-2222-3333-4444-123456789abc PK.crt PK.esl
```

### sign-efi-sig-list

Creates a signed EFI Signature List (.auth) file that can be enrolled in UEFI firmware:

```bash
sign-efi-sig-list -c <certificate> -k <key> <name> <input.esl> <output.auth>
```

**Parameters**:
- `-c <certificate>` - Signing certificate (.crt)
- `-k <key>` - Signing private key (.key)
- `<name>` - Variable name (PK, KEK, db, dbx)
- `<input.esl>` - Input EFI Signature List (.esl)
- `<output.auth>` - Output authenticated variable file (.auth)

**Example**:
```bash
# Self-sign PK
sign-efi-sig-list -c PK.crt -k PK.key PK PK.esl PK.auth

# Sign KEK with PK
sign-efi-sig-list -c PK.crt -k PK.key KEK KEK.esl KEK.auth

# Sign db with KEK
sign-efi-sig-list -c KEK.crt -k KEK.key db db.esl db.auth

# Sign dbx with KEK
sign-efi-sig-list -c KEK.crt -k KEK.key dbx dbx.esl dbx.auth
```

## Running the Script

### Basic Usage (with default GUID)

```bash
cd layers/meta-distro/files/secureboot
./generate-keys.sh
```

**Default GUID**: 11111111-2222-3333-4444-123456789abc

### Custom GUID

```bash
./generate-keys.sh your-custom-guid-here
```

**Example with specific GUID**:
```bash
./generate-keys.sh 550e8400-e29b-41d4-a716-446655440000
```

## Generated Files Summary

### Total Files Generated

| File Type | Count | Description |
|-----------|-------|-------------|
| Private keys (.key) | 4 | PK.key, KEK.key, db.key, dbx.key |
| Certificates (.crt) | 4 | PK.crt, KEK.crt, db.crt, dbx.crt |
| DER certificates (.der) | 4 | PK.der, KEK.der, db.der, dbx.der |
| EFI Sig Lists (.esl) | 4 | PK.esl, KEK.esl, db.esl, dbx.esl |
| Authenticated vars (.auth) | 4 | PK.auth, KEK.auth, db.auth, dbx.auth |
| **Total** | **20** | All file formats |

### File Organization

```
secureboot/
├── PK.*              # Platform Key (all formats)
├── KEK.*             # Key Exchange Key
├── db.*              # Signature Database
├── dbx.*             # Forbidden Database
├── generate-keys.sh  # Key generation script
└── README.md         # This file
```

## Security Considerations

### ⚠️ Private Key Protection

**CRITICAL**: Private keys (.key files) must be kept secure:

1. **Never commit to version control**:
   ```bash
   echo "*.key" >> .gitignore
   ```

2. **Backup securely**:
   ```bash
   # Backup to offline media or secure vault
   tar czf secureboot-keys-backup.tar.gz *.key
   ```

3. **Restrict file permissions**:
   ```bash
   chmod 600 *.key
   ```

4. **Production deployment**:
   - Store private keys in Hardware Security Module (HSM)
   - Or use secure key management system (HashiCorp Vault, AWS KMS, etc.)
   - Never store private keys on build machines

### Public Component Deployment

Safe to deploy to systems:
- `.crt` files - Public certificates
- `.der` files - DER format certificates
- `.esl` files - EFI Signature Lists
- `.auth` files - Authenticated variables

## Certificate Validity

Default validity: **3650 days (10 years)**

Generated keys are valid for 10 years from creation date. For production systems requiring longer validity, modify the script or regenerate keys as needed.

## UEFI Firmware Enrollment

To enroll these keys in UEFI firmware:

1. **Boot into UEFI Setup**:
   - Restart system
   - Enter UEFI firmware setup (usually DEL, F2, or F10 during POST)

2. **Navigate to Secure Boot**:
   - Security → Secure Boot Configuration

3. **Provision Custom Keys**:
   - Platform Key (PK): Upload **PK.auth**
   - Key Exchange Key (KEK): Upload **KEK.auth**
   - Signature Database (db): Upload **db.auth**
   - Revocation Database (dbx): Upload **dbx.auth**

4. **Enable Secure Boot**:
   - Set Secure Boot to "Custom" mode
   - Save and exit

5. **Boot**:
   - System will verify all boot components against db
   - Only authorized components will execute

## Yocto Integration

Keys are automatically included in the Yocto build:

```bash
cd build
source ../layers/poky/oe-init-build-env
bitbake core-image-minimal
```

Generated keys will be deployed to:
```
/boot/loader/keys/
```

## Testing in QEMU

To test Secure Boot in QEMU with OVMF firmware:

```bash
# Run QEMU with OVMF UEFI firmware
runqemu core-image-minimal ovmf
```

## References

- [UEFI Specification 2.10](https://uefi.org/specifications)
- [Secure Boot](https://en.wikipedia.org/wiki/Unified_Extensible_Firmware_Interface#Secure_Boot)
- [Ubuntu Secure Boot Key Generation](https://wiki.ubuntu.com/SecurityTeam/SecureBootKeyGeneration)
- [efitools Documentation](https://sourceforge.net/p/efitools/)
- [U-Boot UEFI Documentation](https://docs.u-boot.org/en/latest/develop/uefi/uefi.html)

## Troubleshooting

### Error: "cert-to-efi-sig-list: command not found"

Install efitools:
```bash
sudo apt-get install efitools
```

### Error: "openssl: command not found"

Install openssl:
```bash
sudo apt-get install openssl
```

### Error: "sign-efi-sig-list: command not found"

Install efitools (includes sign-efi-sig-list):
```bash
sudo apt-get install efitools
```

### Keys already exist, regenerate?

```bash
# Remove old keys
cd layers/meta-distro/files/secureboot
rm -f *.key *.crt *.der *.esl *.auth

# Regenerate
./generate-keys.sh
```

## FAQ

**Q: How often should keys be rotated?**
A: For development/testing: annually. For production: implement key rotation policy (typically 3-5 years).

**Q: Can I use existing keys?**
A: Yes, if they're in the correct format. Copy them to this directory with the correct naming (PK.*, KEK.*, db.*, dbx.*).

**Q: What if I lose the private keys?**
A: You'll need to regenerate them. Keep secure backups in vault.

**Q: Can I use longer key lengths?**
A: Yes, modify the script to use `-newkey rsa:4096` for 4096-bit keys.

**Q: Is it safe to commit .crt and .auth files?**
A: Yes, only private keys (.key) must be kept secret. Public certificates and auth files can be version controlled.
