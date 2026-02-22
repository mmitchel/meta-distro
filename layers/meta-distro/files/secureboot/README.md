# Creating Self-Signed UEFI Secure Boot Keys

This guide explains how to generate self-signed UEFI Secure Boot keys that will be stored in the layer and used by systemd-boot.

## Prerequisites

Install required tools on your development machine:

```bash
# Ubuntu/Debian
sudo apt-get install efitools openssl

# Fedora
sudo dnf install efitools openssl
```

## Key Generation

### Step 1: Create Keys Directory

```bash
mkdir -p layers/meta-distro/files/secureboot
cd layers/meta-distro/files/secureboot
```

### Step 2: Set Your GUID

Generate or use a custom GUID for your keys:

```bash
# Generate a random GUID
GUID=$(uuidgen)
echo "Your GUID: ${GUID}"

# Or use a specific GUID
GUID="77fa9abd-0359-4d32-bd60-28f4e78f784b"
```

### Step 3: Generate Platform Key (PK)

The Platform Key is the root of trust:

```bash
# Generate private key and certificate (valid for 10 years)
openssl req -new -x509 -newkey rsa:2048 \
    -subj "/CN=Platform Key/" \
    -keyout PK.key \
    -out PK.crt \
    -days 3650 \
    -nodes \
    -sha256

# Convert to DER format
openssl x509 -in PK.crt -out PK.der -outform DER

# Create EFI Signature List
cert-to-efi-sig-list -g "${GUID}" PK.crt PK.esl

# Create authenticated variable (self-signed)
sign-efi-sig-list -g "${GUID}" -k PK.key -c PK.crt PK PK.esl PK.auth
```

### Step 4: Generate Key Exchange Key (KEK)

```bash
# Generate private key and certificate (valid for 10 years)
openssl req -new -x509 -newkey rsa:2048 \
    -subj "/CN=Key Exchange Key/" \
    -keyout KEK.key \
    -out KEK.crt \
    -days 3650 \
    -nodes \
    -sha256

# Convert to DER format
openssl x509 -in KEK.crt -out KEK.der -outform DER

# Create EFI Signature List
cert-to-efi-sig-list -g "${GUID}" KEK.crt KEK.esl

# Create authenticated variable (signed by PK)
sign-efi-sig-list -g "${GUID}" -k PK.key -c PK.crt KEK KEK.esl KEK.auth
```

### Step 5: Generate Signature Database Key (db)

```bash
# Generate private key and certificate (valid for 10 years)
openssl req -new -x509 -newkey rsa:2048 \
    -subj "/CN=Signature Database/" \
    -keyout db.key \
    -out db.crt \
    -days 3650 \
    -nodes \
    -sha256

# Convert to DER format
openssl x509 -in db.crt -out db.der -outform DER

# Create EFI Signature List
cert-to-efi-sig-list -g "${GUID}" db.crt db.esl

# Create authenticated variable (signed by KEK)
sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt db db.esl db.auth
```

### Step 6: Generate Forbidden Database (dbx)

```bash
# Create empty dbx (revocation list)
touch dbx_hashes.txt

# Try to create EFI signature list and auth from empty file
sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt dbx dbx_hashes.txt dbx.esl 2>/dev/null || {
    # If empty list fails, create minimal dbx structure
    printf '\x26\x16\xc4\xc1\x4c\x50\x92\x40\xac\xa9\x41\xf9\x36\x93\x43\x28' > dbx.esl
    printf '\x1c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >> dbx.esl
}

# Create authenticated variable
sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt dbx dbx.esl dbx.auth
```

### Step 7: Verify Generated Files

```bash
ls -lh
```

You should see:
```
PK.key   PK.crt   PK.der   PK.esl   PK.auth
KEK.key  KEK.crt  KEK.der  KEK.esl  KEK.auth
db.key   db.crt   db.der   db.esl   db.auth
dbx.esl  dbx.auth
```

## Automated Script

For convenience, you can use this automated script:

```bash
#!/bin/bash
# generate-keys.sh - Generate all Secure Boot keys

set -e

GUID="${1:-$(uuidgen)}"

echo "Generating UEFI Secure Boot keys with GUID: ${GUID}"

# Function to generate key
generate_key() {
    local name=$1
    local cn=$2

    echo "Generating ${name}..."
    openssl req -new -x509 -newkey rsa:2048 -subj "/CN=${cn}/" \
        -keyout ${name}.key -out ${name}.crt -days 3650 -nodes -sha256
    openssl x509 -in ${name}.crt -out ${name}.der -outform DER
    cert-to-efi-sig-list -g "${GUID}" ${name}.crt ${name}.esl
}

# Generate keys
generate_key PK "Platform Key"
generate_key KEK "Key Exchange Key"
generate_key db "Signature Database"

# Create authenticated variables
sign-efi-sig-list -g "${GUID}" -k PK.key -c PK.crt PK PK.esl PK.auth
sign-efi-sig-list -g "${GUID}" -k PK.key -c PK.crt KEK KEK.esl KEK.auth
sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt db db.esl db.auth

# Create empty dbx
touch dbx_hashes.txt
sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt dbx dbx_hashes.txt dbx.esl 2>/dev/null || {
    printf '\x26\x16\xc4\xc1\x4c\x50\x92\x40\xac\xa9\x41\xf9\x36\x93\x43\x28' > dbx.esl
    printf '\x1c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >> dbx.esl
}
sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt dbx dbx.esl dbx.auth

echo "Keys generated successfully!"
ls -lh *.key *.crt *.der *.esl *.auth
```

