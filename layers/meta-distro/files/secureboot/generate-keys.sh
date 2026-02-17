#!/bin/bash
# Generate UEFI Secure Boot keys for storage in layer
# Usage: ./generate-keys.sh [GUID]

set -e

GUID="${1:-$(uuidgen)}"
VALIDITY_DAYS=3650  # 10 years

echo "=========================================="
echo "Generating UEFI Secure Boot Keys"
echo "=========================================="
echo "GUID: ${GUID}"
echo "Validity: ${VALIDITY_DAYS} days (10 years)"
echo ""

# Function to generate a key pair and certificate
generate_key() {
    local name=$1
    local cn=$2

    echo "Generating ${name} key pair..."

    # Generate RSA private key and self-signed certificate
    openssl req -new -x509 -newkey rsa:2048 \
        -subj "/CN=${cn}/" \
        -keyout ${name}.key \
        -out ${name}.crt \
        -days ${VALIDITY_DAYS} \
        -nodes \
        -sha256

    # Convert certificate to DER format
    openssl x509 -in ${name}.crt -out ${name}.der -outform DER

    # Create EFI Signature List
    cert-to-efi-sig-list -g "${GUID}" ${name}.crt ${name}.esl

    echo "  ✓ ${name} key generated"
}

# Check for required tools
if ! command -v openssl &> /dev/null; then
    echo "Error: openssl not found. Install with: sudo apt-get install openssl"
    exit 1
fi

if ! command -v cert-to-efi-sig-list &> /dev/null; then
    echo "Error: efitools not found. Install with: sudo apt-get install efitools"
    exit 1
fi

if ! command -v uuidgen &> /dev/null && [ -z "$1" ]; then
    echo "Error: uuidgen not found. Please provide a GUID as argument."
    exit 1
fi

# Generate Platform Key (PK)
generate_key PK "Platform Key"

# Generate Key Exchange Key (KEK)
generate_key KEK "Key Exchange Key"

# Generate Signature Database key (db)
generate_key db "Signature Database"

echo ""
echo "Creating authenticated variables..."

# Create authenticated variables (signed with appropriate parent keys)
# PK is self-signed
sign-efi-sig-list -g "${GUID}" -k PK.key -c PK.crt PK PK.esl PK.auth
echo "  ✓ PK.auth created (self-signed)"

# KEK is signed by PK
sign-efi-sig-list -g "${GUID}" -k PK.key -c PK.crt KEK KEK.esl KEK.auth
echo "  ✓ KEK.auth created (signed by PK)"

# db is signed by KEK
sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt db db.esl db.auth
echo "  ✓ db.auth created (signed by KEK)"

# For dbx (revocation list), create an empty list initially
echo ""
echo "Creating empty dbx (revocation list)..."
touch dbx_hashes.txt

# Try to create from empty file
if ! sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt dbx dbx_hashes.txt dbx.esl 2>/dev/null; then
    # Create minimal empty EFI signature list structure
    printf '\x26\x16\xc4\xc1\x4c\x50\x92\x40\xac\xa9\x41\xf9\x36\x93\x43\x28' > dbx.esl
    printf '\x1c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >> dbx.esl
fi

sign-efi-sig-list -g "${GUID}" -k KEK.key -c KEK.crt dbx dbx.esl dbx.auth
echo "  ✓ dbx.auth created (signed by KEK)"

# Cleanup temporary files
rm -f dbx_hashes.txt

echo ""
echo "=========================================="
echo "Secure Boot keys generated successfully!"
echo "=========================================="
echo ""
echo "Generated files:"
ls -lh *.key *.crt *.der *.esl *.auth 2>/dev/null
echo ""
echo "Key Summary:"
echo "  • PK  (Platform Key)        - Root of trust"
echo "  • KEK (Key Exchange Key)    - Signs db/dbx updates"
echo "  • db  (Signature Database)  - Authorizes boot components"
echo "  • dbx (Forbidden Database)  - Revocation list (empty)"
echo ""
echo "Certificate Validity:"
echo "  • Valid for: ${VALIDITY_DAYS} days (10 years from creation date)"
echo "  • Creation date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo "  • Expiration: $(date -u -d "+${VALIDITY_DAYS} days" +"%Y-%m-%d" 2>/dev/null || date -u -v+${VALIDITY_DAYS}d +"%Y-%m-%d" 2>/dev/null || echo "$(date -u +"%Y")+10 years")"
echo ""
echo "⚠️  SECURITY WARNING:"
echo "  • Keep *.key files secure and private!"
echo "  • For production: store private keys in secure vault"
echo "  • Only deploy public keys (*.crt, *.esl, *.auth) to targets"
echo "  • Add *.key to .gitignore before committing"
echo ""
echo "Next steps:"
echo "  1. Review generated keys"
echo "  2. Backup private keys to secure location"
echo "  3. Optionally remove *.key files from this directory"
echo "  4. Build your Yocto image - keys will be included automatically"
echo ""
