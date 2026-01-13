#!/bin/bash
# author: ak1ra
# date: 2023-07-31
# description: Dump Kubernetes resource manifests in particular namespace

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
    # Add cleanup logic here if needed
    exit "${exit_code}"
}

trap cleanup EXIT INT TERM

# Show usage information
usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
    ${SCRIPT_NAME} [OPTIONS] [NAMESPACE...]

    Dump Kubernetes resource manifests in particular namespace(s)

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -A, --all-namespaces      Dump all namespaces
    -f, --force               Overwrite existing manifest files
                              Default: skip existing files

ARGUMENTS:
    NAMESPACE...              One or more namespaces to dump
                              (ignored if --all-namespaces is specified)

EXAMPLES:
    ${SCRIPT_NAME} default kube-system
    ${SCRIPT_NAME} --all-namespaces
    ${SCRIPT_NAME} --force -A
    ${SCRIPT_NAME} --log-level DEBUG --log-format full default

EOF
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="hAf"
    local longoptions="help,log-level:,log-format:,all-namespaces,force"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g DUMP_ALL_NAMESPACES="false"
    declare -g FORCE_OVERWRITE="false"
    declare -g -a NAMESPACES=()

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
            -A | --all-namespaces)
                DUMP_ALL_NAMESPACES="true"
                shift
                ;;
            -f | --force)
                FORCE_OVERWRITE="true"
                shift
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

    if [[ "${DUMP_ALL_NAMESPACES}" == "true" ]]; then
        if [[ "$#" -gt 0 ]]; then
            log_warning "Ignoring namespace arguments when --all-namespaces is specified"
        fi
        readarray -t NAMESPACES < <(kubectl get namespaces --no-headers --output=name)
    else
        if [[ "$#" -eq 0 ]]; then
            log_error "No namespaces specified"
            usage 1
        fi
        NAMESPACES=("$@")
    fi
}

# Check if namespace exists
namespace_exists() {
    local namespace="$1"
    kubectl get namespaces --no-headers --output=name | grep -qE "^namespace/${namespace}$"
}

# Ensure directory exists
ensure_directory() {
    local dir="$1"
    if [[ ! -d "${dir}" ]]; then
        mkdir -p "${dir}"
        log_info "Created directory: ${dir}"
    fi
}

# Dump Kubernetes resources for a namespace
kube_dump_namespace() {
    local namespace="$1"
    if ! namespace_exists "${namespace}"; then
        log_warning "Namespace '${namespace}' does not exist, skipping..."
        return 0
    fi

    log_info "Dumping namespace: ${namespace}"

    local jq_cattle_regex='^(?:(?:authz\.cluster|secret\.user|field|lifecycle|listener|workload)\.)?cattle\.io\/'

    local api_resources=()
    readarray -t api_resources < <(
        kubectl api-resources --namespaced --no-headers --output=name | grep -v '^events'
    )

    if [[ ${#api_resources[@]} -eq 0 ]]; then
        log_error "No namespaced API resources found"
        return 1
    fi

    for api_resource in "${api_resources[@]}"; do
        log_debug "Checking resource type: ${api_resource}"

        local resources_with_prefix=()
        readarray -t resources_with_prefix < <(
            kubectl --namespace "${namespace}" get "${api_resource}" \
                --no-headers --ignore-not-found --output=name 2>/dev/null || true
        )

        if [[ ${#resources_with_prefix[@]} -eq 0 ]]; then
            log_debug "No resources found for type: ${api_resource}"
            continue
        fi

        log_debug "Found ${#resources_with_prefix[@]} resource(s) of type: ${api_resource}"

        for resource in "${resources_with_prefix[@]}"; do
            local resource_dir="${namespace}/${api_resource}"
            ensure_directory "${resource_dir}"

            local resource_name="${resource#*/}"
            local output_file="${resource_dir}/${resource_name}.json"

            if [[ -f "${output_file}" && "${FORCE_OVERWRITE}" == "false" ]]; then
                log_info "Skipping existing file: ${output_file}"
                continue
            fi

            log_info "Dumping ${resource} to ${output_file}"

            if ! kubectl --namespace "${namespace}" get "${resource}" --output=json |
                jq --arg jq_cattle_regex "${jq_cattle_regex}" --indent 4 --sort-keys 'walk(
                    if type == "object" then
                        with_entries(select(.key | test($jq_cattle_regex) | not))
                    else .
                    end)
                    | del(
                        .metadata.namespace,
                        .metadata.annotations."deployment.kubernetes.io/revision",
                        .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
                        .metadata.creationTimestamp,
                        .metadata.generation,
                        .metadata.managedFields,
                        .metadata.resourceVersion,
                        .metadata.selfLink,
                        .metadata.uid,
                        .metadata.ownerReferences,
                        .status,
                        .spec.clusterIP,
                        .spec.clusterIPs
                    )' >"${output_file}"; then
                log_error "Failed to dump ${resource}"
                continue
            fi

            log_debug "Successfully dumped ${resource}"
        done
    done

    log_info "Completed dumping namespace: ${namespace}"
}

main() {
    require_command kubectl jq getopt

    parse_args "$@"

    if [[ ${#NAMESPACES[@]} -eq 0 ]]; then
        log_error "No namespaces found or specified"
        exit 1
    fi

    log_info "Starting kube-dump..."
    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Force overwrite: ${FORCE_OVERWRITE}"
    log_info "Processing ${#NAMESPACES[@]} namespace(s)"

    for ns in "${NAMESPACES[@]}"; do
        kube_dump_namespace "${ns#namespace/}"
    done

    log_info "kube-dump completed successfully"
}

main "$@"
