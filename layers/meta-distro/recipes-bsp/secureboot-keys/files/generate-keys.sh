#!/bin/bash
# Generate UEFI Secure Boot keys for DISTRO Project
# Creates two sets of keys:
# 1. Current set: PK, KEK, db, dbx (10 years, 3650 days)
# 2. Next set: PK_next, KEK_next, db_next, dbx_next (25 years, 9125 days)
#
# The _next keys are pre-generated for planned key rotation
# Usage: ./generate-keys.sh [GUID]
#
# Reference: https://wiki.ubuntu.com/SecurityTeam/SecureBootKeyGeneration

set -e

GUID="${1:-11111111-2222-3333-4444-123456789abc}"
VALIDITY_CURRENT=3650   # 10 years for current keys
VALIDITY_NEXT=9125      # 25 years for next-generation keys

echo "=========================================="
echo "Generating UEFI Secure Boot Keys (Dual Generation)"
echo "=========================================="
echo "GUID: ${GUID}"
echo ""
echo "Current Keys (for immediate deployment):"
echo "  Validity: ${VALIDITY_CURRENT} days (10 years)"
echo ""
echo "Next-Generation Keys (for future rotation):"
echo "  Validity: ${VALIDITY_NEXT} days (25 years)"
echo ""

# Check for required tools
check_tool() {
    local tool=$1
    local package=$2
    if ! command -v "$tool" &> /dev/null; then
        echo "Error: $tool not found"
        echo "Install with: sudo apt-get install $package"
        exit 1
    fi
}

echo "Checking for required tools..."
check_tool "openssl" "openssl"
check_tool "cert-to-efi-sig-list" "efitools"
check_tool "sign-efi-sig-list" "efitools"
echo "  ✓ All required tools found"
echo ""

# ============================================================================
# Generate Current Platform Key (PK)
# ============================================================================
echo "Generating Current Platform Key (PK)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_PK/ \
    -keyout PK.key -out PK.crt -nodes -days ${VALIDITY_CURRENT}
cert-to-efi-sig-list -g "${GUID}" PK.crt PK.esl
sign-efi-sig-list -c PK.crt -k PK.key PK PK.esl PK.auth
echo "  ✓ PK.auth created (self-signed platform key)"

# ============================================================================
# Generate Next-Generation Platform Key (PK_next)
# ============================================================================
echo "Generating Next-Generation Platform Key (PK_next)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_PK_NEXT/ \
    -keyout PK_next.key -out PK_next.crt -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" PK_next.crt PK_next.esl
sign-efi-sig-list -c PK_next.crt -k PK_next.key PK_next PK_next.esl PK_next.auth
echo "  ✓ PK_next.auth created (future platform key, 25-year validity)"

# ============================================================================
# Generate Current Key Exchange Key (KEK)
# ============================================================================
echo "Generating Current Key Exchange Key (KEK)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_KEK/ \
    -keyout KEK.key -out KEK.crt -nodes -days ${VALIDITY_CURRENT}
cert-to-efi-sig-list -g "${GUID}" KEK.crt KEK.esl
sign-efi-sig-list -c PK.crt -k PK.key KEK KEK.esl KEK.auth
echo "  ✓ KEK.auth created (signed by PK)"

# ============================================================================
# Generate Next-Generation Key Exchange Key (KEK_next)
# ============================================================================
echo "Generating Next-Generation Key Exchange Key (KEK_next)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_KEK_NEXT/ \
    -keyout KEK_next.key -out KEK_next.crt -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" KEK_next.crt KEK_next.esl
sign-efi-sig-list -c PK_next.crt -k PK_next.key KEK_next KEK_next.esl KEK_next.auth
echo "  ✓ KEK_next.auth created (signed by PK_next, 25-year validity)"

# ============================================================================
# Generate Current Signature Database key (db)
# ============================================================================
echo "Generating Current Signature Database key (db)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_db/ \
    -keyout db.key -out db.crt -nodes -days ${VALIDITY_CURRENT}
cert-to-efi-sig-list -g "${GUID}" db.crt db.esl
sign-efi-sig-list -c KEK.crt -k KEK.key db db.esl db.auth
echo "  ✓ db.auth created (signed by KEK)"

# ============================================================================
# Generate Next-Generation Signature Database key (db_next)
# ============================================================================
echo "Generating Next-Generation Signature Database key (db_next)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_db_NEXT/ \
    -keyout db_next.key -out db_next.crt -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" db_next.crt db_next.esl
