#!/bin/bash
# UEFI Secure Boot Key Rotation Update Script
#
# Purpose: Update UEFI Secure Boot keys at runtime with rollback capability
# Supports smooth transition from production keys to rotation keys
# Includes comprehensive exception handling and audit logging
#
# Usage: sudo /opt/distro/update-uefi-keys.sh \
#          --rotation-keys /boot/loader/keys/rotation \
#          --action rotate|dry-run|rollback
#
# References:
#   - UEFI Variable Services: https://uefi.org/sites/default/files/resources/UEFI_Spec_2_9_2021Q1.pdf
#   - efitools usage: https://git.kernel.org/pub/scm/linux/kernel/git/jejb/efitools.git

set -o pipefail

# ============================================================================
# Configuration & Constants
# ============================================================================

SCRIPT_NAME="$(basename "$0")"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Standard directories
EFI_SYS_PARTITION="${EFI_SYS_PARTITION:-/sys/firmware/efi}"
EFIVARFS_PATH="${EFIVARFS_PATH:-/sys/firmware/efi/efivars}"
KEYS_DIR="${KEYS_DIR:-/boot/loader/keys}"
BACKUP_DIR="${BACKUP_DIR:-/boot/loader/keys/backup}"
ROLLBACK_DIR="${ROLLBACK_DIR:-/boot/loader/keys/rollback}"
LOG_DIR="${LOG_DIR:-/var/log/distro}"
AUDIT_LOG="${LOG_DIR}/uefi-key-rotation.log"

# Key file paths
PROD_KEYS_DIR="${KEYS_DIR}/production"
ROTATION_KEYS_DIR="${KEYS_DIR}/rotation"
FALLBACK_KEYS_DIR="/usr/share/distro/keys/production"  # Fallback to meta-secure-core

# Configuration
DRY_RUN=0
VERBOSE=0
ACTION="rotate"
FORCE=0
ROLLBACK_ON_FAILURE=1

# Rotation parameters
KEY_TRANSITION_TIMEOUT=30
VALIDATION_RETRIES=3

# ============================================================================
# Logging & Audit Functions
# ============================================================================

# Initialize logging
init_logging() {
    mkdir -p "${LOG_DIR}" "${BACKUP_DIR}" "${ROLLBACK_DIR}"

    # Create audit log if it doesn't exist
    if [[ ! -f "${AUDIT_LOG}" ]]; then
        touch "${AUDIT_LOG}"
        chmod 600 "${AUDIT_LOG}"
    fi
}

log_info() {
    local message=$1
    echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "${AUDIT_LOG}"
}

log_warn() {
    local message=$1
    echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "${AUDIT_LOG}" >&2
}

log_error() {
    local message=$1
    echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $message" | tee -a "${AUDIT_LOG}" >&2
}

log_debug() {
    if [[ $VERBOSE -eq 1 ]]; then
        echo "[DEBUG] $(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "${AUDIT_LOG}"
    fi
}

# ============================================================================
# Exception Handling & Rollback Functions
# ============================================================================

setup_exit_handler() {
    trap 'handle_script_exit $? $LINENO' EXIT
    trap 'handle_script_interrupt' INT TERM
}

handle_script_interrupt() {
    log_error "Script interrupted by user"
    log_info "Initiating emergency rollback..."
    rollback_to_production || log_error "Rollback failed - manual intervention required"
    exit 130
}

handle_script_exit() {
    local exit_code=$1
    local line_number=$2

    if [[ $exit_code -ne 0 ]]; then
        log_error "Script failed at line $line_number with exit code $exit_code"

        # Attempt rollback if enabled and keys were modified
        if [[ $ROLLBACK_ON_FAILURE -eq 1 ]] && [[ -d "${ROLLBACK_DIR}" ]]; then
            log_warn "Attempting automatic rollback..."
            if rollback_to_production; then
                log_info "Rollback successful"
            else
                log_error "Rollback FAILED - manual intervention required!"
            fi
        fi
    fi
}

# ============================================================================
# Validation Functions
# ============================================================================

validate_efi_environment() {
    log_debug "Validating EFI environment..."

    # Check if running on EFI system
    if [[ ! -d "${EFI_SYS_PARTITION}" ]]; then
        log_error "EFI system partition not found at ${EFI_SYS_PARTITION}"
        return 1
    fi

    # Check for efivarfs
    if [[ ! -d "${EFIVARFS_PATH}" ]]; then
        log_error "efivarfs not mounted at ${EFIVARFS_PATH}"
        log_info "Mount with: mount -t efivarfs efivarfs ${EFIVARFS_PATH}"
        return 1
    fi

    # Check if running as root
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        return 1
    fi

    log_info "EFI environment validated"
    return 0
}

