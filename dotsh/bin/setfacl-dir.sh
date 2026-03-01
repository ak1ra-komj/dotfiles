#!/usr/bin/env bash
# author: ak1ra
# date: 2025-12-11
# ansible -m copy -a 'src=dotsh/bin/setfacl-dir.sh dest=/usr/local/bin/setfacl-dir.sh mode="0755"' -v -b localhost

set -o errexit -o nounset -o errtrace

SCRIPT_NAME="$(basename "${0}")"

err() { echo "${SCRIPT_NAME}: ${*}" >&2; }

# Check if required commands are available
require_command() {
    local missing=()
    for c in "${@}"; do
        if ! command -v "${c}" >/dev/null 2>&1; then
            missing+=("${c}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        err "Required command(s) not installed: ${missing[*]}"
        exit 1
    fi
}

usage() {
    local exit_code="${1:-0}"
    cat <<USAGE
USAGE:
    ${SCRIPT_NAME} [OPTIONS] --owner OWNER --directory DIR

    Set file permissions and ACLs for a directory tree.
    This script requires root privileges. Run with sudo.

OPTIONS:
    -h, --help                Show this help message
    -o, --owner OWNER         Set owner (format: user:group) [REQUIRED]
    -d, --directory DIR       Target directory [REQUIRED]
    -m, --mode MODE           Permission mode in symbolic format
                              Default: u=rwX,g=rX,o=rX (755 for dirs, 644 for files)
    -u, --acl-user USER       Set ACL user (can combine with --acl-group)
                              Default: \$SUDO_USER or current user
    -g, --acl-group GROUP     Set ACL group (can combine with --acl-user)
                              Default: none

DESCRIPTION:
    Sets ownership, permissions, and ACLs for all files and directories
    within the target directory.

    Base permissions (--mode):
    - Default: u=rwX,g=rX,o=rX
    - Directories: 755 (rwxr-xr-x), Files: 644 (rw-r--r--)
    - 'X' adds execute only to directories and already-executable files

    ACL permissions (--acl-user, --acl-group):
    - ACL entries are always set to 'rwX' regardless of --mode
    - Directories: rwx, Files: rw-

EXAMPLES:
    sudo ${SCRIPT_NAME} -o www-data:www-data -d /var/www/html -u debian
    sudo ${SCRIPT_NAME} -o nginx:nginx -d /var/www -m u=rwX,g=rwX,o= -u debian
    sudo ${SCRIPT_NAME} -o root:root -d /opt/app -u debian -g developers

USAGE
    exit "${exit_code}"
}

parse_args() {
    local args
    local options="ho:d:m:u:g:"
    local longoptions="help,owner:,directory:,mode:,acl-user:,acl-group:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g OWNER=""
    declare -g DIRECTORY=""
    declare -g MODE="u=rwX,g=rX,o=rX"
    declare -g ACL_USER="${SUDO_USER:-${USER}}"
    declare -g ACL_GROUP=""

    while true; do
        case "${1}" in
            -h | --help) usage 0 ;;
            -o | --owner)
                OWNER="${2}"
                shift 2
                ;;
            -d | --directory)
                DIRECTORY="${2}"
                shift 2
                ;;
            -m | --mode)
                MODE="${2}"
                shift 2
                ;;
            -u | --acl-user)
                ACL_USER="${2}"
                shift 2
                ;;
            -g | --acl-group)
                ACL_GROUP="${2}"
                shift 2
                ;;
            --)
                shift
                break
                ;;
            *)
                err "Unexpected option: ${1}"
                usage 1
                ;;
        esac
    done
}

validate_inputs() {
    if [[ -z "${OWNER}" ]]; then
        err "Missing required parameter: --owner"
        usage 1
    fi

    if [[ -z "${DIRECTORY}" ]]; then
        err "Missing required parameter: --directory"
        usage 1
    fi

    if [[ ! -d "${DIRECTORY}" ]]; then
        err "Directory does not exist: ${DIRECTORY}"
        exit 1
    fi

    if ! [[ "${OWNER}" =~ ^[a-zA-Z0-9_-]+:[a-zA-Z0-9_-]+$ ]]; then
        err "Invalid owner format: ${OWNER}. Expected format: user:group"
        exit 1
    fi

    local owner_user="${OWNER%%:*}"
    local owner_group="${OWNER##*:}"

    if ! getent passwd "${owner_user}" >/dev/null 2>&1; then
        err "User does not exist: ${owner_user}"
        exit 1
    fi

    if ! getent group "${owner_group}" >/dev/null 2>&1; then
        err "Group does not exist: ${owner_group}"
        exit 1
    fi

    if [[ -n "${ACL_USER}" ]] && ! getent passwd "${ACL_USER}" >/dev/null 2>&1; then
        err "ACL user does not exist: ${ACL_USER}"
        exit 1
    fi

    if [[ -n "${ACL_GROUP}" ]] && ! getent group "${ACL_GROUP}" >/dev/null 2>&1; then
        err "ACL group does not exist: ${ACL_GROUP}"
        exit 1
    fi
}

setfacl_dir() {
    echo "Setting ownership to ${OWNER} on ${DIRECTORY}"
    chown --recursive "${OWNER}" "${DIRECTORY}"

    echo "Setting base permissions: ${MODE}"
    chmod --recursive "${MODE}" "${DIRECTORY}"

    local acl_rules=()
    [[ -n "${ACL_USER}" ]] && acl_rules+=("user:${ACL_USER}:rwX")
    [[ -n "${ACL_GROUP}" ]] && acl_rules+=("group:${ACL_GROUP}:rwX")

    if [[ ${#acl_rules[@]} -gt 0 ]]; then
        local acl_modify
        acl_modify="$(
            IFS=','
            echo "${acl_rules[*]}"
        )"
        echo "Setting ACLs: ${acl_modify}"
        setfacl --recursive --modify="${acl_modify}" "${DIRECTORY}"
    fi

    echo "Done."
}

main() {
    if [[ "${EUID}" -ne 0 ]]; then
        err "This script must be run as root. Use: sudo ${SCRIPT_NAME}"
        exit 1
    fi

    require_command getopt setfacl chown chmod getent

    parse_args "${@}"
    validate_inputs
    setfacl_dir
}

main "${@}"
