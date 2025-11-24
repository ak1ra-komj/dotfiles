#!/bin/bash

set -o errexit -o nounset -o pipefail

SCRIPT_NAME="$(basename "$(readlink -f "$0")")"

# Logging functions
log_color() {
    local color="$1"
    shift
    if [ -t 2 ]; then
        printf "\x1b[0;%sm%s\x1b[0m\n" "${color}" "$*" >&2
    else
        printf "%s\n" "$*" >&2
    fi
}

log_time() {
    local color="$1"
    shift
    log_color "$color" "[$(date -u +%Y-%m-%dT%H:%M:%S+0000)]$*"
}

log_error() {
    local RED=31
    log_color "$RED" "[ERROR] $*"
}

log_warning() {
    local YELLOW=33
    log_color "$YELLOW" "[WARNING] $*"
}

log_info() {
    local WHITE=37
    log_color "$WHITE" "[INFO] $*"
}

log_debug() {
    local BLUE=34
    if [ "${DEBUG:-false}" = "true" ]; then
        log_color "$BLUE" "[DEBUG] $*"
    fi
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

    A getopt example shell script

OPTIONS:
    -h, --help           Show this help message
    -d, --debug          Enable debug logging
    -a, --alpha arg      Set ALPHA
    -b, --bravo arg      Set BRAVO
    -c, --charlie arg    Set CHARLIE

EXAMPLES:
    ${SCRIPT_NAME} --alpha bravo
    ${SCRIPT_NAME} --bravo charlie --charlie alpha

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="hda:b:c:"
    local longoptions="help,debug,alpha:,bravo:,charlie:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g DEBUG=false
    declare -g -a REST_ARGS=()

    declare -g ALPHA="alpha"
    declare -g BRAVO="bravo"
    declare -g CHARLIE="charlie"

    while true; do
        case "$1" in
            -h | --help)
                usage
                ;;
            -d | --debug)
                DEBUG="true"
                shift
                ;;
            -a | --alpha)
                ALPHA="$2"
                shift 2
                ;;
            -b | --bravo)
                BRAVO="$2"
                shift 2
                ;;
            -c | --charlie)
                CHARLIE="$2"
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

    # Capture remaining positional arguments
    REST_ARGS=("$@")
}

main() {
    require_command getopt

    parse_args "$@"

    log_info "ALPHA=${ALPHA}"
    log_info "BRAVO=${BRAVO}"
    log_info "CHARLIE=${CHARLIE}"

    # https://www.shellcheck.net/wiki/SC2145
    if [[ ${#REST_ARGS[@]} -gt 0 ]]; then
        log_debug "Remaining arguments: ${REST_ARGS[*]}"
    fi
}

main "$@"
