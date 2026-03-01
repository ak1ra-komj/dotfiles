#!/usr/bin/env bash
# Author: ak1ra
# Date: 2020-05-22
# Update:
#   * 2021-03-12, add --invert-match option
#   * 2023-06-26, add --help option
#   * 2025-11-18, refactoring docker-rm.sh

set -o errexit -o nounset -o errtrace

SCRIPT_FILE="$(readlink -f "${0}")"
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
    local color="${1}"
    shift
    if [[ -t 2 ]]; then
        printf "\x1b[0;%sm%s\x1b[0m\n" "${color}" "${*}" >&2
    else
        printf "%s\n" "${*}" >&2
    fi
}

log_message() {
    local color="${1}"
    local level="${2}"
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

# Set log level with validation
set_log_level() {
    local level="${1^^}"
    if [[ -z "${LOG_PRIORITY[${level}]:-}" ]]; then
        log_error "Invalid log level: ${1}. Valid levels: ERROR, WARNING, INFO, DEBUG"
        exit 1
    fi
    LOG_LEVEL="${level}"
}

# Set log format with validation
set_log_format() {
    case "${1}" in
        simple | level | full)
            LOG_FORMAT="${1}"
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

# Show usage information
usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
    ${SCRIPT_NAME} [OPTIONS] [PATTERN]

    Remove Docker containers and images based on patterns.
    Default behavior is dry-run mode (use --apply to execute).

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    --apply                   Actually delete images (default: dry-run)
    -v, --invert-match        Invert the pattern match

ARGUMENTS:
    PATTERN                   Image name pattern to match (default: <none>)
                              Use regex patterns for complex matching

EXAMPLES:
    ${SCRIPT_NAME}                                  # Dry-run, match <none> images
    ${SCRIPT_NAME} --apply                          # Apply deletion of <none> images
    ${SCRIPT_NAME} 'openjdk-base'                   # Dry-run, match 'openjdk-base'
    ${SCRIPT_NAME} --apply 'k8s.gcr.io|quay.io'     # Delete matching images
    ${SCRIPT_NAME} -v 'important' --apply           # Delete all except 'important'
    ${SCRIPT_NAME} --log-level DEBUG --log-format level

EOF
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="hv"
    local longoptions="help,log-level:,log-format:,apply,invert-match"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g APPLY="false"
    declare -g INVERT_MATCH="false"
    declare -g PATTERN="<none>"

    while true; do
        case "${1}" in
            -h | --help)
                usage
                ;;
            --log-level)
                set_log_level "${2}"
                shift 2
                ;;
            --log-format)
                set_log_format "${2}"
                shift 2
                ;;
            --apply)
                APPLY="true"
                shift
                ;;
            -v | --invert-match)
                INVERT_MATCH="true"
                shift
                ;;
            --)
                shift
                break
                ;;
            *)
                log_error "Unexpected option: ${1}"
                usage 1
                ;;
        esac
    done

    if [[ ${#} -gt 0 ]]; then
        PATTERN="${1}"
    fi
}

# Remove exited Docker containers
docker_rm_containers() {
    log_debug "Checking for exited containers..."

    local -a exited_containers=()
    if ! readarray -t exited_containers < <(
        docker ps -a --format '{{.ID}} {{.Status}}' |
            awk '/Exited/ {print $1}'
    ); then
        log_error "Failed to list Docker containers"
        return 1
    fi

    if [[ ${#exited_containers[@]} -eq 0 ]]; then
        log_info "No exited containers found"
        return 0
    fi

    log_info "Found ${#exited_containers[@]} exited containers:"
    docker ps -a | awk '/Exited/'

    if [[ "${APPLY}" == "true" ]]; then
        log_info "Removing ${#exited_containers[@]} exited containers..."
        if docker rm -f "${exited_containers[@]}"; then
            log_info "Successfully removed exited containers"
        else
            log_error "Failed to remove some containers"
            return 1
        fi
    else
        log_info "[Dry-run] Would remove ${#exited_containers[@]} exited containers"
    fi
}

# Remove Docker images based on pattern
docker_rm_images() {
    log_debug "Fetching Docker images with pattern: '${PATTERN}'"

    local -a images=()
    local -a images_to_del=()

    # Fetch all images once
    if ! readarray -t images < <(
        docker image ls --format '{{.ID}} {{.Repository}} {{.Tag}}'
    ); then
        log_error "Failed to list Docker images"
        return 1
    fi

    log_debug "Total images found: ${#images[@]}"

    # Filter images based on pattern
    local entry id repo tag name
    for entry in "${images[@]}"; do
        read -r id repo tag <<<"${entry}"
        name="${repo}:${tag}"

        # Special handling for <none> pattern
        if [[ "${PATTERN}" == "<none>" ]]; then
            if [[ "${tag}" == "<none>" ]]; then
                images_to_del+=("${id}")
                log_debug "Matched <none> image: ${id}"
            fi
            continue
        fi

        # Pattern matching with optional inversion
        if [[ "${INVERT_MATCH}" == "true" ]]; then
            if [[ ! "${name}" =~ ${PATTERN} ]]; then
                images_to_del+=("${name}")
                log_debug "Matched (inverted): ${name}"
            fi
        else
            if [[ "${name}" =~ ${PATTERN} ]]; then
                images_to_del+=("${name}")
                log_debug "Matched: ${name}"
            fi
        fi
    done

    if [[ ${#images_to_del[@]} -eq 0 ]]; then
        log_warning "No images match the pattern: '${PATTERN}'"
        return 0
    fi

    log_info "Found ${#images_to_del[@]} images matching pattern '${PATTERN}'"
    printf "    %s\n" "${images_to_del[@]}"

    if [[ "${APPLY}" == "true" ]]; then
        log_info "Deleting ${#images_to_del[@]} images..."
        if printf "%s\0" "${images_to_del[@]}" | xargs -0 -P10 -n1 docker image rm; then
            log_info "Deletion completed successfully"
        else
            log_error "Some images failed to delete"
            return 1
        fi
    else
        log_info "[Dry-run] No images deleted. Use --apply to actually delete"
    fi
}

main() {
    require_command docker getopt

    parse_args "${@}"

    log_debug "Configuration:"
    log_debug "  APPLY=${APPLY}"
    log_debug "  INVERT_MATCH=${INVERT_MATCH}"
    log_debug "  PATTERN='${PATTERN}'"
    log_debug "  LOG_LEVEL=${LOG_LEVEL}"
    log_debug "  LOG_FORMAT=${LOG_FORMAT}"

    log_info "Starting Docker cleanup process..."

    docker_rm_containers
    docker_rm_images

    log_info "Cleanup process completed"
}

main "${@}"