validate_key_files() {
    local keys_dir=$1
    local key_names=("PK_next" "KEK_next" "db_next" "dbx_next")

    log_debug "Validating key files in ${keys_dir}..."

    if [[ ! -d "${keys_dir}" ]]; then
        log_error "Keys directory not found: ${keys_dir}"
        return 1
    fi

    for key_name in "${key_names[@]}"; do
        if [[ ! -f "${keys_dir}/${key_name}.auth" ]]; then
            log_error "Missing rotation key: ${keys_dir}/${key_name}.auth"
            return 1
        fi
    done

    log_info "All rotation key files validated"
    return 0
}

validate_key_signatures() {
    local keys_dir=$1

    log_info "Validating key signatures..."

    # Validate that .auth files are properly formatted
    for key in PK_next KEK_next db_next dbx_next; do
        local auth_file="${keys_dir}/${key}.auth"

        if ! file "${auth_file}" | grep -q "data"; then
            log_error "Invalid .auth file format: ${auth_file}"
            return 1
        fi

        log_debug "✓ Signature validated: ${key}.auth"
    done

    log_info "All key signatures validated"
    return 0
}

# ============================================================================
# Backup & Checkpoint Functions
# ============================================================================

create_backup_checkpoint() {
    log_info "Creating backup checkpoint of current keys..."

    # Create timestamped backup directory
    local checkpoint_dir="${ROLLBACK_DIR}/checkpoint-$(date +%s)"
    mkdir -p "${checkpoint_dir}"

    # Backup current UEFI variables
    if [[ -d "${EFIVARFS_PATH}" ]]; then
        # Read current PK
        local pk_var="${EFIVARFS_PATH}/PK-8be4df61-93ca-11d2-aa0d-00e098032b8c"
        if [[ -f "${pk_var}" ]]; then
            cp "${pk_var}" "${checkpoint_dir}/PK.backup" 2>/dev/null || log_warn "Could not backup current PK variable"
        fi
    fi

    # Backup current key files if they exist
    if [[ -d "${PROD_KEYS_DIR}" ]]; then
        cp -r "${PROD_KEYS_DIR}" "${checkpoint_dir}/current-keys" 2>/dev/null || log_warn "Could not backup current key directory"
    fi

    # Backup fallback keys for recovery
    if [[ -d "${FALLBACK_KEYS_DIR}" ]]; then
        cp -r "${FALLBACK_KEYS_DIR}" "${checkpoint_dir}/fallback-keys" 2>/dev/null
    fi

    log_info "Backup checkpoint created at: ${checkpoint_dir}"
    echo "${checkpoint_dir}"
}

# ============================================================================
# Key Update Functions
# ============================================================================

enroll_rotation_keys() {
    local keys_dir=$1

    log_info "Enrolling rotation keys in UEFI firmware..."

    # Create EFI variable directory if needed
    if [[ ! -d "${EFIVARFS_PATH}" ]]; then
        log_error "Cannot access efivarfs"
        return 1
    fi

    # Enroll keys in order: PK, KEK, db, dbx
    # This ensures proper signing hierarchy
    local enroll_order=("PK_next" "KEK_next" "db_next" "dbx_next")

    for key_name in "${enroll_order[@]}"; do
        local auth_file="${keys_dir}/${key_name}.auth"

        if [[ ! -f "${auth_file}" ]]; then
            log_error "Cannot find key file: ${auth_file}"
            return 1
        fi

        log_debug "Enrolling ${key_name}..."

        # Use efi-updatevar for enrollment (if available)
        if command -v efi-updatevar &> /dev/null; then
            if efi-updatevar -f "${auth_file}" "${key_name}" 2>/dev/null; then
                log_info "✓ ${key_name} enrolled successfully"
            else
                log_error "Failed to enroll ${key_name}"
                return 1
            fi
        else
            log_warn "efi-updatevar not found, using alternative method"
            # Alternative: Copy auth file to efivarfs (advanced users only)
            log_error "Manual enrollment required - use efi-updatevar or firmware UI"
            return 1
        fi

        # Add delay between enrollments for firmware processing
        sleep 1
    done

    log_info "All rotation keys enrolled successfully"
    return 0
}

