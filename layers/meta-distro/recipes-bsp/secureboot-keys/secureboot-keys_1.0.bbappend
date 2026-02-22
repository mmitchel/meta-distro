# Deploy Secure Boot Keys to DEPLOYDIR
# Copyright (c) 2026 DISTRO Project
# SPDX-License-Identifier: MIT
#
# This bbappend deploys generated Secure Boot keys to DEPLOYDIR for easy access
# Both current (10-year) and next-generation (25-year) keys are included

do_deploy() {
    # Create deployment directory
    install -d ${DEPLOYDIR}/secureboot-keys

    # Deploy all generated key files from WORKDIR
    # Both current and next-generation keys are available after do_compile
    if [ -f ${WORKDIR}/PK.key ]; then
        # Current keys (PK, KEK, db, dbx - 10-year validity)
        install -m 0600 ${WORKDIR}/PK.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK.auth ${DEPLOYDIR}/secureboot-keys/

        install -m 0600 ${WORKDIR}/KEK.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK.auth ${DEPLOYDIR}/secureboot-keys/

        install -m 0600 ${WORKDIR}/db.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db.auth ${DEPLOYDIR}/secureboot-keys/

        install -m 0600 ${WORKDIR}/dbx.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx.auth ${DEPLOYDIR}/secureboot-keys/

        # Next-generation keys (PK_next, KEK_next, db_next, dbx_next - 25-year validity)
        install -m 0600 ${WORKDIR}/PK_next.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK_next.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK_next.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK_next.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/PK_next.auth ${DEPLOYDIR}/secureboot-keys/

        install -m 0600 ${WORKDIR}/KEK_next.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK_next.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK_next.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK_next.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/KEK_next.auth ${DEPLOYDIR}/secureboot-keys/

        install -m 0600 ${WORKDIR}/db_next.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db_next.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db_next.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db_next.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/db_next.auth ${DEPLOYDIR}/secureboot-keys/

        install -m 0600 ${WORKDIR}/dbx_next.key ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx_next.crt ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx_next.der ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx_next.esl ${DEPLOYDIR}/secureboot-keys/
        install -m 0644 ${WORKDIR}/dbx_next.auth ${DEPLOYDIR}/secureboot-keys/

        # Create README in deployment directory
        cat > ${DEPLOYDIR}/secureboot-keys/README.md << 'EOF'
# Secure Boot Keys - Deployment Package

## Contents

This directory contains 40 generated Secure Boot key files:

### Current Keys (10-year validity)
- **PK files**: Platform Key (self-signed root of trust)
- **KEK files**: Key Exchange Key (signed by PK)
- **db files**: Signature Database (signed by KEK)
- **dbx files**: Forbidden Database (signed by KEK)

### Next-Generation Keys (25-year validity for future rotation)
- **PK_next files**: Platform Key - next generation (self-signed)
- **KEK_next files**: Key Exchange Key - next generation (signed by PK_next)
- **db_next files**: Signature Database - next generation (signed by KEK_next)
- **dbx_next files**: Forbidden Database - next generation (signed by KEK_next)

## File Types

Each key has 5 file formats:
- `.key` - Private key (KEEP SECURE)
- `.crt` - Public certificate (PEM format)
- `.der` - Public certificate (DER format, for UEFI)
- `.esl` - EFI Signature List
- `.auth` - Authenticated variable for UEFI enrollment

## Security Notice

⚠️ **IMPORTANT**: All `.key` files contain private keys and must be kept SECURE.

1. **Do NOT commit** private keys (*.key) to version control
2. **Store securely** in an HSM, Vault, or offline secure location
3. **Restrict access** to authorized personnel only
4. **Backup** private keys to offline secure storage

## Deployment Strategy

### Phase 1 (Years 1-10): Current Keys Active
- Deploy current keys (PK, KEK, db, dbx) to UEFI firmware
- Sign all boot components with KEK
- Store next-gen private keys in secure vault

### Phase 2 (Years 8-12): Transition Period
- Deploy next-gen public keys alongside current keys
- Begin transitioning boot components to KEK_next signatures
- Prepare migration to next-generation keys

### Phase 3 (Years 10+): Next-Gen Keys Active
- Current keys expire after 10 years
- Transition complete to next-gen keys (PK_next, KEK_next, db_next, dbx_next)
- Next-gen keys remain valid for 15+ additional years (25-year total)

## Installation Instructions

### For QEMU Testing
```bash
# Keys are already available in this directory after build
ls -la *.auth  # View authenticated variable files
```

### For Real Hardware
```bash
# Copy public components to /boot/loader/keys/
cp *.crt /boot/loader/keys/
cp *.esl /boot/loader/keys/
cp *.auth /boot/loader/keys/

# Keep private keys in secure location (NOT on target)
# Store *.key files in HSM or offline secure storage
```

### UEFI Firmware Enrollment
```bash
1. Boot into UEFI setup (Press DEL, F2, or manufacturer key during boot)
2. Navigate to: Security → Secure Boot
3. Clear Secure Boot (to allow custom key enrollment)
4. Enroll keys in this order:
   - Platform Key (PK): PK.auth
   - Key Exchange Key: KEK.auth
   - Signature Database: db.auth (may be optional)
   - Forbidden Database: dbx.auth (may be optional)
5. Enable Secure Boot
6. Save and exit
```

## Key Rotation Procedure

When transitioning from current to next-generation keys (around year 8-10):

1. **Prepare next-gen infrastructure**:
   - Access secured next-gen private keys from vault
   - Generate new boot component signatures using KEK_next
   - Update firmware to accept both current and next-gen keys

2. **Deploy transition period**:
   - Install both current and next-gen keys in firmware
   - Boot components signed by both KEK and KEK_next
   - Test thoroughly with next-gen signatures

3. **Transition to next-gen**:
   - After all systems validated, make KEK_next primary
   - Phase out KEK usage gradually
   - Eventually disable KEK when all components migrated

4. **Archive and retire**:
   - Archive current keys (PK, KEK, db, dbx) for historical reference
   - Decommission current keys after expiry (year 10)
   - Next-gen keys become primary with 15+ years validity remaining

## Generated Date

This key package was generated at: $(date -u)

## Support

For questions about Secure Boot key management, see:
- DISTRO Project documentation
- U-Boot Secure Boot documentation: https://docs.u-boot.org/
- UEFI Secure Boot specification: https://uefi.org/

---
Copyright (c) 2026 DISTRO Project
SPDX-License-Identifier: MIT
EOF

        bbnote "Secure Boot keys deployed to ${DEPLOYDIR}/secureboot-keys/"
        bbnote "  Total: 40 files (20 current + 20 next-generation)"
        bbnote "  Current keys: 10-year validity (PK, KEK, db, dbx)"
        bbnote "  Next-gen keys: 25-year validity (PK_next, KEK_next, db_next, dbx_next)"
        bbnote ""
        bbnote "⚠️  SECURITY: Keep all .key files SECURE and out of version control"
        bbnote "Public keys (.crt, .esl, .auth) are safe to distribute"
    else
        bberror "Key files not found in ${WORKDIR}. Check generate-keys.sh output."
    fi
}

addtask deploy after do_compile before do_build

# Ensure files are preserved in DEPLOYDIR
SSTATE_SKIP_CREATION:secureboot-keys = "1"