sign-efi-sig-list -c KEK_next.crt -k KEK_next.key db_next db_next.esl db_next.auth
echo "  ✓ db_next.auth created (signed by KEK_next, 25-year validity)"

# ============================================================================
# Generate Current Forbidden Database key (dbx)
# ============================================================================
echo "Generating Current Forbidden Database (dbx - revocation list)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_dbx/ \
    -keyout dbx.key -out dbx.crt -nodes -days ${VALIDITY_CURRENT}
cert-to-efi-sig-list -g "${GUID}" dbx.crt dbx.esl
sign-efi-sig-list -c KEK.crt -k KEK.key dbx dbx.esl dbx.auth
echo "  ✓ dbx.auth created (signed by KEK, initially empty)"

# ============================================================================
# Generate Next-Generation Forbidden Database key (dbx_next)
# ============================================================================
echo "Generating Next-Generation Forbidden Database (dbx_next)..."
openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=TEST_dbx_NEXT/ \
    -keyout dbx_next.key -out dbx_next.crt -nodes -days ${VALIDITY_NEXT}
cert-to-efi-sig-list -g "${GUID}" dbx_next.crt dbx_next.esl
sign-efi-sig-list -c KEK_next.crt -k KEK_next.key dbx_next dbx_next.esl dbx_next.auth
echo "  ✓ dbx_next.auth created (signed by KEK_next, 25-year validity)"

# ============================================================================
# Additional key formats for deployment
# ============================================================================
echo ""
echo "Converting current certificates to DER format..."
for key in PK KEK db dbx; do
    openssl x509 -in ${key}.crt -out ${key}.der -outform DER
done
echo "  ✓ DER format certificates created (current)"

echo ""
echo "Converting next-generation certificates to DER format..."
for key in PK_next KEK_next db_next dbx_next; do
    openssl x509 -in ${key}.crt -out ${key}.der -outform DER
done
echo "  ✓ DER format certificates created (next-generation)"

echo ""
echo "=========================================="
echo "Secure Boot keys generated successfully!"
echo "=========================================="
echo ""
echo "Generated file count:"
TOTAL_FILES=$(find . -maxdepth 1 \( -name '*.key' -o -name '*.crt' -o -name '*.der' -o -name '*.esl' -o -name '*.auth' \) | wc -l)
echo "  Total: ${TOTAL_FILES} files (current + next-generation)"
echo ""

echo "Generated files:"
echo "  Current Set (10-year validity):"
ls -lh PK.* KEK.* db.* dbx.* 2>/dev/null | grep -E '\.(key|crt|der|esl|auth)$' || echo "    (none yet)"
echo ""
echo "  Next-Generation Set (25-year validity):"
ls -lh PK_next.* KEK_next.* db_next.* dbx_next.* 2>/dev/null | grep -E '\.(key|crt|der|esl|auth)$' || echo "    (none yet)"
echo ""

echo "Key Hierarchy (Current):"
echo "  PK (Platform Key)"
echo "  ├── Root of trust"
echo "  ├── Self-signed"
echo "  └── Signs KEK, db, dbx changes"
echo ""
echo "  KEK (Key Exchange Key)"
echo "  ├── Signed by PK"
echo "  └── Authorizes updates to db/dbx"
echo ""
echo "  db (Signature Database)"
echo "  ├── Signed by KEK"
echo "  └── Authorized boot components/drivers"
echo ""
echo "  dbx (Forbidden Database)"
echo "  ├── Signed by KEK"
echo "  └── Revocation list (empty initially)"
echo ""

echo "Certificate Validity:"
echo "  Current Set:"
echo "    • Valid for: ${VALIDITY_CURRENT} days (10 years from creation date)"
echo "    • Keys: PK, KEK, db, dbx"
echo "  Next-Generation Set (for future key rotation):"
echo "    • Valid for: ${VALIDITY_NEXT} days (25 years from creation date)"
echo "    • Keys: PK_next, KEK_next, db_next, dbx_next"
echo "  • Creation date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
echo ""

echo "Authenticated Variable Files (.auth) - Current Set:"
echo "  • PK.auth  - Platform Key (self-signed)"
echo "  • KEK.auth - Key Exchange Key (signed by PK)"
echo "  • db.auth  - Signature Database (signed by KEK)"
echo "  • dbx.auth - Forbidden Database (signed by KEK)"
echo ""

