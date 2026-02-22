# Secure Boot Key Generation Recipe for DISTRO Project
# Copyright (c) 2026 DISTRO Project
# SPDX-License-Identifier: MIT
#
# This recipe generates UEFI Secure Boot keys with dual-generation support:
#   - Current set: PK, KEK, db, dbx (10-year validity)
#   - Next-generation set: PK_next, KEK_next, db_next, dbx_next (25-year validity for future rotation)
#
# All keys include authenticated variable files (.auth) for Secure Boot enrollment
# Keys are generated at build-time and deployed to DEPLOYDIR

SUMMARY = "Generate UEFI Secure Boot keys with dual-generation support for key rotation"
DESCRIPTION = "Creates two generations of UEFI Secure Boot keys: \
Current (PK, KEK, db, dbx - 10-year validity) and \
Next-generation (PK_next, KEK_next, db_next, dbx_next - 25-year validity) \
with authenticated variable files (.auth) for Secure Boot enrollment and future key rotation"
AUTHOR = "DISTRO Project"
LICENSE = "MIT"

SRC_URI = "file://generate-keys.sh"

DEPENDS = "efitools-native openssl-native"

PACKAGE_ARCH = "${BUILD_ARCH}"

inherit native

# GUID for EFI Signature Lists
SB_GUID ?= "11111111-2222-3333-4444-123456789abc"

# Certificate validity periods (in days)
# Current keys validity: 10 years
SB_VALIDITY_CURRENT ?= "3650"
# Next-generation keys validity: 25 years
SB_VALIDITY_NEXT ?= "9125"

# Path to store generated keys
SB_KEYS_DIR = "${TOPDIR}/../layers/meta-distro/files/secureboot"

do_compile() {
    cd ${WORKDIR}
    bash generate-keys.sh "${SB_GUID}"
}

do_install() {
    install -d ${D}${bindir}
    install -m 0755 ${WORKDIR}/generate-keys.sh ${D}${bindir}/generate-secure-boot-keys

    # Note: Keys are generated in workdir during compile
    # They will be deployed by the bbappend recipe to DEPLOYDIR
}

