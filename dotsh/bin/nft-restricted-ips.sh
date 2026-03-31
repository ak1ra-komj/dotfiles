#!/usr/bin/env bash
# ansible localhost \
#    -m copy -a 'src=dotsh/bin/nft-restricted-ips.sh dest=/usr/local/sbin/nft-restricted-ips.sh mode=0755' -v -b
# 当修改了如 MAX_CONN 等常量时, 需要手动删除 /etc/nftables.d/restricted_ips.nft 或者先 nft delete table inet restricted_ips, 再重新运行脚本

set -o errexit -o nounset -o errtrace

SCRIPT_FILE="$(readlink -f "${0}")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

readonly TABLE_FAMILY="inet"
readonly TABLE_NAME="restricted_ips"
readonly TABLE_CONF="/etc/nftables.d/restricted_ips.nft"
readonly SET4_NAME="restricted_ip4"
readonly SET6_NAME="restricted_ip6"
readonly SET_TIMEOUT="24h"
readonly MAX_CONN="100"

log_info() { printf "[+] %s\n" "${*}"; }
log_warning() { printf "[!] %s\n" "${*}" >&2; }
log_error() { printf "[-] %s\n" "${*}" >&2; }

usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
    ${SCRIPT_NAME} <command> [args]

COMMANDS:
    add <ip> [timeout]    Add IP to restricted set, auto-detects IPv4/IPv6 (e.g. timeout 30m, 2h)
                          IPs in the set are limited to ${MAX_CONN} concurrent connections
    del <ip>              Remove IP from restricted set
    list                  List current restricted IPs (both IPv4 and IPv6)

EXAMPLES:
    ${SCRIPT_NAME} add 10.16.0.233
    ${SCRIPT_NAME} add 10.16.0.233 30m
    ${SCRIPT_NAME} add 2001:db8::1
    ${SCRIPT_NAME} del 10.16.0.233
    ${SCRIPT_NAME} list

EOF
    exit "${exit_code}"
}

require_command() {
    local missing=()
    for c in "${@}"; do
        if ! command -v "${c}" >/dev/null 2>&1; then
            missing+=("${c}")
        fi
    done
    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Required command(s) not found: ${missing[*]}"
        exit 1
    fi
}

check_root() {
    if [[ "${EUID}" -ne 0 ]]; then
        log_error "Please run as root"
        exit 1
    fi
}

write_nft_conf() {
    log_info "Writing nftables config to ${TABLE_CONF}"
    mkdir -p "$(dirname "${TABLE_CONF}")"
    cat >"${TABLE_CONF}" <<EOF
table ${TABLE_FAMILY} ${TABLE_NAME} {
    set ${SET4_NAME} {
        type ipv4_addr
        timeout ${SET_TIMEOUT}
        flags timeout
    }

    set ${SET6_NAME} {
        type ipv6_addr
        timeout ${SET_TIMEOUT}
        flags timeout
    }

    chain input {
        type filter hook input priority filter; policy accept;
        ct state established, related accept
        ip saddr @${SET4_NAME} ct count over ${MAX_CONN} drop
        ip6 saddr @${SET6_NAME} ct count over ${MAX_CONN} drop
    }
}
EOF
}

ensure_env() {
    if [[ ! -f "${TABLE_CONF}" ]]; then
        write_nft_conf
    fi

    if ! nft list table "${TABLE_FAMILY}" "${TABLE_NAME}" >/dev/null 2>&1; then
        log_info "Loading nftables config from ${TABLE_CONF}"
        nft -f "${TABLE_CONF}"
    fi
}

detect_set() {
    local ip="${1}"
    # IPv6 contains colons; everything else treated as IPv4
    if [[ "${ip}" == *:* ]]; then
        printf '%s' "${SET6_NAME}"
    else
        printf '%s' "${SET4_NAME}"
    fi
}

add_ip() {
    local ip="${1}"
    local timeout="${2:-}"
    local set_name
    set_name="$(detect_set "${ip}")"

    if [[ -n "${timeout}" ]]; then
        nft add element "${TABLE_FAMILY}" "${TABLE_NAME}" "${set_name}" "{ ${ip} timeout ${timeout} }"
        log_info "Added ${ip} to ${set_name} with timeout ${timeout}"
    else
        nft add element "${TABLE_FAMILY}" "${TABLE_NAME}" "${set_name}" "{ ${ip} timeout ${SET_TIMEOUT} }"
        log_info "Added ${ip} to ${set_name} (default timeout ${SET_TIMEOUT})"
    fi
}

del_ip() {
    local ip="${1}"
    local set_name
    set_name="$(detect_set "${ip}")"
    if nft delete element "${TABLE_FAMILY}" "${TABLE_NAME}" "${set_name}" "{ ${ip} }" 2>/dev/null; then
        log_info "Removed ${ip} from ${set_name}"
    else
        log_warning "${ip} not found in ${set_name}"
    fi
}

list_ips() {
    printf '=== %s ===\n' "${SET4_NAME}"
    nft list set "${TABLE_FAMILY}" "${TABLE_NAME}" "${SET4_NAME}"
    printf '=== %s ===\n' "${SET6_NAME}"
    nft list set "${TABLE_FAMILY}" "${TABLE_NAME}" "${SET6_NAME}"
}

main() {
    require_command nft
    check_root

    if [[ $# -lt 1 ]]; then
        usage 1
    fi

    local cmd="${1}"
    shift

    case "${cmd}" in
        add)
            if [[ $# -lt 1 ]]; then usage 1; fi
            ensure_env
            add_ip "${@}"
            ;;
        del | delete | rm)
            if [[ $# -lt 1 ]]; then usage 1; fi
            ensure_env
            del_ip "${1}"
            ;;
        list | ls)
            ensure_env
            list_ips
            ;;
        -h | --help)
            usage 0
            ;;
        *)
            usage 1
            ;;
    esac
}

main "${@}"
