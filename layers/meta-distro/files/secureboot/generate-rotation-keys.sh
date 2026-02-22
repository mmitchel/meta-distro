#!/bin/bash
# Generate UEFI Secure Boot Rotation Keys for DISTRO Project
#
# This script creates rotation-capable keys based on existing production keys
# from meta-secure-core/meta-signing-key/files/uefi_sb_keys/
#
# Approach:
#   1. Use existing keys (PK, KEK, DB, DBX) as the current/production set
#   2. Generate new _next keys with extended validity (25 years)
#   3. Create authenticated variables (.auth files) for smooth key rotation
#   4. Maintain signing hierarchy: _next keys signed by corresponding _next parents
#
# Usage: ./generate-rotation-keys.sh [SOURCE_KEYS_DIR] [GUID]
#
# References:
#   - UEFI Secure Boot: https://uefi.org/
#   - Key Rotation: https://docs.u-boot.org/en/latest/develop/uefi/uefi.html

set -e

# Configuration
SOURCE_KEYS_DIR="${1:-.}"
GUID="${2:-11111111-2222-3333-4444-123456789abc}"
VALIDITY_NEXT=9125      # 25 years for rotation keys

# Script directory and paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CURRENT_KEYS_DIR="${SCRIPT_DIR}"

echo "=========================================="
echo "Generating UEFI Secure Boot Rotation Keys"
echo "=========================================="
echo ""
echo "Configuration:"
echo "  Source keys (production):  ${SOURCE_KEYS_DIR}"
echo "  Output directory:          ${CURRENT_KEYS_DIR}"
echo "  Rotation key validity:     ${VALIDITY_NEXT} days (25 years)"
echo "  GUID:                      ${GUID}"
echo ""

# ============================================================================
# Utility Functions
# ============================================================================

check_tool() {
    local tool=$1
    local package=$2
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool not found"
        echo "Install with: sudo apt-get install $package"
        exit 1
    fi
}

check_key_file() {
    local file=$1
    local description=$2
    if [[ ! -f "$file" ]]; then
        echo "Error: $description not found at $file"
        exit 1
    fi
}

log_step() {
    echo "  ✓ $1"
}

log_error() {
    echo "  ✗ $1" >&2
}

# ============================================================================
# Validation Phase
# ============================================================================

echo "Validating environment..."

# Check for required tools
check_tool "openssl" "openssl"
check_tool "cert-to-efi-sig-list" "efitools"
check_tool "sign-efi-sig-list" "efitools"
log_step "All required tools found"

# Check for production keys
echo ""
echo "Verifying production keys from meta-secure-core..."
if [[ "$SOURCE_KEYS_DIR" != "." ]]; then
    check_key_file "${SOURCE_KEYS_DIR}/PK.key" "PK private key"
    check_key_file "${SOURCE_KEYS_DIR}/PK.crt" "PK certificate"
    check_key_file "${SOURCE_KEYS_DIR}/KEK.key" "KEK private key"
    check_key_file "${SOURCE_KEYS_DIR}/KEK.crt" "KEK certificate"
    check_key_file "${SOURCE_KEYS_DIR}/DB.key" "DB private key"
    check_key_file "${SOURCE_KEYS_DIR}/DB.crt" "DB certificate"
    check_key_file "${SOURCE_KEYS_DIR}/DBX/DBX.key" "DBX private key"
    check_key_file "${SOURCE_KEYS_DIR}/DBX/DBX.crt" "DBX certificate"
    log_step "All production keys found"
fi

# Ensure output directory exists
mkdir -p "${CURRENT_KEYS_DIR}"

echo ""

# ============================================================================
# Key Generation Phase - Rotation Keys (25-year validity)
# ============================================================================

echo "Generating rotation-capable keys (_next variants)..."
echo ""

