#!/bin/bash
# author: ak1ra
# date: 2025-11-13

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
    ${SCRIPT_NAME} [OPTIONS]

    Show Kubernetes TLS secrets expiring soon (non-self-signed).

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -d, --days DAYS           Show certificates expiring within DAYS
                              Default: 30

EXAMPLES:
    ${SCRIPT_NAME} --days 7
    ${SCRIPT_NAME} --days 30
    ${SCRIPT_NAME} --log-level DEBUG --log-format full

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="hd:"
    local longoptions="help,log-level:,log-format:,days:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"

    declare -g LIMIT_DAYS=30

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
            -d | --days)
                LIMIT_DAYS="$2"
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

# Validate parameters
validate_params() {
    if ! [[ "${LIMIT_DAYS}" =~ ^[0-9]+$ ]] || [[ "${LIMIT_DAYS}" -le 0 ]]; then
        log_error "Invalid days value: ${LIMIT_DAYS}"
        exit 2
    fi
    log_debug "LIMIT_DAYS=${LIMIT_DAYS}"
}

# Check TLS secrets for expiration
check_tls_secrets() {
    local tempdir
    tempdir="$(mktemp -d /tmp/secrets.XXXXXX)"
    trap 'rm -rf "${tempdir}"' EXIT

    local now limit
    now="$(date +%s)"
    limit="$((LIMIT_DAYS * 24 * 3600))"

    while read -r namespace name crt; do
        [[ -n "${crt}" ]] || continue

        local pem="${tempdir}/${namespace}_${name}.pem"
        echo "${crt}" | base64 -d >"${pem}" 2>/dev/null || continue

        local subject issuer not_after expire_ts
        subject=$(openssl x509 -in "${pem}" -noout -subject 2>/dev/null | sed 's/^subject= //')
        issuer=$(openssl x509 -in "${pem}" -noout -issuer 2>/dev/null | sed 's/^issuer= //')
        not_after=$(openssl x509 -in "${pem}" -noout -enddate 2>/dev/null | cut -d= -f2)
        expire_ts=$(date -d "${not_after}" +%s 2>/dev/null || true)

        # Only non-self-signed certs expiring within LIMIT_DAYS
        if [[ "${subject}" != "${issuer}" ]] && ((expire_ts - now < limit)); then
            echo "=== ${namespace}/${name} ==="
            echo "Subject: ${subject}"
            echo "Issuer : ${issuer}"
            log_warning "Not after: $(date --utc +%Y-%m-%dT%H:%M:%S%Z --date="${not_after}")"
            echo
        fi
    done < <(
        kubectl get secrets --all-namespaces --output=jsonpath='
        {range .items[?(@.type=="kubernetes.io/tls")]}
            {.metadata.namespace} {.metadata.name} {.data.tls\.crt}{"\n"}
        {end}'
    )
}

main() {
    require_command kubectl base64 openssl getopt

    parse_args "$@"
    validate_params

    check_tls_secrets
}

main "$@"
