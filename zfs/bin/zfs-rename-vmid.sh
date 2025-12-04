#!/bin/bash

set -o errexit -o nounset -o pipefail

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

# Configuration
declare -g PVE_QEMU_SERVER="/etc/pve/qemu-server"

# Logging configuration
declare -g LOG_LEVEL="INFO"    # ERROR, WARNING, INFO, DEBUG
declare -g LOG_FORMAT="simple" # simple, level, full

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

# Set log level with validation
set_log_level() {
    local level="${1^^}" # Convert to uppercase
    if [[ -n "${LOG_PRIORITY[${level}]:-}" ]]; then
        LOG_LEVEL="${level}"
    else
        log_error "Invalid log level: ${1}. Valid levels: ERROR, WARNING, INFO, DEBUG"
        exit 1
    fi
}

# Set log format with validation
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

# Check if required commands are available
require_command() {
    for c in "$@"; do
        if ! command -v "$c" >/dev/null 2>&1; then
            log_error "Required command '$c' is not installed"
            exit 1
        fi
    done
}

# Show usage information
usage() {
    cat <<EOF
Usage:
    ${SCRIPT_NAME} [OPTIONS] <source_zpool>/<source_vmid> <dest_zpool>/<dest_vmid>

    Rename VM zvols and configuration from source to destination.
    This includes all VM disks (disk-*, cloudinit, base) and the qemu-server config.

    WARNING: This operation modifies ZFS datasets and VM configurations!
    By default, the script runs in dry-run mode. Use --apply to execute changes.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    --apply                   Actually execute the rename (default is dry-run)
    --backup-dir DIR          Base directory for timestamped backups
                              Default: ~/pve/qemu-server

ARGUMENTS:
    source_zpool/source_vmid  Source zpool and VM ID (e.g., tank/3101)
    dest_zpool/dest_vmid      Destination zpool and VM ID (e.g., data0/2101)

EXAMPLES:
    ${SCRIPT_NAME} tank/3101 data0/2101
    ${SCRIPT_NAME} --apply tank/3101 data0/2101
    ${SCRIPT_NAME} --log-level DEBUG --backup-dir /backup tank/3101 tank/2101

NOTE:
    Backups are stored in timestamped subdirectories:
    <backup-dir>/<YYYY-MM-DD-HHMMSS>/

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="h"
    local longoptions="help,log-level:,log-format:,apply,backup-dir:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g SOURCE=""
    declare -g DEST=""
    declare -g APPLY=false
    declare -g BACKUP_DIR_BASE="${HOME}/pve/qemu-server"
    declare -g BACKUP_DIR=""

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
            --apply)
                APPLY=true
                shift
                ;;
            --backup-dir)
                BACKUP_DIR_BASE="$2"
                shift 2
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

    # Validate positional arguments
    if [[ $# -ne 2 ]]; then
        log_error "Expected exactly two arguments: <source_zpool/source_vmid> <dest_zpool/dest_vmid>"
        usage
    fi

    SOURCE="$1"
    DEST="$2"

    # Validate format: must contain exactly one slash
    if [[ ! "${SOURCE}" =~ ^[^/]+/[^/]+$ ]]; then
        log_error "Invalid source format: ${SOURCE}. Expected format: zpool/vmid"
        exit 1
    fi

    if [[ ! "${DEST}" =~ ^[^/]+/[^/]+$ ]]; then
        log_error "Invalid destination format: ${DEST}. Expected format: zpool/vmid"
        exit 1
    fi

    # Create timestamped backup directory
    local timestamp
    timestamp="$(date -u +%Y-%m-%d-%H%M%S)"
    BACKUP_DIR="${BACKUP_DIR_BASE}/${timestamp}"
}

# Validate source VM exists and destination doesn't
validate_vms() {
    local source_zpool="${SOURCE%/*}"
    local source_vmid="${SOURCE#*/}"
    local dest_zpool="${DEST%/*}"
    local dest_vmid="${DEST#*/}"

    log_debug "Validating source VM: ${SOURCE}"

    # Check if source zpool exists
    if [[ ! -d "/dev/zvol/${source_zpool}" ]]; then
        log_error "Source zpool does not exist: ${source_zpool}"
        exit 1
    fi

    # Check if destination zpool exists
    if [[ ! -d "/dev/zvol/${dest_zpool}" ]]; then
        log_error "Destination zpool does not exist: ${dest_zpool}"
        exit 1
    fi

    # Check if source VM config exists
    if [[ ! -f "${PVE_QEMU_SERVER}/${source_vmid}.conf" ]]; then
        log_error "Source VM config does not exist: ${PVE_QEMU_SERVER}/${source_vmid}.conf"
        exit 1
    fi

    # Check if destination VM config already exists
    if [[ -f "${PVE_QEMU_SERVER}/${dest_vmid}.conf" ]]; then
        log_error "Destination VM config already exists: ${PVE_QEMU_SERVER}/${dest_vmid}.conf"
        exit 1
    fi

    log_debug "Validation passed"
}

# Rename a single zvol
zfs_rename_zvol() {
    local src_zvol_dev="$1"
    local dst_zvol_dev="$2"

    if [[ ! -b "${src_zvol_dev}" ]]; then
        log_warning "Source zvol does not exist: ${src_zvol_dev}"
        return 0
    fi

    if [[ -b "${dst_zvol_dev}" ]]; then
        log_error "Destination zvol already exists: ${dst_zvol_dev}"
        return 1
    fi

    # Remove /dev/ prefix to get ZFS dataset names
    local src_zvol="${src_zvol_dev#/dev/}"
    local dst_zvol="${dst_zvol_dev#/dev/}"

    local src_zpool="${src_zvol%%/*}"
    local dst_zpool="${dst_zvol%%/*}"

    log_info "Renaming: ${src_zvol} -> ${dst_zvol}"

    if [[ "${APPLY}" == false ]]; then
        if [[ "${src_zpool}" != "${dst_zpool}" ]]; then
            local snapshot_name
            snapshot_name="zfs-rename-snap-$(date --utc +%F-%H%M%S)"
            echo "zfs snapshot ${src_zvol}@${snapshot_name}"
            echo "zfs send ${src_zvol}@${snapshot_name} | zfs receive ${dst_zvol}@${snapshot_name}"
        else
            echo "zfs rename ${src_zvol} ${dst_zvol}"
        fi
        return 0
    fi

    # Use 'zfs send | zfs receive' if zvols are in different zpools
    if [[ "${src_zpool}" != "${dst_zpool}" ]]; then
        local snapshot_name
        snapshot_name="zfs-rename-snap-$(date --utc +%F-%H%M%S)"
        log_debug "Creating snapshot: ${src_zvol}@${snapshot_name}"
        if ! zfs snapshot "${src_zvol}@${snapshot_name}"; then
            log_error "Failed to create snapshot: ${src_zvol}@${snapshot_name}"
            return 1
        fi

        log_debug "Sending snapshot to destination"
        if ! zfs send "${src_zvol}@${snapshot_name}" | zfs receive "${dst_zvol}@${snapshot_name}"; then
            log_error "Failed to send/receive snapshot"
            return 1
        fi
        log_info "Successfully migrated: ${src_zvol} -> ${dst_zvol}"
    else
        if ! zfs rename "${src_zvol}" "${dst_zvol}"; then
            log_error "Failed to rename: ${src_zvol} -> ${dst_zvol}"
            return 1
        fi
        log_info "Successfully renamed: ${src_zvol} -> ${dst_zvol}"
    fi
}

# Rename all VM zvols and configuration
zfs_rename_vmid() {
    local src_zpool="${SOURCE%/*}"
    local src_vmid="${SOURCE#*/}"
    local dst_zpool="${DEST%/*}"
    local dst_vmid="${DEST#*/}"

    log_info "Processing VM rename: ${SOURCE} -> ${DEST}"

    # Build regex patterns for matching VM disks
    local src_disk_regex="${src_zpool}(:|/)(base|vm)-${src_vmid}-(cloudinit|disk-[0-9]+)"
    local dst_disk_replacement="${dst_zpool}\1\2-${dst_vmid}-\3"

    log_debug "Searching for VM disks in /dev/zvol/${src_zpool}"

    # Find all VM disk zvols (exclude partition devices with '$' anchor)
    local src_disks
    if ! readarray -t src_disks < <(
        find "/dev/zvol/${src_zpool}" -type l 2>/dev/null | grep -E "${src_disk_regex}$" || true
    ); then
        log_error "Failed to find VM disks"
        exit 1
    fi

    if [[ ${#src_disks[@]} -eq 0 ]]; then
        log_warning "No VM disks found for ${SOURCE}"
    else
        log_info "Found ${#src_disks[@]} disk(s) to rename"

        local success_count=0
        local failure_count=0

        for src_disk in "${src_disks[@]}"; do
            local dst_disk
            dst_disk="$(echo "${src_disk}" | sed -E 's%'"${src_disk_regex}"'%'"${dst_disk_replacement}"'%')"

            if zfs_rename_zvol "${src_disk}" "${dst_disk}"; then
                ((success_count++))
            else
                ((failure_count++))
            fi
        done

        log_info "Zvol rename complete: ${success_count} succeeded, ${failure_count} failed"

        if [[ ${failure_count} -gt 0 ]]; then
            log_error "Some zvols failed to rename"
            exit 1
        fi
    fi

    # Handle VM configuration file
    log_info "Processing VM configuration"

    local src_conf="${PVE_QEMU_SERVER}/${src_vmid}.conf"
    local dst_conf="${PVE_QEMU_SERVER}/${dst_vmid}.conf"
    local backup_conf="${BACKUP_DIR}/${src_vmid}.conf"

    if [[ "${APPLY}" == false ]]; then
        log_info "Dry-run: Would backup and update VM config"
        echo "mkdir -p ${BACKUP_DIR}"
        echo "cp ${src_conf} ${backup_conf}"
        echo "sed -E 's%${src_disk_regex}%${dst_disk_replacement}%' ${backup_conf} >${dst_conf}"
        echo "rm ${src_conf}"
        log_info "Backup would be stored in: ${BACKUP_DIR}"
        return 0
    fi

    # Create backup directory
    log_info "Creating timestamped backup directory: ${BACKUP_DIR}"
    if ! mkdir -p "${BACKUP_DIR}"; then
        log_error "Failed to create backup directory: ${BACKUP_DIR}"
        exit 1
    fi

    # Backup original config
    log_info "Backing up original config to: ${backup_conf}"
    if ! cp -v "${src_conf}" "${backup_conf}"; then
        log_error "Failed to backup original config"
        exit 1
    fi

    # Create new config with updated paths
    log_info "Creating new VM config: ${dst_vmid}.conf"
    if ! sed -E 's%'"${src_disk_regex}"'%'"${dst_disk_replacement}"'%' \
        "${backup_conf}" >"${dst_conf}"; then
        log_error "Failed to create new config"
        exit 1
    fi

    # Show differences
    log_info "Configuration changes:"
    if ! diff "${backup_conf}" "${dst_conf}" || true; then
        log_debug "Diff completed"
    fi

    # Remove old config
    log_info "Removing old VM config: ${src_vmid}.conf"
    if ! rm "${src_conf}"; then
        log_error "Failed to remove old config"
        exit 1
    fi

    log_info "VM rename completed successfully"
    log_info "Backup stored in: ${BACKUP_DIR}"
}

main() {
    require_command getopt zfs find grep sed diff date

    parse_args "$@"

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Source: ${SOURCE}"
    log_debug "Destination: ${DEST}"
    log_debug "Apply mode: ${APPLY}"
    log_debug "Backup directory: ${BACKUP_DIR}"

    validate_vms
    zfs_rename_vmid
}

main "$@"
