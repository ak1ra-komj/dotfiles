#!/usr/bin/env bash
# author: ak1ra
# date: 2025-11-24

set -o errexit -o nounset -o errtrace

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
        printf "\x1b[0;%sm%s\x1b[0m\n" "${color}" "${*}" >&2
    else
        printf "%s\n" "${*}" >&2
    fi
}

log_message() {
    local color="$1"
    local level="$2"
    shift 2

    if [[ "${LOG_PRIORITY[$level]}" -lt "${LOG_PRIORITY[$LOG_LEVEL]}" ]]; then
        return 0
    fi

    local message="${*}"
    case "${LOG_FORMAT}" in
        simple) log_color "${color}" "${message}" ;;
        level) log_color "${color}" "[${level}] ${message}" ;;
        full) log_color "${color}" "[$(date --utc --iso-8601=seconds)][${level}] ${message}" ;;
        *) log_color "${color}" "${message}" ;;
    esac
}

log_error() { log_message 31 "ERROR" "${@}"; }
log_info() { log_message 32 "INFO" "${@}"; }
log_warning() { log_message 33 "WARNING" "${@}"; }
log_debug() { log_message 34 "DEBUG" "${@}"; }
log_critical() { log_message 36 "CRITICAL" "${@}"; }

set_log_level() {
    local level="${1^^}"
    if [[ -z "${LOG_PRIORITY[${level}]:-}" ]]; then
        log_error "Invalid log level: ${1}. Valid levels: ERROR, WARNING, INFO, DEBUG"
        exit 1
    fi
    LOG_LEVEL="${level}"
}

set_log_format() {
    case "${1}" in
        simple | level | full) LOG_FORMAT="${1}" ;;
        *)
            log_error "Invalid log format: ${1}. Valid formats: simple, level, full"
            exit 1
            ;;
    esac
}

require_command() {
    local missing=()
    for c in "${@}"; do
        if ! command -v "${c}" >/dev/null 2>&1; then
            missing+=("${c}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Required command(s) not installed: ${missing[*]}"
        log_error "Please install the missing dependencies and try again"
        exit 1
    fi
}

usage() {
    local exit_code="${1:-0}"
    cat <<EOF
Usage:
    ${SCRIPT_NAME} [OPTIONS]

    Append suffix-modified rules to Kubernetes Ingress JSON file.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -f, --file FILE           JSON file to process (required)
    -s, --suffix SUFFIX       Suffix to add to hostnames
                              Default: -delta
    -i, --in-place            Modify file in-place instead of outputting to stdout

EXAMPLES:
    ${SCRIPT_NAME} -f ingress.json
    ${SCRIPT_NAME} -f ingress.json -s '-test'
    ${SCRIPT_NAME} -f ingress.json -i
    ${SCRIPT_NAME} --log-level DEBUG --log-format full -f ingress.json

EOF
    exit "${exit_code}"
}

parse_args() {
    local args
    local options="hf:s:i"
    local longoptions="help,log-level:,log-format:,file:,suffix:,in-place"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g FILE=""
    declare -g SUFFIX="-delta"
    declare -g IN_PLACE="false"

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
            -f | --file)
                FILE="$2"
                shift 2
                ;;
            -s | --suffix)
                SUFFIX="$2"
                shift 2
                ;;
            -i | --in-place)
                IN_PLACE="true"
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
}

# Validate required parameters
validate_params() {
    if [[ -z "${FILE}" ]]; then
        log_error "File parameter is required"
        usage
    fi

    if [[ ! -f "${FILE}" ]]; then
        log_error "File '${FILE}' does not exist"
        exit 1
    fi

    log_debug "FILE=${FILE}, SUFFIX=${SUFFIX}, IN_PLACE=${IN_PLACE}"
}

# Process the Ingress JSON file
process_ingress() {
    local file="$1"
    local suffix="$2"
    local in_place="$3"

    log_info "Processing Ingress file: ${file}"
    log_info "Adding suffix: ${suffix}"

    # shellcheck disable=SC2016
    local jq_filter='
def add_suffix_to_host(host):
    host | capture("^(?<subdomain>[^.]+)\\.(?<domain>.+)$")
    | "\(.subdomain)\($suffix).\(.domain)";

.spec.rules |= . + [.[] | .host = add_suffix_to_host(.host)] |
if .spec.tls and (.spec.tls | length) > 0 then
    .spec.tls[0].hosts |= . + [.[] | add_suffix_to_host(.)]
else
    .
end
'

    if [[ "${in_place}" == "true" ]]; then
        local temp_file
        temp_file=$(mktemp)

        if ! jq --indent 4 --arg suffix "${suffix}" "${jq_filter}" "${file}" >"${temp_file}"; then
            rm -f "${temp_file}"
            log_error "Failed to process JSON file"
            exit 1
        fi

        if ! mv "${temp_file}" "${file}"; then
            rm -f "${temp_file}"
            log_error "Failed to write changes to file"
            exit 1
        fi

        log_info "File modified in-place: ${file}"
    else
        if ! jq --indent 4 --arg suffix "${suffix}" "${jq_filter}" "${file}"; then
            log_error "Failed to process JSON file"
            exit 1
        fi
    fi

    log_info "Processing completed successfully"
}

main() {
    require_command jq getopt

    parse_args "$@"
    validate_params

    process_ingress "${FILE}" "${SUFFIX}" "${IN_PLACE}"
}

main "${@}"
