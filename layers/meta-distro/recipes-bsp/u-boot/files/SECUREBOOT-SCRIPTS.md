# u-boot Secure Boot State Checking Scripts

This directory contains u-boot boot scripts and environment configurations for checking the EFI Secure Boot state during system boot.

## Overview

These scripts provide comprehensive tools for diagnosing and verifying the Secure Boot configuration on systems running u-boot with EFI/UEFI firmware.

## Files

### 1. `check-secureboot.txt` (Primary Script)
**Type:** u-boot boot script source (text format)

**Purpose:** Interactive script to check EFI Secure Boot state with detailed diagnostics

**Contents:**
- Checks if SecureBoot EFI variable is present
- Queries Platform Key (PK), Key Exchange Key (KEK), db, and dbx
- Displays comprehensive Secure Boot status
- Shows warnings if keys are not configured

**Usage:**
```bash
# Compile to binary boot script:
mkimage -T script -C none -n "check-secureboot" \
  -d check-secureboot.txt -o check-secureboot.scr

# Run in u-boot:
fatload mmc 0:1 ${scriptaddr} check-secureboot.scr
source ${scriptaddr}
```

**Output Example:**
```
==========================================
EFI Secure Boot State Check Script
==========================================

✓ EFI SecureBoot variable found
✓ SecureBoot variable is present and readable

--- Platform Key Status ---
✓ Platform Key (PK) is set
  Secure Boot capable: YES

--- Key Exchange Key Status ---
✓ Key Exchange Key (KEK) is set
  Secure Boot configured: YES

--- Signature Database Status ---
✓ Authorized Signature Database (db) is set
✓ Forbidden Signature Database (dbx) is set
```

### 2. `check-secureboot-env.txt` (Environment Configuration)
**Type:** u-boot environment variable definitions

**Purpose:** Pre-defined environment commands for repeated Secure Boot checks

**Available Commands:**
- `run check_secureboot` - Check if SecureBoot variable exists
- `run check_secureboot_keys` - Check all Secure Boot keys (PK, KEK, db, dbx)
- `run show_secureboot_status` - Display comprehensive status report
- `run dump_secureboot_vars` - Dump raw EFI variable contents

**Aliases (Shortcuts):**
- `run sb_check` → `run check_secureboot`
- `run sb_keys` → `run check_secureboot_keys`
- `run sb_status` → `run show_secureboot_status`
- `run sb_dump` → `run dump_secureboot_vars`

**Usage in u-boot:**
```bash
# Load environment configuration
fatload mmc 0:1 ${scriptaddr} check-secureboot-env.txt
source ${scriptaddr}

# Now you can run commands:
run sb_status
run sb_keys
run sb_dump
```

### 3. `check-secureboot.scr` (Compiled Binary Script)
**Type:** u-boot boot script (compiled binary)

**Purpose:** Pre-compiled version of check-secureboot.txt for direct execution

**Generation:**
```bash
mkimage -T script -C none -n "check-secureboot" \
  -d check-secureboot.txt -o check-secureboot.scr
```

**Usage:**
```bash
# Load and run directly
fatload mmc 0:1 ${scriptaddr} check-secureboot.scr
source ${scriptaddr}
```

## EFI Secure Boot Variables Reference

### SecureBoot
- **Type:** UINT8
- **Values:** 0x00 (Disabled), 0x01 (Enabled)
- **Purpose:** Indicates if Secure Boot is currently active
- **Writable:** No (read-only during runtime)

### Platform Key (PK)
- **Type:** EFI_SIGNATURE_LIST
- **Purpose:** Root of trust for Secure Boot
- **Required:** Yes (must be set for Secure Boot operation)
- **Signed by:** Self-signed (PK signs itself)

### Key Exchange Key (KEK)
- **Type:** EFI_SIGNATURE_LIST
- **Purpose:** Used to sign updates to db and dbx
- **Required:** Yes (for Secure Boot)
- **Signed by:** PK

### Authorized Signatures Database (db)
- **Type:** EFI_SIGNATURE_LIST
- **Purpose:** Contains authorized boot binary signatures
- **Required:** Yes (to boot signed binaries)
- **Signed by:** KEK

### Forbidden Signatures Database (dbx)
- **Type:** EFI_SIGNATURE_LIST
- **Purpose:** Revocation list for compromised binaries
- **Required:** No (optional for extra security)
- **Signed by:** KEK

## Implementation in u-boot