Save as `generate-keys.sh`, make executable, and run:

```bash
chmod +x generate-keys.sh
./generate-keys.sh
```

## Directory Structure

After key generation, your directory should look like:

```
layers/meta-distro/files/secureboot/
├── PK.key      # Platform Key private key
├── PK.crt      # Platform Key certificate
├── PK.der      # Platform Key DER format
├── PK.esl      # Platform Key EFI Signature List
├── PK.auth     # Platform Key authenticated variable
├── KEK.key     # Key Exchange Key private key
├── KEK.crt     # Key Exchange Key certificate
├── KEK.der     # Key Exchange Key DER format
├── KEK.esl     # Key Exchange Key EFI Signature List
├── KEK.auth    # Key Exchange Key authenticated variable
├── db.key      # Signature Database private key
├── db.crt      # Signature Database certificate
├── db.der      # Signature Database DER format
├── db.esl      # Signature Database EFI Signature List
├── db.auth     # Signature Database authenticated variable
├── dbx.esl     # Forbidden Database EFI Signature List
└── dbx.auth    # Forbidden Database authenticated variable
```

## Security Considerations

### Private Keys

**⚠️ CRITICAL SECURITY NOTICE:**

- **Development/Testing**: Private keys (*.key) can be stored in the layer for convenience
- **Production**:
  - NEVER commit private keys to version control
  - Generate keys on a secure, air-gapped system
  - Store private keys in HSM (Hardware Security Module) or secure vault
  - Add `*.key` to `.gitignore`

### Production Recommendations

For production systems:

1. **Generate keys on secure system:**
   ```bash
   # Use secure, offline computer
   ./generate-keys.sh
   ```

2. **Store private keys securely:**
   ```bash
   # Copy private keys to secure storage
   cp *.key /secure/vault/

   # Remove private keys from layer
   rm *.key
   ```

3. **Only include public keys in layer:**
   ```
   layers/meta-distro/files/secureboot/
   ├── PK.crt
   ├── PK.esl
   ├── PK.auth
   ├── KEK.crt
   ├── KEK.esl
   ├── KEK.auth
   ├── db.crt
   ├── db.esl
   ├── db.auth
   ├── dbx.esl
   └── dbx.auth
   ```

4. **Update .gitignore:**
   ```bash
   echo "*.key" >> layers/meta-distro/.gitignore
   echo "*.der" >> layers/meta-distro/.gitignore
   ```

## Using the Keys

Once generated, the keys will be:

1. Copied to the boot partition by the `systemd-bootconf` bbappend
2. Placed in `/boot/loader/keys/` for systemd-boot to access
3. Used to sign the kernel and bootloader during build
4. Available for manual enrollment in UEFI firmware

## Signing Kernel and Bootloader

To sign the kernel and bootloader with your db key, add to `local.conf`:

```bitbake
# Enable signing
UEFI_SB_SIGN_ENABLE = "1"

# Path to db key for signing
UEFI_SB_SIGN_KEY = "${LAYERDIR_meta-distro}/files/secureboot/db.key"
UEFI_SB_SIGN_CERT = "${LAYERDIR_meta-distro}/files/secureboot/db.crt"
```

## Manual Key Enrollment

To manually enroll keys in UEFI firmware:

```bash
# Boot into Linux with mounted EFI partition
mount /dev/disk/by-label/boot /boot

# Enroll keys using efi-updatevar
efi-updatevar -f /boot/loader/keys/PK.auth PK
efi-updatevar -f /boot/loader/keys/KEK.auth KEK
efi-updatevar -f /boot/loader/keys/db.auth db
efi-updatevar -f /boot/loader/keys/dbx.auth dbx

# Enable Secure Boot in UEFI settings
```

## Verification

Verify keys are correctly formatted:

```bash
# Check certificate info
openssl x509 -in PK.crt -text -noout

# Check EFI signature list
hexdump -C PK.esl | head -n 5

# Verify signature on auth file
# (No direct verification tool, but file should be non-empty)
ls -lh *.auth
```

## Troubleshooting

**Error: "cert-to-efi-sig-list: command not found"**
- Install efitools: `sudo apt-get install efitools`

**Error: "sign-efi-sig-list: command not found"**
- Install efitools: `sudo apt-get install efitools`

**Keys not working in UEFI**
- Verify GUID is consistent across all keys
- Check that auth files are signed with correct parent keys
- Ensure certificates are valid (not expired)

## References

- [UEFI Secure Boot Specification](https://uefi.org/specifications)
- [efitools Documentation](https://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git)
- [systemd-boot Secure Boot](https://www.freedesktop.org/software/systemd/man/systemd-boot.html)