echo "Authenticated Variable Files (.auth) - Next-Generation Set:"
echo "  • PK_next.auth  - Platform Key (self-signed, valid 25 years)"
echo "  • KEK_next.auth - Key Exchange Key (signed by PK_next, valid 25 years)"
echo "  • db_next.auth  - Signature Database (signed by KEK_next, valid 25 years)"
echo "  • dbx_next.auth - Forbidden Database (signed by KEK_next, valid 25 years)"
echo ""

echo "File Structure:"
echo "  .key   - Private keys (KEEP SECURE)"
echo "  .crt   - Public certificates"
echo "  .der   - DER format certificates"
echo "  .esl   - EFI Signature Lists"
echo "  .auth  - Authenticated variables for UEFI"
echo ""

echo "⚠️  SECURITY WARNINGS:"
echo "  • Keep ALL *.key files SECURE - these are private keys!"
echo "  • Add *.key to .gitignore BEFORE committing"
echo "  • For production: store private keys in secure vault (HSM, Vault, etc.)"
echo "  • Only deploy public components (*.crt, *.esl, *.auth) to targets"
echo "  • Backup private keys to offline secure storage"
echo ""

echo "Key Rotation Strategy:"
echo "  Phase 1 (Years 1-10): Use current keys (PK, KEK, db, dbx)"
echo "    • These keys sign all boot components during this period"
echo "    • Validity: 10 years (${VALIDITY_CURRENT} days)"
echo ""
echo "  Phase 2 (Years 8-12): Transition period"
echo "    • Generate next-generation keys (PK_next, KEK_next, db_next, dbx_next)"
echo "    • Deploy next-gen keys alongside current keys in firmware"
echo "    • Transition boot components to be signed by KEK_next"
echo "    • Next-gen keys signed to ensure smooth transition"
echo ""
echo "  Phase 3 (Years 10+): Legacy key rotation"
echo "    • Current keys (PK, KEK, db, dbx) expire after 10 years"
echo "    • Next-gen keys (PK_next, KEK_next, db_next, dbx_next) remain valid (25 years)"
echo "    • Next-gen keys can be used for 15+ additional years"
echo ""

echo "Deployment Instructions:"
echo ""
echo "  1. To enroll current keys in UEFI firmware:"
echo "     • Boot into UEFI setup"
echo "     • Navigate to: Security → Secure Boot"
echo "     • Provision custom keys:"
echo "       - Platform Key (PK): PK.auth"
echo "       - Key Exchange Key: KEK.auth"
echo "       - Signature Database: db.auth"
echo "       - Revocation Database: dbx.auth"
echo ""
echo "  2. To prepare for future key rotation:"
echo "     • Store next-generation keys securely:"
echo "       - PK_next.auth, KEK_next.auth, db_next.auth, dbx_next.auth"
echo "     • Keep private keys in secure vault (PK_next.key, KEK_next.key, etc.)"
echo "     • Document rotation timeline in security procedures"
echo ""
echo "  3. To deploy to target system:"
echo "     • Copy public files (.crt, .esl, .auth) to /boot/loader/keys/"
echo "     • Include both current and next-gen public keys:"
echo "       - Current: PK.*, KEK.*, db.*, dbx.*"
echo "       - Next-Gen: PK_next.*, KEK_next.*, db_next.*, dbx_next.*"
echo "     • Keep all .key files in secure vault only"
echo ""
echo "  4. For Yocto build:"
echo "     • Keys are automatically included in meta-distro layer"
echo "     • Both current and next-gen keys are deployed to:"
echo "       - /boot/loader/keys/ (all public files)"
echo "       - builddir/deploy/images/<machine>/ (for reference)"
echo "     • Deploy u-boot with EFI_SECURE_BOOT=y configuration"
echo ""

echo "Next Steps:"
echo "  1. ✓ Review and verify all 40 key files (20 current + 20 next-gen)"
echo "  2. ✓ Backup private keys (*.key) to secure location"
echo "  3. ✓ Add *.key files to .gitignore"
echo "  4. ✓ Store next-generation keys in secure vault for future use"
echo "  5. ✓ Build Yocto image - keys will be deployed automatically"
echo "  6. ✓ Boot in QEMU or on real hardware with Secure Boot enabled"
echo ""
