#!/bin/bash
# author: ak1ra
# date: 2023-07-31
# description: Dump Kubernetes resource manifests in particular namespace

set -euo pipefail

# Statistics counters
declare -g TOTAL_RESOURCES=0
declare -g DUMPED_RESOURCES=0
declare -g SKIPPED_RESOURCES=0
declare -g FAILED_RESOURCES=0

# Resource filtering configuration
declare -g -a IGNORED_RESOURCES=(
    "events"
    "events.events.k8s.io"
    "componentstatuses"
)

# Cattle.io annotation patterns to remove (for Rancher users)
declare -g JQ_CATTLE_REGEX='^(?:(?:authz\.cluster|secret\.user|field|lifecycle|listener|workload)\.)?cattle\.io\/'

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
            log_color "${color}" "[$(date --utc --iso-8601=seconds)][${level}] ${message}"
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

DESCRIPTION:
    This script efficiently dumps Kubernetes resources by batching API requests.
    For each resource type, it performs a single kubectl get operation and then
    processes individual resources using jq, significantly reducing API calls.

    By default, only namespaced resources are dumped. Use --include-cluster-resources
    to also dump cluster-level resources.

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
    -C, --include-cluster-resources
                              Also dump cluster-level resources
                              (nodes, clusterroles, etc.)
    -f, --force               Overwrite existing manifest files
                              Default: skip existing files

ARGUMENTS:
    NAMESPACE...              One or more namespaces to dump
                              (ignored if --all-namespaces is specified)

EXAMPLES:
    ${SCRIPT_NAME} default kube-system
    ${SCRIPT_NAME} --all-namespaces
    ${SCRIPT_NAME} --force -A
    ${SCRIPT_NAME} -C --all-namespaces
    ${SCRIPT_NAME} --log-level DEBUG --log-format full default

NOTES:
    - Uses batched API requests to minimize kubectl calls
    - Uses compact JSON output from kubectl for efficiency
    - Failed operations are logged but don't stop the entire process
    - A summary report is displayed at the end
    - Ignored resource types: ${IGNORED_RESOURCES[*]}

EOF
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="hACf"
    local longoptions="help,log-level:,log-format:,all-namespaces,include-cluster-resources,force"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g DUMP_ALL_NAMESPACES="false"
    declare -g FORCE_OVERWRITE="false"
    declare -g INCLUDE_CLUSTER_RESOURCES="false"
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
            -C | --include-cluster-resources)
                INCLUDE_CLUSTER_RESOURCES="true"
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

# Print statistics summary
print_summary() {
    log_info "========== Dump Summary =========="
    log_info "Total resources found:    ${TOTAL_RESOURCES}"
    log_info "Successfully dumped:      ${DUMPED_RESOURCES}"
    log_info "Skipped (existing):       ${SKIPPED_RESOURCES}"
    log_info "Failed:                   ${FAILED_RESOURCES}"
    log_info "=================================="

    if [[ ${FAILED_RESOURCES} -gt 0 ]]; then
        log_warning "Some resources failed to dump. Review the logs above for details."
        log_warning "You can re-run the script to retry failed resources."
        return 1
    fi
    return 0
}

# Check if resource type should be ignored
should_ignore_resource() {
    local resource="$1"
    local ignored
    for ignored in "${IGNORED_RESOURCES[@]}"; do
        if [[ "${resource}" == "${ignored}" ]]; then
            return 0
        fi
    done
    return 1
}

# Process and dump a single resource from batch result
dump_single_resource() {
    local output_dir="$1"
    local api_resource="$2"
    local resource_json="$3"

    local resource_name
    if ! resource_name=$(jq -r '.metadata.name' <<<"${resource_json}" 2>/dev/null); then
        log_error "Failed to extract resource name from JSON"
        return 1
    fi

    local resource_dir="${output_dir}/${api_resource}"
    ensure_directory "${resource_dir}"

    local output_file="${resource_dir}/${resource_name}.json"

    if [[ -f "${output_file}" && "${FORCE_OVERWRITE}" == "false" ]]; then
        log_debug "Skipping existing file: ${output_file}"
        ((SKIPPED_RESOURCES++))
        return 0
    fi

    log_debug "Processing ${api_resource}/${resource_name}"

    if ! jq --arg jq_cattle_regex "${JQ_CATTLE_REGEX}" --indent 4 --sort-keys 'walk(
            if type == "object" then
                with_entries(select(.key | test($jq_cattle_regex) | not))
            else
                .
            end) | del(
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
            )' <<<"${resource_json}" >"${output_file}" 2>/dev/null; then
        log_error "Failed to process and write ${api_resource}/${resource_name}"
        ((FAILED_RESOURCES++))
        return 1
    fi

    log_info "Dumped ${api_resource}/${resource_name}"
    ((DUMPED_RESOURCES++))
    return 0
}

