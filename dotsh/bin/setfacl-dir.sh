#!/bin/bash
# author: ak1ra
# date: 2025-12-11
# ansible -m copy -a 'src=dotsh/bin/setfacl-dir.sh dest=/usr/local/bin/setfacl-dir.sh mode="0755"' -v -b localhost

set -euo pipefail

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
    # Cleanup logic can be added here if needed
    exit "${exit_code}"
}

trap cleanup EXIT INT TERM

# Show usage information
usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
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

    Base permissions (--mode):
    - Default: u=rwX,g=rX,o=rX
    - Directories: 755 permissions (rwxr-xr-x)
    - Files: 644 permissions (rw-r--r--)
    - The 'X' permission adds execute only to directories and files that
      already have execute permission set

    ACL permissions (--acl-user, --acl-group):
    - ACL entries are always set to 'rwX' regardless of --mode
    - Directories: ACL user/group gets rwx
    - Files: ACL user/group gets rw-
    - This allows specific users/groups to have consistent access while
      maintaining different base permissions for owner/group/other

EXAMPLES:
    # Basic usage with default permissions
    sudo ${SCRIPT_NAME} -o www-data:www-data -d /var/www/html -u debian

    # Custom base permissions (770 for dirs, 660 for files)
    # ACL user still gets rwX (rwx on dirs, rw- on files)
    sudo ${SCRIPT_NAME} -o nginx:nginx -d /var/www -m u=rwX,g=rwX,o= -u debian

    # Set ACL for both user and group
    sudo ${SCRIPT_NAME} -o root:root -d /opt/app -u debian -g developers

    # Verbose logging
    sudo ${SCRIPT_NAME} -o nginx:nginx -d /var/www --log-level DEBUG

EOF
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="ho:d:m:u:g:"
    local longoptions="help,log-level:,log-format:,owner:,directory:,mode:,acl-user:,acl-group:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage 1
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
                usage 1
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
        usage 1
    fi

    if [[ -z "${DIRECTORY}" ]]; then
        log_error "Missing required parameter: --directory"
        usage 1
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

    # Validate owner user and group exist
    local owner_user="${OWNER%%:*}"
    local owner_group="${OWNER##*:}"
    validate_user "${owner_user}"
    validate_group "${owner_group}"

    # Validate ACL user is not empty when provided and exists
    if [[ -n "${ACL_USER}" ]]; then
        if [[ -z "${ACL_USER// /}" ]]; then
            log_error "ACL user cannot be empty or whitespace"
            exit 1
        fi
        validate_user "${ACL_USER}"
    fi

    # Validate ACL group format if provided and exists
    if [[ -n "${ACL_GROUP}" ]]; then
        if [[ -z "${ACL_GROUP// /}" ]]; then
            log_error "ACL group cannot be empty or whitespace"
            exit 1
        fi
        validate_group "${ACL_GROUP}"
    fi
}

# Set ACLs on directory
setfacl_dir() {
    log_info "Setting ownership to ${OWNER} on ${DIRECTORY}"
    chown --recursive "${OWNER}" "${DIRECTORY}"

    log_info "Setting base permissions with mode: ${MODE}"
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
    require_command getopt setfacl chown chmod getent

    parse_args "$@"

    check_root

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Owner: ${OWNER}, Mode: ${MODE}, ACL User: ${ACL_USER}, ACL Group: ${ACL_GROUP}, Directory: ${DIRECTORY}"

    validate_inputs
    setfacl_dir
}

main "$@"
