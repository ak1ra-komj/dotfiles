#!/bin/bash
# author: ak1ra
# date: 2025-12-11
# ansible localhost -m copy -a 'src=dotsh/bin/setfacl-dir.sh dest=/usr/local/bin/setfacl-dir.sh mode="0755"' -v -b

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
    ${SCRIPT_NAME} [OPTIONS] --owner OWNER --directory DIR

    Set file permissions and ACLs for a directory tree

    This script requires root privileges. Run with sudo.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -o, --owner OWNER         Set owner (format: user:group) [REQUIRED]
    -d, --directory DIR       Target directory [REQUIRED]
    -m, --mode MODE           Permission mode in symbolic format
                              Default: u=rwX,g=rX,o=rX (755 for dirs, 644 for files)
    -u, --acl-user USER       Set ACL user (can combine with --acl-group)
                              Default: \$SUDO_USER or current user
    -g, --acl-group GROUP     Set ACL group (can combine with --acl-user)
                              Default: none

DESCRIPTION:
    This script sets ownership, permissions, and ACLs for all files and
    directories within the target directory.

    Default behavior (u=rwX,g=rX,o=rX):
    - Directories: 755 permissions (rwxr-xr-x)
    - Files: 644 permissions (rw-r--r--)

    The 'X' permission adds execute only to directories and files that
    already have execute permission set.

EXAMPLES:
    # Basic usage with default permissions
    sudo ${SCRIPT_NAME} -o www-data:www-data -u debian -d /var/www/html

    # Custom permissions (770 for dirs, 660 for files)
    sudo ${SCRIPT_NAME} -o nginx:nginx -d /var/www -m u=rwX,g=rwX,o=

    # Set ACL for both user and group
    sudo ${SCRIPT_NAME} -o root:root -d /opt/app -u dev1 -g developers

    # Verbose logging
    sudo ${SCRIPT_NAME} -o nginx:nginx -d /var/www --log-level DEBUG

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="ho:u:g:d:m:"
    local longoptions="help,log-level:,log-format:,owner:,acl-user:,acl-group:,directory:,mode:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"

    declare -g OWNER=""
    declare -g DIRECTORY=""
    declare -g MODE="u=rwX,g=rX,o=rX"
    declare -g ACL_USER="${SUDO_USER:-${USER}}"
    declare -g ACL_GROUP=""

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
            -o | --owner)
                OWNER="$2"
                shift 2
                ;;
            -d | --directory)
                DIRECTORY="$2"
                shift 2
                ;;
            -m | --mode)
                MODE="$2"
                shift 2
                ;;
            -u | --acl-user)
                ACL_USER="$2"
                shift 2
                ;;
            -g | --acl-group)
                ACL_GROUP="$2"
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
}

# Check if running as root
check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "This script must be run as root. Use: sudo ${SCRIPT_NAME}"
        exit 1
    fi
}

# Validate user exists
validate_user() {
    local user="$1"
    if ! getent passwd "${user}" >/dev/null 2>&1; then
        log_error "User does not exist: ${user}"
        exit 1
    fi
}

# Validate group exists
validate_group() {
    local group="$1"
    if ! getent group "${group}" >/dev/null 2>&1; then
        log_error "Group does not exist: ${group}"
        exit 1
    fi
}

# Validate inputs
validate_inputs() {
    # Check required parameters
    if [[ -z "${OWNER}" ]]; then
        log_error "Missing required parameter: --owner"
        usage
    fi

    if [[ -z "${DIRECTORY}" ]]; then
        log_error "Missing required parameter: --directory"
        usage
    fi

    # Validate directory exists
    if [[ ! -d "${DIRECTORY}" ]]; then
        log_error "Directory does not exist: ${DIRECTORY}"
        exit 1
    fi

    # Validate owner format
    if ! [[ "${OWNER}" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid owner format: ${OWNER}. Expected format: user:group"
        exit 1
    fi

    # Validate ACL user is not empty when provided
    if [[ -n "${ACL_USER}" && -z "${ACL_USER// /}" ]]; then
        log_error "ACL user cannot be empty or whitespace"
        exit 1
    fi

    # Validate ACL group format if provided
    if [[ -n "${ACL_GROUP}" && -z "${ACL_GROUP// /}" ]]; then
        log_error "ACL group cannot be empty or whitespace"
        exit 1
    fi
}

# Set ACLs on directory
setfacl_dir() {
    log_info "Setting ownership to ${OWNER} on ${DIRECTORY}"
    chown --recursive "${OWNER}" "${DIRECTORY}"

    log_info "Setting permissions with mode: ${MODE}"
    chmod --recursive "${MODE}" "${DIRECTORY}"

    # Build setfacl command with user and/or group ACLs
    local acl_rules=()
    if [[ -n "${ACL_USER}" ]]; then
        acl_rules+=("user:${ACL_USER}:rwX")
        log_info "Setting ACL for user: ${ACL_USER} (rwX)"
    fi
    if [[ -n "${ACL_GROUP}" ]]; then
        acl_rules+=("group:${ACL_GROUP}:rwX")
        log_info "Setting ACL for group: ${ACL_GROUP} (rwX)"
    fi

    if [[ ${#acl_rules[@]} -gt 0 ]]; then
        local acl_modify="${acl_rules[*]}"
        acl_modify="${acl_modify// /,}"
        setfacl --recursive --modify="${acl_modify}" "${DIRECTORY}"
    fi

    log_info "Successfully configured permissions and ACLs"
}

main() {
    require_command getopt setfacl chown chmod

    parse_args "$@"

    check_root

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Owner: ${OWNER}, Mode: ${MODE}, ACL User: ${ACL_USER}, ACL Group: ${ACL_GROUP}, Directory: ${DIRECTORY}"

    validate_inputs
    setfacl_dir
}

main "$@"
