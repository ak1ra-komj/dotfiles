#!/usr/bin/env bash
# ansible localhost \
#    -m copy -a 'src=dotsh/bin/nft-proxy-guard.sh dest=/usr/local/sbin/nft-proxy-guard.sh mode=0755' -v -b
# After changing any constant, run: nft-proxy-guard.sh reload

set -o errexit -o nounset -o errtrace

SCRIPT_FILE="$(readlink -f "${0}")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

readonly TABLE_FAMILY="inet"
readonly TABLE_NAME="proxy_guard"
readonly TABLE_CONF="/etc/nftables.d/proxy_guard.nft"

# Target: transparent proxy port and LAN subnets
readonly PROXY_PORT="7890"
# Multiple subnets are supported; add entries to the arrays as needed.
readonly -a LAN4_SUBNETS=("10.16.0.0/20" "172.16.0.0/16")
readonly -a LAN6_SUBNETS=() # e.g. ("fd00::/8" "fe80::/10") to enable IPv6 rules

# Primary protection: max concurrent connections per source IP (conntrack-based)
# connlimit sets must NOT have timeout — conntrack timers handle element expiry
readonly MAX_CONN="300"
readonly CONNLIMIT4_SET="connlimit_ip4"
readonly CONNLIMIT6_SET="connlimit_ip6"

# Secondary protection: auto-ban on excessive new connection rate
# auto-ban sets use add (not update) so timeout is written once and never refreshed
readonly AUTO_BAN_RATE="300" # new TCP connections per minute triggering a ban
readonly AUTO_BAN_BURST="100" # token bucket burst before rate limit applies
readonly AUTO_BAN_TIMEOUT="10m"
readonly AUTOBAN4_SET="auto_banned_ip4"
readonly AUTOBAN6_SET="auto_banned_ip6"

log_info() { printf "[+] %s\n" "${*}"; }
log_warning() { printf "[!] %s\n" "${*}" >&2; }
log_error() { printf "[-] %s\n" "${*}" >&2; }

usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
    ${SCRIPT_NAME} <command> [args]

DESCRIPTION:
    Automatic nftables mitigation for LAN clients opening excessive concurrent
    TCP connections — covers BOTH transparent proxy (TPROXY, any dport) and
    explicit HTTP/SOCKS5 proxy (direct connections to port ${PROXY_PORT}).

    Detection runs in prerouting (filter priority), BEFORE TPROXY delivery,
    so per-client limits apply globally regardless of proxy mode or destination.

    Protection is fully automatic — no manual IP management required:
      Connlimit: drop new TCP when ct count exceeds ${MAX_CONN} per source IP
      Auto-ban:  if new TCP connections exceed ${AUTO_BAN_RATE}/min (burst ${AUTO_BAN_BURST}),
                 the source IP is banned for ${AUTO_BAN_TIMEOUT} (all TCP dropped)

    LAN4 subnets: ${LAN4_SUBNETS[*]}
    LAN6 subnets: ${LAN6_SUBNETS[*]:-<disabled>}

COMMANDS:
    start             Write config and load nftables table
    stop              Delete nftables table and remove config
    reload            Rewrite config and reload table (required after changing constants)
    list              Show current auto-banned and connlimit-tracked IPs
    unban <ip>        Manually remove an IP from the auto-ban set

EXAMPLES:
    ${SCRIPT_NAME} start
    ${SCRIPT_NAME} list
    ${SCRIPT_NAME} unban 10.16.0.233

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

table_loaded() {
    nft list table "${TABLE_FAMILY}" "${TABLE_NAME}" >/dev/null 2>&1
}

# Join array elements with ", " for use in nftables set element lists
join_elements() {
    local IFS=', '
    printf '%s' "${*}"
}

