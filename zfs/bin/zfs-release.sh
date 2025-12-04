#!/bin/bash
# Author: ak1ra
# Date: 2024-11-15

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
    ${SCRIPT_NAME} [OPTIONS] <rootfs>

    Execute 'zfs release' command on all snapshots from rootfs recursively.
    Warning: Don't use this if you don't know what you are doing.
    The rootfs argument cannot end with a slash (/).

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple

ARGUMENTS:
    rootfs                    ZFS filesystem to process recursively

EXAMPLES:
    ${SCRIPT_NAME} main
    ${SCRIPT_NAME} main/zrepl/sink
    ${SCRIPT_NAME} --log-level DEBUG --log-format full main

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="h"
    local longoptions="help,log-level:,log-format:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g ROOTFS=""

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
    if [[ $# -ne 1 ]]; then
        log_error "Expected exactly one argument: <rootfs>"
        usage
    fi

    ROOTFS="$1"

    # Validate rootfs doesn't end with slash
    if [[ "${ROOTFS}" =~ /$ ]]; then
        log_error "rootfs cannot end with a slash (/): ${ROOTFS}"
        exit 1
    fi
}

# Release all holds on snapshots recursively
zfs_release() {
    log_info "Processing snapshots for rootfs: ${ROOTFS}"

    local snapshots
    if ! readarray -t snapshots < <(zfs list -t snapshot -Hr -oname "${ROOTFS}" 2>&1); then
        log_error "Failed to list snapshots for ${ROOTFS}"
        return 1
    fi

    if [[ ${#snapshots[@]} -eq 0 ]]; then
        log_warning "No snapshots found for ${ROOTFS}"
        return 0
    fi

    log_info "Found ${#snapshots[@]} snapshot(s)"

    local snapshot_count=0
    local hold_count=0

    for snapshot in "${snapshots[@]}"; do
        log_debug "Processing snapshot: ${snapshot}"
        local holds
        if ! readarray -t holds < <(zfs holds -H "${snapshot}" 2>&1 | awk '{print $2}'); then
            log_warning "Failed to list holds for ${snapshot}"
            continue
        fi

        if [[ ${#holds[@]} -eq 0 ]]; then
            log_debug "No holds found for ${snapshot}"
            continue
        fi

        ((snapshot_count++))

        for hold in "${holds[@]}"; do
            log_info "Releasing hold '${hold}' from snapshot '${snapshot}'"
            if zfs release "${hold}" "${snapshot}"; then
                ((hold_count++))
                log_debug "Successfully released hold '${hold}'"
            else
                log_error "Failed to release hold '${hold}' from '${snapshot}'"
            fi
        done
    done

    log_info "Release complete: ${hold_count} hold(s) released from ${snapshot_count} snapshot(s)"
}

main() {
    require_command getopt zfs awk

    parse_args "$@"

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Rootfs: ${ROOTFS}"

    zfs_release
}

main "$@"