# PK_next: New Platform Key (self-signed, for future rotation)
echo "  Generating PK_next (rotation platform key)..."
openssl req -x509 -sha256 -newkey rsa:2048 \
    -subj "/CN=DISTRO Rotation PK/" \
    -keyout "${CURRENT_KEYS_DIR}/PK_next.key" \
    -out "${CURRENT_KEYS_DIR}/PK_next.crt" \
    -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" \
    "${CURRENT_KEYS_DIR}/PK_next.crt" \
    "${CURRENT_KEYS_DIR}/PK_next.esl"
sign-efi-sig-list -c "${CURRENT_KEYS_DIR}/PK_next.crt" \
    -k "${CURRENT_KEYS_DIR}/PK_next.key" \
    PK_next \
    "${CURRENT_KEYS_DIR}/PK_next.esl" \
    "${CURRENT_KEYS_DIR}/PK_next.auth"
log_step "PK_next.auth created (self-signed, rotation platform key, 25-year validity)"

# KEK_next: New Key Exchange Key (signed by PK_next)
echo "  Generating KEK_next (rotation key exchange key)..."
openssl req -x509 -sha256 -newkey rsa:2048 \
    -subj "/CN=DISTRO Rotation KEK/" \
    -keyout "${CURRENT_KEYS_DIR}/KEK_next.key" \
    -out "${CURRENT_KEYS_DIR}/KEK_next.crt" \
    -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" \
    "${CURRENT_KEYS_DIR}/KEK_next.crt" \
    "${CURRENT_KEYS_DIR}/KEK_next.esl"
sign-efi-sig-list -c "${CURRENT_KEYS_DIR}/PK_next.crt" \
    -k "${CURRENT_KEYS_DIR}/PK_next.key" \
    KEK_next \
    "${CURRENT_KEYS_DIR}/KEK_next.esl" \
    "${CURRENT_KEYS_DIR}/KEK_next.auth"
log_step "KEK_next.auth created (signed by PK_next, rotation key exchange, 25-year validity)"

# db_next: New Signature Database (signed by KEK_next)
echo "  Generating db_next (rotation signature database)..."
openssl req -x509 -sha256 -newkey rsa:2048 \
    -subj "/CN=DISTRO Rotation DB/" \
    -keyout "${CURRENT_KEYS_DIR}/db_next.key" \
    -out "${CURRENT_KEYS_DIR}/db_next.crt" \
    -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" \
    "${CURRENT_KEYS_DIR}/db_next.crt" \
    "${CURRENT_KEYS_DIR}/db_next.esl"
sign-efi-sig-list -c "${CURRENT_KEYS_DIR}/KEK_next.crt" \
    -k "${CURRENT_KEYS_DIR}/KEK_next.key" \
    db_next \
    "${CURRENT_KEYS_DIR}/db_next.esl" \
    "${CURRENT_KEYS_DIR}/db_next.auth"
log_step "db_next.auth created (signed by KEK_next, rotation signature database, 25-year validity)"

# dbx_next: New Forbidden Database (signed by KEK_next)
echo "  Generating dbx_next (rotation forbidden database)..."
openssl req -x509 -sha256 -newkey rsa:2048 \
    -subj "/CN=DISTRO Rotation DBX/" \
    -keyout "${CURRENT_KEYS_DIR}/dbx_next.key" \
    -out "${CURRENT_KEYS_DIR}/dbx_next.crt" \
    -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" \
    "${CURRENT_KEYS_DIR}/dbx_next.crt" \
    "${CURRENT_KEYS_DIR}/dbx_next.esl"
sign-efi-sig-list -c "${CURRENT_KEYS_DIR}/KEK_next.crt" \
    -k "${CURRENT_KEYS_DIR}/KEK_next.key" \
    dbx_next \
    "${CURRENT_KEYS_DIR}/dbx_next.esl" \
    "${CURRENT_KEYS_DIR}/dbx_next.auth"
log_step "dbx_next.auth created (signed by KEK_next, rotation revocation database, 25-year validity)"

