#!/bin/bash

set -o errexit -o nounset -o pipefail

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

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
    ${SCRIPT_NAME} [OPTIONS] <source_zpool> <destination_zpool>

    Delete zvols in the destination zpool that are duplicates of the source zpool.
    This script identifies zvols matching the pattern '/vm-[0-9]+' in the source
    zpool and checks if corresponding zvols exist in the destination zpool.

    WARNING: This operation is destructive and cannot be undone!
    By default, the script runs in dry-run mode. Use --apply to execute deletions.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    --apply                   Actually execute the deletions (default is dry-run)

ARGUMENTS:
    source_zpool              Source ZFS pool to scan for VM zvols
    destination_zpool         Destination ZFS pool to check for duplicates

EXAMPLES:
    ${SCRIPT_NAME} data0 tank
    ${SCRIPT_NAME} --apply data0 tank
    ${SCRIPT_NAME} --log-level DEBUG --log-format full --apply data0 tank

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="h"
    local longoptions="help,log-level:,log-format:,apply"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g ZPOOL_SRC=""
    declare -g ZPOOL_DEST=""
    declare -g APPLY=false

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
        log_error "Expected exactly two arguments: <source_zpool> <destination_zpool>"
        usage
    fi

    ZPOOL_SRC="$1"
    ZPOOL_DEST="$2"
}

# Validate that zpools exist
validate_zpools() {
    if [[ ! -d "/dev/${ZPOOL_SRC}" ]]; then
        log_error "Source zpool does not exist: ${ZPOOL_SRC}"
        exit 1
    fi

    if [[ ! -d "/dev/${ZPOOL_DEST}" ]]; then
        log_error "Destination zpool does not exist: ${ZPOOL_DEST}"
        exit 1
    fi

    log_debug "Validated zpools: ${ZPOOL_SRC} and ${ZPOOL_DEST}"
}

# Delete duplicate zvols from destination pool
delete_duplicates_zvol() {
    log_info "Scanning for duplicate zvols from '${ZPOOL_SRC}' in '${ZPOOL_DEST}'"

    local zvol_from_zpool_src
    if ! readarray -t zvol_from_zpool_src < <(
        zfs list -H -o name -r "${ZPOOL_SRC}" 2>&1 |
            grep -E '/vm-[0-9]+' |
            sed 's%'"${ZPOOL_SRC}"'%'"${ZPOOL_DEST}"'%'
    ); then
        log_error "Failed to list zvols from ${ZPOOL_SRC}"
        exit 1
    fi

    if [[ ${#zvol_from_zpool_src[@]} -eq 0 ]]; then
        log_info "No VM zvols found in source zpool"
        return 0
    fi

    log_debug "Found ${#zvol_from_zpool_src[@]} potential duplicate(s) to check"

    local zvol_to_delete=()
    for zvol in "${zvol_from_zpool_src[@]}"; do
        if [[ -b "/dev/${zvol}" ]]; then
            log_info "Found duplicate zvol: ${zvol}"
            zvol_to_delete+=("${zvol}")
        else
            log_debug "Zvol does not exist in destination: ${zvol}"
        fi
    done

    if [[ ${#zvol_to_delete[@]} -eq 0 ]]; then
        log_info "No duplicate zvols found in destination zpool"
        return 0
    fi

    log_warning "Found ${#zvol_to_delete[@]} duplicate zvol(s) to delete:"
    for zvol in "${zvol_to_delete[@]}"; do
        log_warning "  - ${zvol}"
    done

    if [[ "${APPLY}" == false ]]; then
        log_info "Dry-run mode: showing commands that would be executed"
        log_info "Use --apply flag to actually execute the deletions"
        for zvol in "${zvol_to_delete[@]}"; do
            echo "zfs destroy -r ${zvol}"
        done
        return 0
    fi

    log_critical "WARNING: This will permanently destroy ${#zvol_to_delete[@]} zvol(s)!"
    log_critical "This operation CANNOT be undone!"

    local choice
    read -r -p "Type 'YES_I_WANT_TO_DESTROY_MY_ZVOL' to continue: " choice

    if [[ "${choice}" != "YES_I_WANT_TO_DESTROY_MY_ZVOL" ]]; then
        log_info "Operation cancelled by user"
        return 0
    fi

    log_info "Proceeding with zvol destruction..."
    local success_count=0
    local failure_count=0

    for zvol in "${zvol_to_delete[@]}"; do
        if [[ -b "/dev/${zvol}" ]]; then
            log_info "Destroying: ${zvol}"
            if zfs destroy -r "${zvol}"; then
                ((success_count++))
                log_info "Successfully destroyed: ${zvol}"
            else
                ((failure_count++))
                log_error "Failed to destroy: ${zvol}"
            fi
        else
            log_warning "Zvol no longer exists, skipping: ${zvol}"
        fi
    done

    log_info "Deletion complete: ${success_count} succeeded, ${failure_count} failed"
}

main() {
    require_command getopt zfs grep sed

    parse_args "$@"

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Source zpool: ${ZPOOL_SRC}"
    log_debug "Destination zpool: ${ZPOOL_DEST}"
    log_debug "Apply mode: ${APPLY}"

    validate_zpools
    delete_duplicates_zvol
}

main "$@"
