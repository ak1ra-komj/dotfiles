#!/bin/bash
# Author: ak1ra
# Date: 2024-04-11
# Description: Map disk devices to their WWN and ATA/SCSI identifiers

set -o errexit -o nounset -o pipefail

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

readonly DISK_BY_ID_DIR="/dev/disk/by-id"

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
    ${SCRIPT_NAME} [OPTIONS]

    Map disk devices to their WWN and ATA/SCSI identifiers.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    --nvme                    Show NVMe EUI mapping instead of WWN/ATA

EXAMPLES:
    ${SCRIPT_NAME}                              # Show WWN and ATA/SCSI mapping
    ${SCRIPT_NAME} --nvme                       # Show NVMe EUI mapping
    ${SCRIPT_NAME} --log-level DEBUG            # Show with debug logging
    ${SCRIPT_NAME} --log-format level --nvme    # NVMe mapping with log levels

NOTES:
    - This script requires read access to /dev/disk/by-id/
    - Output format: DEVICE WWN-ID ATA/SCSI-ID (or EUI-ID NVME-ID)

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="h"
    local longoptions="help,log-level:,log-format:,nvme"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g -a REST_ARGS=()

    declare -g SHOW_NVME=false

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
            --nvme)
                SHOW_NVME=true
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

    # Capture remaining positional arguments
    # shellcheck disable=SC2034
    REST_ARGS=("$@")

    log_debug "Configuration:"
    log_debug "  SHOW_NVME=${SHOW_NVME}"
    log_debug "  LOG_LEVEL=${LOG_LEVEL}"
    log_debug "  LOG_FORMAT=${LOG_FORMAT}"
}

# Map device identifiers based on pattern
# Arguments:
#   $1: nameref to associative array for storing mappings
#   $2: find regex pattern to match
#   $3: grep exclude pattern (optional)
# SC2034 (warning): nameref_map appears unused. Verify use (or export if used externally).
# shellcheck disable=SC2034
map_device_ids() {
    local nameref_name="$1"
    local find_pattern="$2"
    local grep_exclude="${3:-}"

    # Validate parameters
    if [[ -z "${nameref_name}" || -z "${find_pattern}" ]]; then
        log_error "map_device_ids: missing required parameters"
        return 1
    fi

    # Check if directory exists
    if [[ ! -d "${DISK_BY_ID_DIR}" ]]; then
        log_error "Directory not found: ${DISK_BY_ID_DIR}"
        return 1
    fi

    log_debug "Mapping IDs with pattern: ${find_pattern}"

    # Use nameref to modify the passed associative array
    local -n nameref_map="${nameref_name}"
    local link dev

    while IFS= read -r link; do
        if ! dev=$(readlink -f "${link}"); then
            log_warning "Failed to resolve symlink: ${link}"
            continue
        fi
        nameref_map["${dev}"]="${link}"
        log_debug "  Mapped: ${dev} -> ${link}"
    done < <(
        find "${DISK_BY_ID_DIR}" -type l \
            -regextype posix-extended -regex "${find_pattern}" 2>/dev/null |
            grep -vE -- '-part[0-9]+$' | {
            if [[ -n "${grep_exclude}" ]]; then
                grep -vE -- "${grep_exclude}"
            else
                cat
            fi
        }
    )
}

# Show WWN and ATA/SCSI mapping
show_wwn_ata_mapping() {
    local -A dev_wwn_map=()
    local -A dev_ata_map=()
    local dev

    log_info "Mapping WWN identifiers..."
    if ! map_device_ids dev_wwn_map "${DISK_BY_ID_DIR}/wwn-.*" ""; then
        log_error "Failed to map WWN identifiers"
        return 1
    fi

    log_info "Mapping ATA/SCSI identifiers..."
    if ! map_device_ids dev_ata_map "${DISK_BY_ID_DIR}/(ata|scsi)-.*" ""; then
        log_error "Failed to map ATA/SCSI identifiers"
        return 1
    fi

    # Check if array has elements
    if [[ "${#dev_wwn_map[@]}" -eq 0 ]]; then
        log_warning "No WWN identifiers found"
        return 0
    fi

    log_info "Found ${#dev_wwn_map[@]} device(s) with WWN identifiers"
    printf "\n%-15s %-50s %-50s\n" "DEVICE" "WWN-ID" "ATA/SCSI-ID"
    printf "%s\n" "$(printf '%.0s-' {1..115})"

    for dev in "${!dev_wwn_map[@]}"; do
        printf "%-15s %-50s %-50s\n" \
            "${dev}" \
            "${dev_wwn_map[${dev}]:-(no wwn-ID found)}" \
            "${dev_ata_map[${dev}]:-(no ata-ID found)}"
    done | sort -k1
}

# Show NVMe EUI mapping
show_nvme_eui_mapping() {
    local -A dev_eui_map=()
    local -A dev_nvme_map=()
    local dev

    log_info "Mapping NVMe EUI identifiers..."
    if ! map_device_ids dev_eui_map "${DISK_BY_ID_DIR}/nvme-eui\..*" ""; then
        log_error "Failed to map NVMe EUI identifiers"
        return 1
    fi

    log_info "Mapping NVMe identifiers..."
    if ! map_device_ids dev_nvme_map "${DISK_BY_ID_DIR}/nvme-.*" "nvme-eui\."; then
        log_error "Failed to map NVMe identifiers"
        return 1
    fi

    # Check if array has elements
    if [[ "${#dev_eui_map[@]}" -eq 0 ]]; then
        log_warning "No NVMe EUI identifiers found"
        return 0
    fi

    log_info "Found ${#dev_eui_map[@]} NVMe device(s) with EUI identifiers"
    printf "\n%-15s %-50s %-50s\n" "DEVICE" "EUI-ID" "NVME-ID"
    printf "%s\n" "$(printf '%.0s-' {1..115})"

    for dev in "${!dev_eui_map[@]}"; do
        printf "%-15s %-50s %-50s\n" \
            "${dev}" \
            "${dev_eui_map[${dev}]:-(no eui-ID found)}" \
            "${dev_nvme_map[${dev}]:-(no nvme-ID found)}"
    done | sort -k3
}

main() {
    require_command find readlink grep sort getopt

    parse_args "$@"

    log_debug "Starting device mapping..."

    if [[ "${SHOW_NVME}" == true ]]; then
        show_nvme_eui_mapping
    else
        show_wwn_ata_mapping
    fi

    log_debug "Device mapping completed"
}

main "$@"