# ============================================================================
# Generated Files Reference
# ============================================================================
#
# CURRENT SET (10-year validity):
#
# Private Keys (KEEP SECURE):
#   - PK.key     - Platform Key private key
#   - KEK.key    - Key Exchange Key private key
#   - db.key     - Signature Database private key
#   - dbx.key    - Forbidden Database private key
#
# Public Certificates:
#   - PK.crt     - Platform Key certificate
#   - KEK.crt    - Key Exchange Key certificate
#   - db.crt     - Signature Database certificate
#   - dbx.crt    - Forbidden Database certificate
#
# DER Format (for UEFI):
#   - PK.der     - Platform Key certificate (DER)
#   - KEK.der    - Key Exchange Key certificate (DER)
#   - db.der     - Signature Database certificate (DER)
#   - dbx.der    - Forbidden Database certificate (DER)
#
# EFI Signature Lists:
#   - PK.esl     - Platform Key signature list
#   - KEK.esl    - Key Exchange Key signature list
#   - db.esl     - Signature Database signature list
#   - dbx.esl    - Forbidden Database signature list
#
# Authenticated Variables (.auth files):
#   - PK.auth    - Platform Key (self-signed)
#   - KEK.auth   - Key Exchange Key (signed by PK)
#   - db.auth    - Signature Database (signed by KEK)
#   - dbx.auth   - Forbidden Database (signed by KEK)
#
# ============================================================================
# NEXT-GENERATION SET (25-year validity for future key rotation):
#
# Private Keys (KEEP SECURE):
#   - PK_next.key     - Platform Key (next-generation) private key
#   - KEK_next.key    - Key Exchange Key (next-generation) private key
#   - db_next.key     - Signature Database (next-generation) private key
#   - dbx_next.key    - Forbidden Database (next-generation) private key
#
# Public Certificates:
#   - PK_next.crt     - Platform Key (next-generation) certificate
#   - KEK_next.crt    - Key Exchange Key (next-generation) certificate
#   - db_next.crt     - Signature Database (next-generation) certificate
#   - dbx_next.crt    - Forbidden Database (next-generation) certificate
#
# DER Format (for UEFI):
#   - PK_next.der     - Platform Key (next-generation) certificate (DER)
#   - KEK_next.der    - Key Exchange Key (next-generation) certificate (DER)
#   - db_next.der     - Signature Database (next-generation) certificate (DER)
#   - dbx_next.der    - Forbidden Database (next-generation) certificate (DER)
#
# EFI Signature Lists:
#   - PK_next.esl     - Platform Key (next-generation) signature list
#   - KEK_next.esl    - Key Exchange Key (next-generation) signature list
#   - db_next.esl     - Signature Database (next-generation) signature list
#   - dbx_next.esl    - Forbidden Database (next-generation) signature list
#
# Authenticated Variables (.auth files):
#   - PK_next.auth    - Platform Key (next-generation, self-signed)
#   - KEK_next.auth   - Key Exchange Key (next-generation, signed by PK_next)
#   - db_next.auth    - Signature Database (next-generation, signed by KEK_next)
#   - dbx_next.auth   - Forbidden Database (next-generation, signed by KEK_next)
#
# ============================================================================
# Key Hierarchy
# ============================================================================
#
# CURRENT KEYS (10 years):
#   PK (Platform Key) - Root of trust
#   ├── Self-signed with PK.key
#   └── Signs KEK.esl → KEK.auth
#
#   KEK (Key Exchange Key)
#   ├── Signed by PK
#   ├── Signs db.esl → db.auth
#   └── Signs dbx.esl → dbx.auth
#
#   db (Signature Database)
#   ├── Signed by KEK
#   └── Authorizes boot components
#
#   dbx (Forbidden Database)
#   ├── Signed by KEK
#   └── Revocation list (initially empty)
#
# NEXT-GENERATION KEYS (25 years - for future use):
#   PK_next (Platform Key) - Root of trust for next generation
#   ├── Self-signed with PK_next.key
#   └── Signs KEK_next.esl → KEK_next.auth
#
#   KEK_next (Key Exchange Key)
#   ├── Signed by PK_next
#   ├── Signs db_next.esl → db_next.auth
#   └── Signs dbx_next.esl → dbx_next.auth
#
#   db_next (Signature Database)
#   ├── Signed by KEK_next
#   └── Authorizes boot components (next generation)
#
#   dbx_next (Forbidden Database)
#   ├── Signed by KEK_next
#   └── Revocation list (next generation, initially empty)
#
# ============================================================================
# Key Rotation Timeline
# ============================================================================
#
# Phase 1 (Years 1-10):
#   - Use current keys (PK, KEK, db, dbx)
#   - All boot components signed with KEK
#   - Validity: 10 years (${SB_VALIDITY_CURRENT} days)
#
# Phase 2 (Years 8-12) - Transition Period:
#   - Generate next-generation keys (PK_next, KEK_next, db_next, dbx_next)
#   - Deploy next-gen keys alongside current keys
#   - Prepare boot components for transition to KEK_next
#   - Next-gen keys valid for 25 years from generation
#
# Phase 3 (Years 10+) - Full Migration:
#   - Current keys (PK, KEK, db, dbx) expire after 10 years
#   - Next-gen keys (PK_next, KEK_next, db_next, dbx_next) fully active
#   - All new boot components signed by KEK_next
#   - Next-gen keys remain valid for 15+ additional years (25-year total validity)
#
# ============================================================================
# Deployment Strategy
# ============================================================================
#
# All generated keys (40 total: 20 current + 20 next-gen) are available in:
#   1. WORKDIR during build: ${WORKDIR}/{*.key,*.crt,*.der,*.esl,*.auth}
#   2. DEPLOYDIR after build: ${DEPLOYDIR}/{*.key,*.crt,*.der,*.esl,*.auth}
#   3. Image installation: /boot/loader/keys/{*.crt,*.der,*.esl,*.auth}
#
# File distribution:
#   - Private keys (*.key): Keep in secure vault, do NOT deploy to target
#   - Public certificates (*.crt): Deploy to target for reference
#   - DER format (*.der): Use in UEFI firmware updates
#   - Signature Lists (*.esl): Use with sign-efi-sig-list tool
#   - Authenticated variables (*.auth): Deploy to target and use for UEFI enrollment
#
# ============================================================================
# Tool Commands Used
# ============================================================================
#
# Generation follows the pattern:
#
# 1. Create key pair and certificate:
#    openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=<name>/ \
#            -keyout <name>.key -out <name>.crt -nodes -days <validity>
#
# 2. Convert to EFI Signature List:
#    cert-to-efi-sig-list -g <GUID> <name>.crt <name>.esl
#
# 3. Create authenticated variable:
#    sign-efi-sig-list -c <cert> -k <key> <name> <name>.esl <name>.auth
#
# Current Keys Signing Hierarchy:
#   - PK.auth:   signed with PK.crt and PK.key
#   - KEK.auth:  signed with PK.crt and PK.key
#   - db.auth:   signed with KEK.crt and KEK.key
#   - dbx.auth:  signed with KEK.crt and KEK.key
#
# Next-Generation Keys Signing Hierarchy:
#   - PK_next.auth:    signed with PK_next.crt and PK_next.key
#   - KEK_next.auth:   signed with PK_next.crt and PK_next.key
#   - db_next.auth:    signed with KEK_next.crt and KEK_next.key
#   - dbx_next.auth:   signed with KEK_next.crt and KEK_next.key

# ============================================================================
# Tool Commands Used
# ============================================================================
#
# Generation follows the pattern:
#
# 1. Create key pair and certificate:
#    openssl req -x509 -sha256 -newkey rsa:2048 -subj /CN=<name>/ \
#            -keyout <name>.key -out <name>.crt -nodes -days 3650
#
# 2. Convert to EFI Signature List:
#    cert-to-efi-sig-list -g <GUID> <name>.crt <name>.esl
#
# 3. Create authenticated variable:
#    sign-efi-sig-list -c <cert> -k <key> <name> <name>.esl <name>.auth
#
# Signing hierarchy:
#   - PK.auth:   signed with PK.crt and PK.key
#   - KEK.auth:  signed with PK.crt and PK.key
#   - db.auth:   signed with KEK.crt and KEK.key
#   - dbx.auth:  signed with KEK.crt and KEK.key
