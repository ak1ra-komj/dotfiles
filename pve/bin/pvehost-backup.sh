#!/bin/bash

set -o errexit -o nounset -o pipefail

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

# Logging configuration
declare -g LOG_LEVEL="INFO"
declare -g LOG_FORMAT="simple"

# Log level priorities
declare -g -A LOG_PRIORITY=(
    ["DEBUG"]=10
    ["INFO"]=20
    ["WARNING"]=30
    ["ERROR"]=40
    ["CRITICAL"]=50
)

# Logging functions
log_color() {
    local color="$1"
    shift
    if [[ -t 2 ]]; then
        printf "\x1b[0;%sm%s\x1b[0m\n" "${color}" "$*" >&2
    else
        printf "%s\n" "$*" >&2
    fi
}

log_message() {
    local color="$1"
    local level="$2"
    shift 2

    if [[ "${LOG_PRIORITY[$level]}" -lt "${LOG_PRIORITY[$LOG_LEVEL]}" ]]; then
        return 0
    fi

    local message="$*"
    case "${LOG_FORMAT}" in
        simple)
            log_color "${color}" "${message}"
            ;;
        level)
            log_color "${color}" "[${level}] ${message}"
            ;;
        full)
            local timestamp
            timestamp="$(date -u +%Y-%m-%dT%H:%M:%S+0000)"
            log_color "${color}" "[${timestamp}][${level}] ${message}"
            ;;
        *)
            log_color "${color}" "${message}"
            ;;
    esac
}

log_error() {
    local RED=31
    log_message "${RED}" "ERROR" "$@"
}

log_info() {
    local GREEN=32
    log_message "${GREEN}" "INFO" "$@"
}

log_warning() {
    local YELLOW=33
    log_message "${YELLOW}" "WARNING" "$@"
}

log_debug() {
    local BLUE=34
    log_message "${BLUE}" "DEBUG" "$@"
}

log_critical() {
    local CYAN=36
    log_message "${CYAN}" "CRITICAL" "$@"
}

set_log_level() {
    local level="${1^^}"
    if [[ -n "${LOG_PRIORITY[${level}]:-}" ]]; then
        LOG_LEVEL="${level}"
    else
        log_error "Invalid log level: ${1}. Valid levels: ERROR, WARNING, INFO, DEBUG"
        exit 1
    fi
}

set_log_format() {
    case "$1" in
        simple | level | full)
            LOG_FORMAT="$1"
            ;;
        *)
            log_error "Invalid log format: ${1}. Valid formats: simple, level, full"
            exit 1
            ;;
    esac
}

require_command() {
    for c in "$@"; do
        if ! command -v "$c" >/dev/null 2>&1; then
            log_error "Required command '$c' is not installed"
            exit 1
        fi
    done
}

usage() {
    cat <<EOF
Usage:
    ${SCRIPT_NAME} [OPTIONS]

    Backup Proxmox VE host configuration files

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              Default: simple
    -p, --path PATH           Backup destination path
                              Default: /local-zfs1/pvehost-backup
    -r, --retention DAYS      Number of days to keep backups
                              Default: 30
    --verify                  Verify backup integrity after creation
    --no-cleanup              Skip cleanup of old backups
    --dry-run                 Show what would be backed up without creating backup

EXAMPLES:
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --path /mnt/backup --retention 60
    ${SCRIPT_NAME} --log-level DEBUG --verify
    ${SCRIPT_NAME} --dry-run

EOF
    exit 0
}

parse_args() {
    local args
    local options="hp:r:"
    local longoptions="help,log-level:,log-format:,path:,retention:,verify,no-cleanup,dry-run"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"

    declare -g BACKUP_PATH="${HOME}/pvehost-backup"
    declare -g RETENTION_DAYS=30
    declare -g VERIFY_BACKUP=false
    declare -g NO_CLEANUP=false
    declare -g DRY_RUN=false

    while true; do
        case "$1" in
            -h | --help)
                usage
                ;;
            --log-level)
                set_log_level "$2"
                shift 2
                ;;
            --log-format)
                set_log_format "$2"
                shift 2
                ;;
            -p | --path)
                BACKUP_PATH="$2"
                shift 2
                ;;
            -r | --retention)
                if ! [[ "$2" =~ ^[0-9]+$ ]]; then
                    log_error "Retention must be a positive number"
                    exit 1
                fi
                RETENTION_DAYS="$2"
                shift 2
                ;;
            --verify)
                VERIFY_BACKUP=true
                shift
                ;;
            --no-cleanup)
                NO_CLEANUP=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                log_error "Unexpected option: $1"
                usage
                ;;
        esac
    done
}

# PVE configuration paths to backup
get_backup_set() {
    cat <<'EOF'
/etc/apt/
/etc/pve/
/etc/lvm/
/etc/modprobe.d/
/etc/network/interfaces
/etc/vzdump.conf
/etc/sysctl.conf
/etc/resolv.conf
/etc/ksmtuned.conf
/etc/hosts
/etc/hostname
/etc/cron.d/
/etc/cron.daily/
/etc/cron.hourly/
/etc/cron.monthly/
/etc/cron.weekly/
/etc/crontab
/etc/aliases
/etc/apcupsd/
EOF
}

