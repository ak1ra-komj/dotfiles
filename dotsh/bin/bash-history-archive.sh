#!/bin/bash

set -euo pipefail

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

# Logging configuration
declare -g LOG_LEVEL="INFO"
declare -g LOG_FORMAT="simple"
declare -g TEMP_FILE=""

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
    local level="${1^^}"
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
    local missing=()
    for c in "$@"; do
        if ! command -v "$c" >/dev/null 2>&1; then
            missing+=("$c")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Required command(s) not installed: ${missing[*]}"
        log_error "Please install the missing dependencies and try again"
        exit 1
    fi
}

# Cleanup handler
cleanup() {
    local exit_code=$?
    # Remove temporary files if they exist
    if [[ -n "${TEMP_FILE:-}" ]] && [[ -f "${TEMP_FILE}" ]]; then
        rm -f "${TEMP_FILE}"
        log_debug "Cleaned up temporary file: ${TEMP_FILE}"
    fi
    exit "${exit_code}"
}

trap cleanup EXIT INT TERM

# Show usage information
usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
    ${SCRIPT_NAME} [OPTIONS]

    Archive bash history when it exceeds a specified number of lines.
    Older lines are moved to an archive file to keep the history manageable.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              Default: simple
    --max-lines LINES         Maximum number of lines to keep in history
                              Default: 10000
    --history-file FILE       Path to bash history file
                              Default: ~/.bash_history
    --archive-file FILE       Path to history archive file
                              Default: ~/.bash_history.archive

EXAMPLES:
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --max-lines 5000
    ${SCRIPT_NAME} --log-level DEBUG --log-format full
    ${SCRIPT_NAME} --history-file ~/.custom_history --archive-file ~/.custom_archive

EOF
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="h"
    local longoptions="help,log-level:,log-format:,max-lines:,history-file:,archive-file:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g MAX_LINES=10000
    declare -g HISTORY_FILE="${HOME}/.bash_history"
    declare -g ARCHIVE_FILE="${HOME}/.bash_history.archive"

    while true; do
        case "$1" in
            -h | --help)
                usage 0
                ;;
            --log-level)
                set_log_level "$2"
                shift 2
                ;;
            --log-format)
                set_log_format "$2"
                shift 2
                ;;
            --max-lines)
                MAX_LINES="$2"
                shift 2
                ;;
            --history-file)
                HISTORY_FILE="$2"
                shift 2
                ;;
            --archive-file)
                ARCHIVE_FILE="$2"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                log_error "Unexpected option: $1"
                usage 1
                ;;
        esac
    done
}

# Archive bash history
archive_history() {
    # Validate max_lines is a positive integer
    if ! [[ "${MAX_LINES}" =~ ^[0-9]+$ ]] || [[ "${MAX_LINES}" -le 0 ]]; then
        log_error "Invalid max-lines value: ${MAX_LINES}. Must be a positive integer."
        exit 1
    fi

    # Check if history file exists
    if [[ ! -f "${HISTORY_FILE}" ]]; then
        log_warning "History file does not exist: ${HISTORY_FILE}"
        exit 0
    fi

    # Set secure umask
    umask 077

    # Count lines in history file
    local linecount
    linecount=$(wc -l <"${HISTORY_FILE}")
    log_debug "History file has ${linecount} lines (max: ${MAX_LINES})"

    if ((linecount > MAX_LINES)); then
        local prune_lines=$((linecount - MAX_LINES))
        log_info "Archiving ${prune_lines} lines from history file"

        # Create temporary file
        declare -g TEMP_FILE="${HISTORY_FILE}.tmp$$"

        # Archive old lines
        if ! head -n "${prune_lines}" "${HISTORY_FILE}" >>"${ARCHIVE_FILE}"; then
            log_error "Failed to append to archive file: ${ARCHIVE_FILE}"
            exit 1
        fi

        # Remove archived lines from history
        if ! sed -e "1,${prune_lines}d" "${HISTORY_FILE}" >"${TEMP_FILE}"; then
            log_error "Failed to create temporary history file"
            exit 1
        fi

        # Replace history file with trimmed version
        if ! mv "${TEMP_FILE}" "${HISTORY_FILE}"; then
            log_error "Failed to update history file"
            exit 1
        fi

        log_info "Successfully archived ${prune_lines} lines to ${ARCHIVE_FILE}"
    else
        log_debug "History file is within limits, no archiving needed"
    fi
}

main() {
    require_command getopt wc head sed

    parse_args "$@"

    log_debug "Configuration: max_lines=${MAX_LINES}, history_file=${HISTORY_FILE}, archive_file=${ARCHIVE_FILE}"

    archive_history
}

main "$@"
