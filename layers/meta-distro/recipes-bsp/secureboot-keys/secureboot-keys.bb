SUMMARY = "Generate and install UEFI Secure Boot keys"
DESCRIPTION = "Creates and installs Secure Boot keys (PK, KEK, db, dbx) to /boot partition"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COREBASE}/meta/COPYING.MIT;md5=3da9cfbcab651e8f7761e65559d3f617"

DEPENDS = "openssl-native efitools-native"

inherit deploy

SRC_URI = "file://generate-secureboot-keys.sh"

S = "${WORKDIR}"

KEYDIR = "${WORKDIR}/keys"
GUID ?= "77fa9abd-0359-4d32-bd60-28f4e78f784b"

do_compile() {
    # Create keys directory
    mkdir -p ${KEYDIR}

    # Run key generation script
    cd ${KEYDIR}
    bash ${WORKDIR}/generate-secureboot-keys.sh ${GUID}
}

do_install() {
    # Install keys to /boot/efi/EFI/keys/
    install -d ${D}/boot/efi/EFI/keys

    # Install all generated keys
    install -m 0600 ${KEYDIR}/PK.esl ${D}/boot/efi/EFI/keys/
    install -m 0600 ${KEYDIR}/PK.auth ${D}/boot/efi/EFI/keys/
    install -m 0600 ${KEYDIR}/KEK.esl ${D}/boot/efi/EFI/keys/
    install -m 0600 ${KEYDIR}/KEK.auth ${D}/boot/efi/EFI/keys/
    install -m 0600 ${KEYDIR}/db.esl ${D}/boot/efi/EFI/keys/
    install -m 0600 ${KEYDIR}/db.auth ${D}/boot/efi/EFI/keys/
    install -m 0600 ${KEYDIR}/dbx.esl ${D}/boot/efi/EFI/keys/
    install -m 0600 ${KEYDIR}/dbx.auth ${D}/boot/efi/EFI/keys/

    # Also install certificates for reference
    install -m 0644 ${KEYDIR}/PK.crt ${D}/boot/efi/EFI/keys/
    install -m 0644 ${KEYDIR}/KEK.crt ${D}/boot/efi/EFI/keys/
    install -m 0644 ${KEYDIR}/db.crt ${D}/boot/efi/EFI/keys/

    # Install README
    cat > ${D}/boot/efi/EFI/keys/README.txt << 'EOF'
UEFI Secure Boot Keys
=====================

This directory contains UEFI Secure Boot keys for this system:

Key Hierarchy:
--------------
PK (Platform Key)     - Top-level key, controls KEK updates
KEK (Key Exchange Key)- Second level, controls db/dbx updates
db (Signature DB)     - Authorized signatures for boot components
dbx (Forbidden DB)    - Revoked/forbidden signatures

Files:
------
*.esl  - EFI Signature Lists (for direct UEFI variable updates)
*.auth - Authenticated variables (signed updates)
*.crt  - X.509 certificates (for reference/verification)

Usage:
------
These keys are automatically enrolled during system initialization.
To manually update UEFI Secure Boot variables, use:
  - efi-updatevar for *.auth files
  - chattr to manage immutable attributes

Security:
---------
Keep PK.key and other private keys secure!
Only public keys (*.crt, *.esl) should be deployed to production systems.

Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
GUID: ${GUID}
EOF
}

FILES:${PN} = "/boot/efi/EFI/keys/*"

PACKAGE_ARCH = "${MACHINE_ARCH}"