# Dump Kubernetes resources for a namespace (optimized with batch requests)
kube_dump_namespace() {
    local namespace="$1"
    if ! namespace_exists "${namespace}"; then
        log_warning "Namespace '${namespace}' does not exist, skipping..."
        return 0
    fi

    log_info "Dumping namespace: ${namespace}"

    local api_resources=()
    readarray -t api_resources < <(
        kubectl api-resources --namespaced --no-headers --output=name
    )

    if [[ ${#api_resources[@]} -eq 0 ]]; then
        log_error "No namespaced API resources found"
        return 1
    fi

    log_debug "Found ${#api_resources[@]} namespaced resource type(s)"

    for api_resource in "${api_resources[@]}"; do
        if should_ignore_resource "${api_resource}"; then
            log_debug "Ignoring resource type: ${api_resource}"
            continue
        fi

        log_debug "Processing resource type: ${api_resource}"

        # Batch get all resources of this type as compact JSON array
        local -a resource_items=()
        readarray -t resource_items < <(
            kubectl --namespace "${namespace}" get "${api_resource}" \
                --ignore-not-found --output=json 2>/dev/null |
                jq -c '.items[]' 2>/dev/null || true
        )

        local item_count=${#resource_items[@]}
        if [[ ${item_count} -eq 0 ]]; then
            log_debug "No resources found for type: ${api_resource}"
            continue
        fi

        log_info "Found ${item_count} resource(s) of type: ${api_resource}"
        ((TOTAL_RESOURCES += item_count))

        # Process each compact JSON item
        for resource_json in "${resource_items[@]}"; do
            dump_single_resource "${namespace}" "${api_resource}" "${resource_json}" || true
        done
    done

    log_info "Completed dumping namespace: ${namespace}"
}

# Dump cluster-level resources
kube_dump_cluster_resources() {
    log_info "Dumping cluster-level resources"

    local api_resources=()
    readarray -t api_resources < <(
        kubectl api-resources --namespaced=false --no-headers --output=name
    )

    if [[ ${#api_resources[@]} -eq 0 ]]; then
        log_warning "No cluster-level API resources found"
        return 0
    fi

    log_debug "Found ${#api_resources[@]} cluster-level resource type(s)"

    local cluster_dir="_cluster"
    ensure_directory "${cluster_dir}"

    for api_resource in "${api_resources[@]}"; do
        if should_ignore_resource "${api_resource}"; then
            log_debug "Ignoring resource type: ${api_resource}"
            continue
        fi

        log_debug "Processing cluster resource type: ${api_resource}"

        # Batch get all resources of this type as compact JSON array
        local -a resource_items=()
        readarray -t resource_items < <(
            kubectl get "${api_resource}" \
                --ignore-not-found --output=json 2>/dev/null |
                jq -c '.items[]' 2>/dev/null || true
        )

        local item_count=${#resource_items[@]}
        if [[ ${item_count} -eq 0 ]]; then
            log_debug "No cluster resources found for type: ${api_resource}"
            continue
        fi

        log_info "Found ${item_count} cluster resource(s) of type: ${api_resource}"
        ((TOTAL_RESOURCES += item_count))

        # Process each compact JSON item
        for resource_json in "${resource_items[@]}"; do
            dump_single_resource "${cluster_dir}" "${api_resource}" "${resource_json}" || true
        done
    done

    log_info "Completed dumping cluster-level resources"
}

main() {
    require_command kubectl jq getopt

    parse_args "$@"

    if [[ ${#NAMESPACES[@]} -eq 0 && "${INCLUDE_CLUSTER_RESOURCES}" == "false" ]]; then
        log_error "No namespaces found or specified"
        exit 1
    fi

    log_info "Starting kube-dump (optimized mode)..."
    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Force overwrite: ${FORCE_OVERWRITE}"
    log_debug "Include cluster resources: ${INCLUDE_CLUSTER_RESOURCES}"

    if [[ ${#NAMESPACES[@]} -gt 0 ]]; then
        log_info "Processing ${#NAMESPACES[@]} namespace(s)"
        for ns in "${NAMESPACES[@]}"; do
            kube_dump_namespace "${ns#namespace/}"
        done
    fi

    if [[ "${INCLUDE_CLUSTER_RESOURCES}" == "true" ]]; then
        kube_dump_cluster_resources
    fi

    log_info "kube-dump completed"
    print_summary
}

main "$@"