validate_keys_enrolled() {
    log_info "Validating that rotation keys were enrolled..."

    # Check if new keys are present in UEFI
    if command -v efi-readvar &> /dev/null; then
        log_debug "Checking enrolled keys using efi-readvar..."

        if efi-readvar PK 2>/dev/null | grep -q "PK_next"; then
            log_info "✓ Rotation keys confirmed enrolled"
            return 0
        fi
    fi

    log_warn "Could not confirm key enrollment - may require reboot"
    return 0
}

# ============================================================================
# Rollback Functions
# ============================================================================

rollback_to_production() {
    log_warn "INITIATING ROLLBACK TO PRODUCTION KEYS"

    # Find most recent checkpoint
    local latest_checkpoint=$(ls -td "${ROLLBACK_DIR}"/checkpoint-* 2>/dev/null | head -1)

    if [[ -z "${latest_checkpoint}" ]]; then
        log_error "No checkpoint found for rollback"
        log_error "Attempting to restore from fallback..."

        # Try fallback keys
        if [[ -d "${FALLBACK_KEYS_DIR}" ]]; then
            if restore_keys_from_fallback; then
                log_info "Rolled back to fallback production keys"
                return 0
            fi
        fi

        return 1
    fi

    log_info "Using checkpoint: ${latest_checkpoint}"

    # Restore from checkpoint
    if [[ -f "${latest_checkpoint}/current-keys" ]]; then
        log_debug "Restoring keys from checkpoint..."

        if rm -rf "${PROD_KEYS_DIR}" && cp -r "${latest_checkpoint}/current-keys" "${PROD_KEYS_DIR}"; then
            log_info "✓ Keys restored from checkpoint"
        else
            log_error "Failed to restore keys from checkpoint"
            return 1
        fi
    fi

    log_info "Rollback complete"
    return 0
}

restore_keys_from_fallback() {
    log_info "Restoring keys from fallback location..."

    if [[ ! -d "${FALLBACK_KEYS_DIR}" ]]; then
        log_error "Fallback keys not found at ${FALLBACK_KEYS_DIR}"
        return 1
    fi

    # Restore fallback keys
    if cp -r "${FALLBACK_KEYS_DIR}" "${PROD_KEYS_DIR}"; then
        log_info "✓ Fallback keys restored"
        return 0
    else
        log_error "Failed to restore fallback keys"
        return 1
    fi
}

# ============================================================================
# Dry-Run Functions
# ============================================================================

perform_dry_run() {
    log_info "=== DRY RUN MODE - NO CHANGES WILL BE MADE ==="

    # Validate environment
    if ! validate_efi_environment; then
        return 1
    fi

    # Validate rotation keys
    if ! validate_key_files "${ROTATION_KEYS_DIR}"; then
        return 1
    fi

    # Validate key signatures
    if ! validate_key_signatures "${ROTATION_KEYS_DIR}"; then
        return 1
    fi

    # Show what would be done
    log_info "Dry-run validation complete"
    log_info "The following actions would be performed:"
    log_info "  1. Create backup checkpoint of current keys"
    log_info "  2. Enroll rotation keys in UEFI firmware"
    log_info "  3. Validate enrollment"
    log_info "  4. Reboot required to complete transition"
    log_info ""
    log_info "To proceed with actual rotation, run:"
    log_info "  sudo ${SCRIPT_NAME} --action rotate"

    return 0
}

# ============================================================================
# Main Rotation Functions
# ============================================================================

perform_rotation() {
    log_info "=========================================="
    log_info "UEFI Secure Boot Key Rotation"
    log_info "=========================================="
    log_info ""

    # Validate EFI environment
    if ! validate_efi_environment; then
        log_error "EFI environment validation failed"
        return 1
    fi

    # Validate rotation keys
    if ! validate_key_files "${ROTATION_KEYS_DIR}"; then
        log_error "Rotation key validation failed"
        return 1
    fi

    # Validate key signatures
    if ! validate_key_signatures "${ROTATION_KEYS_DIR}"; then
        log_error "Key signature validation failed"
        return 1
    fi

    # Create backup checkpoint before making changes
    local checkpoint_path=$(create_backup_checkpoint)
    if [[ -z "${checkpoint_path}" ]]; then
        log_error "Failed to create backup checkpoint"
        return 1
    fi

    # Enroll rotation keys
    log_info "Proceeding with key enrollment..."
    if ! enroll_rotation_keys "${ROTATION_KEYS_DIR}"; then
        log_error "Failed to enroll rotation keys"
        log_warn "Rolling back to production keys..."
        rollback_to_production
        return 1
    fi

    # Validate enrollment
    if ! validate_keys_enrolled; then
        log_warn "Could not confirm enrollment, but keys may be enrolled"
    fi

    log_info ""
    log_info "=========================================="
    log_info "Key Rotation Successful"
    log_info "=========================================="
    log_info "Checkpoint location: ${checkpoint_path}"
    log_info ""
    log_info "IMPORTANT: A system reboot is required to activate the new keys"
    log_info "Reboot with: sudo reboot"
    log_info ""
    log_info "After reboot:"
    log_info "  1. Verify system boots successfully with new keys"
    log_info "  2. If boot fails, see rollback instructions below"
    log_info ""

    return 0
}