validate_backup_paths() {
    log_debug "Validating backup paths..."
    local missing_paths=()

    while IFS= read -r path; do
        if [[ ! -e "${path}" ]]; then
            log_warning "Path does not exist: ${path}"
            missing_paths+=("${path}")
        fi
    done < <(get_backup_set)

    if [[ ${#missing_paths[@]} -gt 0 ]]; then
        log_info "Found ${#missing_paths[@]} missing path(s), continuing anyway"
    fi
}

create_backup() {
    local hostname
    hostname="$(hostname)"
    local timestamp
    timestamp="$(date +%F.%s)"
    local backup_file="${hostname}-${timestamp}.tar.gz"
    local backup_full_path="${BACKUP_PATH}/${backup_file}"

    log_info "Creating backup: ${backup_file}"

    if [[ "${DRY_RUN}" == true ]]; then
        log_info "[DRY RUN] Would backup the following paths:"
        get_backup_set
        return 0
    fi

    # Create backup directory if it doesn't exist
    if [[ ! -d "${BACKUP_PATH}" ]]; then
        log_info "Creating backup directory: ${BACKUP_PATH}"
        mkdir -p "${BACKUP_PATH}"
    fi

    # Create temporary file list
    local temp_list
    temp_list="$(mktemp)"
    trap 'rm -f "${temp_list}"' EXIT

    # Filter out non-existent paths
    while IFS= read -r path; do
        if [[ -e "${path}" ]]; then
            echo "${path}" >>"${temp_list}"
        fi
    done < <(get_backup_set)

    # Create backup
    log_debug "Creating tar archive..."
    if tar -czf "${backup_full_path}" --absolute-names --files-from="${temp_list}" 2>&1 | while IFS= read -r line; do
        log_debug "tar: ${line}"
    done; then
        log_info "Backup created successfully: ${backup_full_path}"

        # Generate checksum
        log_debug "Generating SHA256 checksum..."
        if sha256sum "${backup_full_path}" >"${backup_full_path}.sha256"; then
            log_info "Checksum saved: ${backup_full_path}.sha256"
        else
            log_warning "Failed to generate checksum"
        fi

        # Show backup size
        local size
        size="$(du -h "${backup_full_path}" | cut -f1)"
        log_info "Backup size: ${size}"

        echo "${backup_full_path}"
    else
        log_error "Failed to create backup"
        return 1
    fi
}

verify_backup() {
    local backup_file="$1"

    log_info "Verifying backup integrity..."

    # Verify checksum if available
    if [[ -f "${backup_file}.sha256" ]]; then
        log_debug "Verifying checksum..."
        if (cd "$(dirname "${backup_file}")" && sha256sum -c "$(basename "${backup_file}.sha256")"); then
            log_info "Checksum verification passed"
        else
            log_error "Checksum verification failed"
            return 1
        fi
    fi

    # Test tar archive
    log_debug "Testing tar archive integrity..."
    if tar -tzf "${backup_file}" >/dev/null 2>&1; then
        log_info "Archive integrity verified"
        return 0
    else
        log_error "Archive integrity check failed"
        return 1
    fi
}

cleanup_old_backups() {
    if [[ "${NO_CLEANUP}" == true ]]; then
        log_info "Skipping cleanup (--no-cleanup specified)"
        return 0
    fi

    log_info "Cleaning up backups older than ${RETENTION_DAYS} days..."

    local count=0
    while IFS= read -r file; do
        log_debug "Removing old backup: ${file}"
        rm -f "${file}" "${file}.sha256"
        ((count++))
    done < <(find "${BACKUP_PATH}" -name "*.tar.gz" -type f -mtime "+${RETENTION_DAYS}")

    if [[ ${count} -gt 0 ]]; then
        log_info "Removed ${count} old backup(s)"
    else
        log_info "No old backups to remove"
    fi
}

list_backups() {
    log_info "Current backups in ${BACKUP_PATH}:"

    if [[ ! -d "${BACKUP_PATH}" ]]; then
        log_warning "Backup directory does not exist"
        return 0
    fi

    local count=0
    while IFS= read -r file; do
        local size
        size="$(du -h "${file}" | cut -f1)"
        local date
        date="$(stat -c %y "${file}" | cut -d' ' -f1)"
        log_info "  $(basename "${file}") [${size}] (${date})"
        ((count++))
    done < <(find "${BACKUP_PATH}" -name "*.tar.gz" -type f | sort -r)

    log_info "Total backups: ${count}"
}

main() {
    require_command getopt tar sha256sum find du stat

    parse_args "$@"

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_info "PVE Host Backup Script"
    log_info "Backup path: ${BACKUP_PATH}"
    log_info "Retention: ${RETENTION_DAYS} days"

    validate_backup_paths

    local backup_file
    if backup_file="$(create_backup)"; then
        if [[ "${VERIFY_BACKUP}" == true ]] && [[ "${DRY_RUN}" == false ]]; then
            verify_backup "${backup_file}"
        fi

        if [[ "${DRY_RUN}" == false ]]; then
            cleanup_old_backups
            list_backups
        fi

        log_info "Backup completed successfully"
    else
        log_error "Backup failed"
        exit 1
    fi
}

main "$@"