write_nft_conf() {
    log_info "Writing nftables config to ${TABLE_CONF}"
    mkdir -p "$(dirname "${TABLE_CONF}")"
    local lan4_elements lan6_elements
    lan4_elements="$(join_elements "${LAN4_SUBNETS[@]}")"
    {
        cat <<EOF
table ${TABLE_FAMILY} ${TABLE_NAME} {
    # LAN subnet sets — referenced by rules; interval flag required for prefix matching.
    set lan4_subnets {
        type ipv4_addr
        flags interval
        elements = { ${lan4_elements} }
    }

    # Connlimit tracking sets: NO timeout — conntrack timers handle element expiry.
    # ct count attaches per-element state to conntrack; adding timeout breaks this.
    set ${CONNLIMIT4_SET} {
        type ipv4_addr
        size 65535
        flags dynamic
    }

    # Auto-ban sets: WITH timeout; use add (not update) so the ban timer is
    # written once on first match and never reset by subsequent packets.
    set ${AUTOBAN4_SET} {
        type ipv4_addr
        timeout ${AUTO_BAN_TIMEOUT}
        flags dynamic, timeout
    }

EOF
        if [[ ${#LAN6_SUBNETS[@]} -gt 0 ]]; then
            lan6_elements="$(join_elements "${LAN6_SUBNETS[@]}")"
            cat <<EOF
    set lan6_subnets {
        type ipv6_addr
        flags interval
        elements = { ${lan6_elements} }
    }

    set ${CONNLIMIT6_SET} {
        type ipv6_addr
        size 65535
        flags dynamic
    }

    set ${AUTOBAN6_SET} {
        type ipv6_addr
        timeout ${AUTO_BAN_TIMEOUT}
        flags dynamic, timeout
    }

EOF
        fi
        cat <<EOF
    # Hook: prerouting at filter priority (0).
    # Runs AFTER mangle/prerouting (-150, where TPROXY redirect is applied) but
    # BEFORE packet delivery to INPUT. DROP here prevents the proxy process from
    # ever receiving the packet, protecting both conntrack and the proxy equally.
    #
    # ip protocol tcp (not tcp dport ${PROXY_PORT}) ensures detection covers:
    #   - transparent proxy clients (TPROXY, any dport — original 5-tuple tracked)
    #   - explicit proxy clients (direct tcp dport ${PROXY_PORT})
    chain prerouting {
        type filter hook prerouting priority filter; policy accept;

        # 1. Drop ALL TCP from auto-banned IPs — evaluated first to terminate both
        #    new and existing connections from malicious clients immediately.
        ip saddr @${AUTOBAN4_SET} ip protocol tcp drop
EOF
        if [[ ${#LAN6_SUBNETS[@]} -gt 0 ]]; then
            cat <<EOF
        ip6 saddr @${AUTOBAN6_SET} ip6 nexthdr tcp drop
EOF
        fi
        cat <<EOF

        # 2. Rate detection → auto-ban for ALL new TCP from LAN (any destination).
        #    add semantics: timeout written once; never refreshed by subsequent packets.
        ip saddr @lan4_subnets ip protocol tcp ct state new meter rate_detect_ip4 { ip saddr limit rate over ${AUTO_BAN_RATE}/minute burst ${AUTO_BAN_BURST} packets } add @${AUTOBAN4_SET} { ip saddr timeout ${AUTO_BAN_TIMEOUT} } drop
EOF
        if [[ ${#LAN6_SUBNETS[@]} -gt 0 ]]; then
            cat <<EOF
        ip6 saddr @lan6_subnets ip6 nexthdr tcp ct state new meter rate_detect_ip6 { ip6 saddr limit rate over ${AUTO_BAN_RATE}/minute burst ${AUTO_BAN_BURST} packets } add @${AUTOBAN6_SET} { ip6 saddr timeout ${AUTO_BAN_TIMEOUT} } drop
EOF
        fi
        cat <<EOF

        # 3. Connlimit: drop new TCP when per-source concurrent count exceeds MAX_CONN.
        #    Covers all destinations (transparent + explicit proxy).
        ip saddr @lan4_subnets ip protocol tcp ct state new add @${CONNLIMIT4_SET} { ip saddr ct count over ${MAX_CONN} } drop
EOF
        if [[ ${#LAN6_SUBNETS[@]} -gt 0 ]]; then
            cat <<EOF
        ip6 saddr @lan6_subnets ip6 nexthdr tcp ct state new add @${CONNLIMIT6_SET} { ip6 saddr ct count over ${MAX_CONN} } drop
EOF
        fi
        cat <<EOF
    }
}
EOF
    } >"${TABLE_CONF}"
}

start_table() {
    if table_loaded; then
        log_warning "Table ${TABLE_FAMILY} ${TABLE_NAME} is already loaded — use 'reload' to update"
        return
    fi
    write_nft_conf
    nft -f "${TABLE_CONF}"
    log_info "Table ${TABLE_FAMILY} ${TABLE_NAME} loaded"
}

stop_table() {
    if table_loaded; then
        nft delete table "${TABLE_FAMILY}" "${TABLE_NAME}"
        log_info "Table ${TABLE_FAMILY} ${TABLE_NAME} deleted"
    else
        log_warning "Table ${TABLE_FAMILY} ${TABLE_NAME} is not loaded"
    fi
    if [[ -f "${TABLE_CONF}" ]]; then
        rm -f "${TABLE_CONF}"
        log_info "Config ${TABLE_CONF} removed"
    fi
}

reload_table() {
    if table_loaded; then
        nft delete table "${TABLE_FAMILY}" "${TABLE_NAME}"
    fi
    write_nft_conf
    nft -f "${TABLE_CONF}"
    log_info "Table ${TABLE_FAMILY} ${TABLE_NAME} reloaded"
}

list_sets() {
    if ! table_loaded; then
        log_error "Table ${TABLE_FAMILY} ${TABLE_NAME} is not loaded — run 'start' first"
        exit 1
    fi
    printf '=== %s (auto-ban, timeout %s) ===\n' "${AUTOBAN4_SET}" "${AUTO_BAN_TIMEOUT}"
    nft list set "${TABLE_FAMILY}" "${TABLE_NAME}" "${AUTOBAN4_SET}"
    printf '=== %s (connlimit tracked) ===\n' "${CONNLIMIT4_SET}"
    nft list set "${TABLE_FAMILY}" "${TABLE_NAME}" "${CONNLIMIT4_SET}"
    if [[ ${#LAN6_SUBNETS[@]} -gt 0 ]]; then
        printf '=== %s (auto-ban, timeout %s) ===\n' "${AUTOBAN6_SET}" "${AUTO_BAN_TIMEOUT}"
        nft list set "${TABLE_FAMILY}" "${TABLE_NAME}" "${AUTOBAN6_SET}"
        printf '=== %s (connlimit tracked) ===\n' "${CONNLIMIT6_SET}"
        nft list set "${TABLE_FAMILY}" "${TABLE_NAME}" "${CONNLIMIT6_SET}"
    fi
}

unban_ip() {
    local ip="${1}"
    if ! table_loaded; then
        log_error "Table ${TABLE_FAMILY} ${TABLE_NAME} is not loaded — run 'start' first"
        exit 1
    fi
    local set_name
    if [[ "${ip}" == *:* ]]; then
        set_name="${AUTOBAN6_SET}"
    else
        set_name="${AUTOBAN4_SET}"
    fi
    if nft delete element "${TABLE_FAMILY}" "${TABLE_NAME}" "${set_name}" "{ ${ip} }" 2>/dev/null; then
        log_info "Removed ${ip} from ${set_name}"
    else
        log_warning "${ip} not found in ${set_name}"
    fi
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
        start)
            start_table
            ;;
        stop)
            stop_table
            ;;
        reload)
            reload_table
            ;;
        list | ls | status)
            list_sets
            ;;
        unban)
            if [[ $# -lt 1 ]]; then usage 1; fi
            unban_ip "${1}"
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