### u-boot Secure Boot Commands
```bash
# Check if variable exists
efi query var <VAR_NAME>

# Display variable details (with -nv flag for non-volatile)
efi query var <VAR_NAME> -nv

# Test for variable existence in conditionals
if efi query var SecureBoot; then
  echo "SecureBoot variable found"
else
  echo "SecureBoot variable NOT found"
fi
```

### Integration Points

These scripts can be integrated into:

1. **Boot Script Sequence**
   ```bash
   # In bootcmd or custom boot scripts
   setenv bootcmd ' \
     run check_secureboot; \
     run check_secureboot_keys; \
     run load_kernel; \
     bootm ...; \
   '
   ```

2. **u-boot Environment**
   ```bash
   # In u-boot configuration or environment files
   source check-secureboot-env.txt
   ```

3. **Diagnostic Tools**
   ```bash
   # Interactive u-boot console
   => source ${scriptaddr} check-secureboot.scr
   => run sb_status
   => run sb_dump
   ```

## Typical Boot Flow with Secure Boot Check

```
1. u-boot starts
2. Load and run check-secureboot-env.txt
3. Execute: run check_secureboot_keys
4. If keys are valid: proceed with normal boot
5. If keys missing: show warning but continue
6. Load kernel and boot OS
```

## Troubleshooting

### "SecureBoot variable not found"
**Cause:** System is not running in UEFI mode
**Solution:** Boot with UEFI firmware enabled in BIOS/UEFI settings

### "Platform Key (PK) not set"
**Cause:** Secure Boot not initialized on this system
**Solution:** Enroll Secure Boot keys in UEFI firmware settings

### "KEK not found"
**Cause:** Secure Boot keys not properly configured
**Solution:** Ensure full Secure Boot key hierarchy is set (PK → KEK → db/dbx)

### "db (Authorized Signatures) missing"
**Cause:** No authorized boot binaries configured
**Solution:** Add boot binary signatures to db via Secure Boot setup utility

## Security Considerations

1. **Variable Authenticity**
   - Verify variables are signed with proper Secure Boot keys
   - Check digital signatures of all boot binaries

2. **Key Protection**
   - PK is critical: once set, controls all other key updates
   - KEK controls db/dbx updates
   - Both must be kept secure

3. **Measurement Boot**
   - Combine with TPM PCR measurements for attestation
   - Extend PCR7 with Secure Boot state
   - Enable measured boot in u-boot configuration

4. **Revocation**
   - Use dbx to revoke compromised binaries
   - Regularly update revocation lists
   - Monitor for known CVEs in boot binaries

## Related Documentation

- [UEFI Specification - Secure Boot](https://uefi.org/specs/UEFI/2.10/Chapter_28_Secure_Boot_and_Driver_Signing.html)
- [u-boot EFI Implementation](https://u-boot.readthedocs.io/en/latest/develop/uefi/)
- [u-boot Secure Boot Integration](https://u-boot.readthedocs.io/en/latest/develop/uefi_secure_boot.html)
- [DISTRO Project Secure Boot Configuration](../README.md)

## Examples

### Example 1: Check Secure Boot Status During Boot
```bash
# In u-boot bootcmd
setenv bootcmd 'run check_secureboot; run load_kernel; bootm ...'
```

### Example 2: Conditional Boot Based on Secure Boot State
```bash
setenv secure_boot_check ' \
  if efi query var SecureBoot; then \
    if efi query var PK; then \
      echo "Secure Boot: ENABLED"; \
      setenv secureboot_status enabled; \
    else \
      echo "Secure Boot: DISABLED (permissive mode)"; \
      setenv secureboot_status disabled; \
    fi; \
  else \
    echo "WARNING: UEFI boot required for Secure Boot"; \
    setenv secureboot_status unavailable; \
  fi; \
'

setenv bootcmd 'run secure_boot_check; run load_kernel; bootm ...'
```

### Example 3: Dump All Secure Boot Variables for Diagnostics
```bash
# Load environment commands
source check-secureboot-env.txt

# Dump all variables
run sb_dump

# Output shows all EFI Secure Boot variable contents
```

## Contributing

To improve these scripts:

1. Test with different u-boot versions (v2024.01+)
2. Verify on different UEFI implementations (OVMF, EDK2)
3. Add support for additional diagnostics
4. Improve error messages and reporting
5. Add PCR measurement integration

## License

These scripts are part of the DISTRO Project and licensed under MIT.

Copyright (c) 2026 DISTRO Project
SPDX-License-Identifier: MIT
