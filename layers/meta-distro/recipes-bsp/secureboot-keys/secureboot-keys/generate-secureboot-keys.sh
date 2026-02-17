#!/bin/bash
# Generate UEFI Secure Boot keys (PK, KEK, db, dbx)

set -e

GUID="${1:-77fa9abd-0359-4d32-bd60-28f4e78f784b}"

echo "Generating UEFI Secure Boot keys with GUID: ${GUID}"

# Function to generate a key pair and certificate
generate_key() {
    local name=$1
    local cn=$2

    echo "Generating ${name} key pair..."

    # Generate RSA private key
    openssl req -new -x509 -newkey rsa:2048 -subj "/CN=${cn}/" \
        -keyout ${name}.key -out ${name}.crt -days 3650 -nodes -sha256

    # Convert certificate to DER format
    openssl x509 -in ${name}.crt -out ${name}.der -outform DER

    # Create EFI Signature List
    cert-to-efi-sig-list -g ${GUID} ${name}.crt ${name}.esl

    echo "${name} key generated successfully"
}

# Function to create authenticated variable
create_auth_var() {
    local name=$1
    local signer_key=$2
    local signer_crt=$3

    echo "Creating authenticated variable for ${name}..."

    sign-efi-sig-list -g ${GUID} -k ${signer_key} -c ${signer_crt} \
        ${name} ${name}.esl ${name}.auth

    echo "${name}.auth created"
}

# Generate Platform Key (PK)
generate_key PK "Platform Key"

# Generate Key Exchange Key (KEK)
generate_key KEK "Key Exchange Key"

# Generate Signature Database key (db)
generate_key db "Signature Database"

# For dbx (revocation list), create an empty list initially
echo "Creating empty dbx (revocation list)..."
touch dbx_hashes.txt
sign-efi-sig-list -g ${GUID} -k KEK.key -c KEK.crt dbx dbx_hashes.txt dbx.esl || true
sign-efi-sig-list -g ${GUID} -k KEK.key -c KEK.crt dbx dbx_hashes.txt dbx.auth || true

# If the above fails (empty list), create minimal dbx
if [ ! -f dbx.esl ]; then
    echo "Creating minimal dbx..."
    # Create a minimal empty EFI signature list
    printf '\x26\x16\xc4\xc1\x4c\x50\x92\x40\xac\xa9\x41\xf9\x36\x93\x43\x28' > dbx.esl
    printf '\x1c\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00' >> dbx.esl
    sign-efi-sig-list -g ${GUID} -k KEK.key -c KEK.crt dbx dbx.esl dbx.auth
fi

# Create authenticated variables (signed with appropriate parent keys)
# PK is self-signed
create_auth_var PK PK.key PK.crt

# KEK is signed by PK
create_auth_var KEK PK.key PK.crt

# db is signed by KEK
create_auth_var db KEK.key KEK.crt

echo ""
echo "=========================================="
echo "Secure Boot keys generated successfully!"
echo "=========================================="
echo ""
echo "Generated files:"
ls -lh *.key *.crt *.der *.esl *.auth 2>/dev/null || true
echo ""
echo "IMPORTANT: Keep *.key files secure!"
echo "Only deploy public keys (*.crt, *.esl, *.auth) to target systems."