# ============================================================================
# DER Format Conversion (for UEFI firmware)
# ============================================================================

echo ""
echo "Converting certificates to DER format (for UEFI firmware)..."

for key in PK_next KEK_next db_next dbx_next; do
    if [[ -f "${CURRENT_KEYS_DIR}/${key}.crt" ]]; then
        openssl x509 -in "${CURRENT_KEYS_DIR}/${key}.crt" \
            -out "${CURRENT_KEYS_DIR}/${key}.der" \
            -outform DER
        log_step "${key}.der created"
    fi
done

# ============================================================================
# Summary and Output
# ============================================================================

echo ""
echo "=========================================="
echo "Key Rotation Generation Complete!"
echo "=========================================="
echo ""

echo "Generated Files:"
echo "  Rotation Keys (25-year validity):"
ls -lh "${CURRENT_KEYS_DIR}"/PK_next.* 2>/dev/null | grep -E '\.(key|crt|der|esl|auth)$' | awk '{print "    " $9}'
ls -lh "${CURRENT_KEYS_DIR}"/KEK_next.* 2>/dev/null | grep -E '\.(key|crt|der|esl|auth)$' | awk '{print "    " $9}'
ls -lh "${CURRENT_KEYS_DIR}"/db_next.* 2>/dev/null | grep -E '\.(key|crt|der|esl|auth)$' | awk '{print "    " $9}'
ls -lh "${CURRENT_KEYS_DIR}"/dbx_next.* 2>/dev/null | grep -E '\.(key|crt|der|esl|auth)$' | awk '{print "    " $9}'

echo ""
echo "Key Rotation Architecture:"
echo "  Production Keys (from meta-secure-core):"
echo "    PK   (Platform Key) - Root of trust, active deployment"
echo "    KEK  (Key Exchange Key) - Signed by PK"
echo "    DB   (Signature Database) - Signed by KEK"
echo "    DBX  (Forbidden Database) - Signed by KEK"
echo ""
echo "  Rotation Keys (generated, 25-year validity):"
echo "    PK_next   (New Platform Key) - Self-signed, future root"
echo "    KEK_next  (New KEK) - Signed by PK_next"
echo "    db_next   (New Signature DB) - Signed by KEK_next"
echo "    dbx_next  (New Forbidden DB) - Signed by KEK_next"
echo ""

echo "Key Rotation Timeline:"
echo "  Current: Production keys (PK, KEK, DB, DBX) active"
echo "  Phase 1: Both key sets available in firmware (8-10 years)"
echo "  Phase 2: Transition boot components to rotation keys"
echo "  Phase 3: Rotation keys become primary (years 10-25+)"
echo ""

echo "Deployment Instructions:"
echo "  1. Store private keys securely:"
echo "     - PK_next.key, KEK_next.key, db_next.key, dbx_next.key"
echo "     - Keep in secure vault (HSM, Vault, offline storage)"
echo ""
echo "  2. Deploy public components to target:"
echo "     - Copy *.crt, *.esl, *.auth files to /boot/loader/keys/"
echo ""
echo "  3. At rotation time (8-10 years):"
echo "     - Use update-uefi-keys.sh to transition to rotation keys"
echo "     - Maintain rollback capability to production keys"
echo ""

echo "⚠️  SECURITY WARNINGS:"
echo "  • Keep ALL private keys (*.key) SECURE"
echo "  • Never commit *.key files to version control"
echo "  • Store rotation keys in secure vault until needed"
echo "  • Backup keys to offline secure storage"
echo ""

echo "Rotation Support Script:"
echo "  Location: /opt/distro/update-uefi-keys.sh (in image)"
echo "  Purpose:  Update UEFI keys at runtime with exception handling"
echo "  Features: - Validates new keys before enrollment"
echo "           - Creates rollback checkpoint"
echo "           - Automatic rollback on failure"
echo "           - Detailed audit logging"
echo ""