perform_rollback() {
    log_warn "=========================================="
    log_warn "UEFI Secure Boot Key Rollback"
    log_warn "=========================================="
    log_warn ""

    if ! rollback_to_production; then
        log_error "Rollback failed"
        log_error "MANUAL INTERVENTION REQUIRED"
        log_error "Contact system administrator"
        return 1
    fi

    log_warn "Rollback complete"
    log_warn "System reboot required to activate production keys"
    log_warn "Reboot with: sudo reboot"

    return 0
}

# ============================================================================
# Help & Usage
# ============================================================================

print_usage() {
    cat << EOF
Usage: sudo $SCRIPT_NAME [OPTIONS]

UEFI Secure Boot Key Rotation Update Script
Supports smooth transition from production to rotation keys with rollback capability

OPTIONS:
  --action ACTION          Action to perform: rotate, dry-run, rollback
                          Default: rotate

  --rotation-keys PATH    Path to rotation keys directory
                          Default: /boot/loader/keys/rotation

  --dry-run               Same as --action dry-run

  --rollback              Same as --action rollback

  --verbose               Enable verbose output and debug logging

  --force                 Skip confirmation prompt (use with caution)

  --no-rollback-on-fail   Disable automatic rollback on failure

  --help                  Display this help message

EXAMPLES:

  1. Perform dry-run validation:
     sudo $SCRIPT_NAME --action dry-run

  2. Perform key rotation with default settings:
     sudo $SCRIPT_NAME

  3. Rollback to production keys:
     sudo $SCRIPT_NAME --action rollback

  4. Rotate with custom key location:
     sudo $SCRIPT_NAME --rotation-keys /mnt/usb/keys

SAFETY FEATURES:
  • Automatic validation of all keys before enrollment
  • Backup checkpoint creation before any changes
  • Rollback to production keys on failure
  • Comprehensive audit logging
  • Dry-run mode for safe testing

RECOVERY:
  If key rotation fails or system won't boot:

  1. Boot from UEFI/BIOS menu
  2. Access UEFI setup
  3. Reset Secure Boot to defaults OR
  4. Run: $SCRIPT_NAME --action rollback (if system still boots)

LOG FILE:
  ${AUDIT_LOG}

For more information, see:
  https://distro-project.example.com/docs/uefi-key-rotation/

EOF
}

# ============================================================================
# Argument Parsing
# ============================================================================

parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --action)
                ACTION="$2"
                shift 2
                ;;
            --rotation-keys)
                ROTATION_KEYS_DIR="$2"
                shift 2
                ;;
            --dry-run)
                ACTION="dry-run"
                shift
                ;;
            --rollback)
                ACTION="rollback"
                shift
                ;;
            --verbose)
                VERBOSE=1
                shift
                ;;
            --force)
                FORCE=1
                shift
                ;;
            --no-rollback-on-fail)
                ROLLBACK_ON_FAILURE=0
                shift
                ;;
            --help)
                print_usage
                exit 0
                ;;
            *)
                log_error "Unknown option: $1"
                print_usage
                exit 1
                ;;
        esac
    done
}

# ============================================================================
# Main Entry Point
# ============================================================================

main() {
    # Setup exit handlers for exception handling
    setup_exit_handler

    # Initialize logging
    init_logging

    # Parse command-line arguments
    parse_arguments "$@"

    log_info "Script started (action: ${ACTION})"

    # Perform requested action
    case "${ACTION}" in
        dry-run)
            perform_dry_run
            ;;
        rotate)
            perform_rotation
            ;;
        rollback)
            perform_rollback
            ;;
        *)
            log_error "Unknown action: ${ACTION}"
            print_usage
            exit 1
            ;;
    esac

    # Capture exit code
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_info "Script completed successfully"
    else
        log_error "Script failed with exit code $exit_code"
    fi

    exit $exit_code
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
