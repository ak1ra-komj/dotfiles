#!/bin/bash

set -euo pipefail

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

# Logging configuration
declare -g LOG_LEVEL="INFO"
declare -g LOG_FORMAT="simple"

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
    local level="${1^^}"
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
    exit "${exit_code}"
}

trap cleanup EXIT INT TERM

# Show usage information
usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
    ${SCRIPT_NAME} [OPTIONS] [DEPLOYMENT...]

    Show image history for Kubernetes deployments

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              Default: simple
    -n, --namespace NAMESPACE Kubernetes namespace
                              Default: current context's namespace
    -A, --all-namespaces      Show history for all namespaces
                              Default: false

ARGUMENTS:
    DEPLOYMENT                Name of deployment(s) to show history for
                              If not specified, shows all deployments in namespace

EXAMPLES:
    ${SCRIPT_NAME} awesome-deployment
    ${SCRIPT_NAME} -n production awesome-deployment another-deployment
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} -n kube-system
    ${SCRIPT_NAME} --all-namespaces
    ${SCRIPT_NAME} --log-level DEBUG awesome-deployment

EOF
    exit "${exit_code}"
}

# Get current namespace from kubeconfig
get_current_namespace() {
    local namespace
    namespace=$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null)
    if [[ -z "${namespace}" ]]; then
        echo "default"
    else
        echo "${namespace}"
    fi
}

# Show image history for a single deployment
show_deployment_history() {
    local namespace="$1"
    local deployment_name="$2"
    shift 2
    local -a rs_array=("$@")

    log_debug "Processing deployment: ${deployment_name} in namespace: ${namespace}"

    # Build array of matching ReplicaSets
    local -a matching_rs=()
    for rs_json in "${rs_array[@]}"; do
        # Check if this RS belongs to the deployment
        if jq -e --arg deploy "${deployment_name}" '
            .metadata.ownerReferences[]?
            | select(.name == $deploy and .kind == "Deployment")
        ' <<<"${rs_json}" >/dev/null 2>&1; then
            matching_rs+=("${rs_json}")
        fi
    done

    if [[ ${#matching_rs[@]} -eq 0 ]]; then
        log_warning "No ReplicaSets found for deployment '${deployment_name}' in namespace '${namespace}'"
        return 0
    fi

    # Format output data into array
    local -a output_lines=()
    for rs_json in "${matching_rs[@]}"; do
        local line
        line=$(
            jq -r '[
                .metadata.creationTimestamp,
                (.metadata.annotations."deployment.kubernetes.io/revision" // "N/A"),
                .metadata.name,
                (.spec.replicas // 0 | tostring),
                (.status.replicas // 0 | tostring),
                (.spec.template.spec.containers | map(.image) | join(","))
            ] | @tsv' <<<"${rs_json}"
        )
        output_lines+=("${line}")
    done

    # Sort lines by timestamp
    mapfile -t output_lines < <(printf "%s\n" "${output_lines[@]}" | sort)

    log_info "Image history for deployment: ${deployment_name} (namespace: ${namespace})"
    printf "%-30s %-8s %-50s %-8s %-8s %s\n" "CREATED" "REVISION" "NAME" "DESIRED" "CURRENT" "IMAGES"

    for line in "${output_lines[@]}"; do
        IFS=$'\t' read -r created revision name desired current images <<<"${line}"
        printf "%-30s %-8s %-50s %-8s %-8s %s\n" "${created}" "${revision}" "${name}" "${desired}" "${current}" "${images}"
    done
    echo ""
}

# Show history for all deployments in namespace
show_all_deployments_history() {
    local namespace="$1"
    shift
    local -a rs_array=("$@")

    log_debug "Getting all deployments in namespace: ${namespace}"

    # Extract unique deployment names into array
    local -a deployment_names=()
    local -A seen_deployments=()

    for rs_json in "${rs_array[@]}"; do
        # Extract deployment names from owner references
        local -a deploy_refs=()
        mapfile -t deploy_refs < <(
            jq -r '
                .metadata.ownerReferences[]?
                | select(.kind == "Deployment")
                | .name
        ' <<<"${rs_json}"
        )

        for deploy_name in "${deploy_refs[@]}"; do
            if [[ -z "${seen_deployments[${deploy_name}]:-}" ]]; then
                deployment_names+=("${deploy_name}")
                seen_deployments["${deploy_name}"]=1
            fi
        done
    done

    # Sort deployment names
    mapfile -t deployment_names < <(printf "%s\n" "${deployment_names[@]}" | sort -u)

    if [[ ${#deployment_names[@]} -eq 0 ]]; then
        log_warning "No deployments found in namespace '${namespace}'"
        return 0
    fi

    # Process each deployment
    for deployment in "${deployment_names[@]}"; do
        show_deployment_history "${namespace}" "${deployment}" "${rs_array[@]}"
    done
}

# Parse command line arguments
parse_args() {
    local args
    local options="hn:A"
    local longoptions="help,log-level:,log-format:,namespace:,all-namespaces"

    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage 1
    fi

    eval set -- "${args}"
    declare -g -a REST_ARGS=()

    declare -g NAMESPACE=""
    declare -g ALL_NAMESPACES=false

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
            -n | --namespace)
                NAMESPACE="$2"
                shift 2
                ;;
            -A | --all-namespaces)
                ALL_NAMESPACES=true
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

    # Capture remaining positional arguments
    REST_ARGS=("$@")
}

main() {
    require_command kubectl jq getopt

    parse_args "$@"

    # Validate namespace and all-namespaces options
    if [[ "${ALL_NAMESPACES}" == true ]] && [[ -n "${NAMESPACE}" ]]; then
        log_error "Cannot specify both --namespace and --all-namespaces"
        exit 1
    fi

    # Get ReplicaSets based on scope
    log_debug "Fetching ReplicaSets"
    local -a rs_array=()

    if [[ "${ALL_NAMESPACES}" == true ]]; then
        log_debug "Fetching ReplicaSets from all namespaces"
        mapfile -t rs_array < <(kubectl get replicasets.apps --all-namespaces -o json 2>/dev/null | jq -c '.items[]')
    else
        # Determine namespace
        if [[ -z "${NAMESPACE}" ]]; then
            NAMESPACE=$(get_current_namespace)
            log_debug "Using current namespace: ${NAMESPACE}"
        fi

        # Validate namespace exists
        if ! kubectl get namespace "${NAMESPACE}" &>/dev/null; then
            log_error "Namespace '${NAMESPACE}' does not exist"
            exit 1
        fi

        log_debug "Fetching ReplicaSets from namespace: ${NAMESPACE}"
        mapfile -t rs_array < <(kubectl get replicasets.apps -n "${NAMESPACE}" -o json 2>/dev/null | jq -c '.items[]')
    fi

    if [[ ${#rs_array[@]} -eq 0 ]]; then
        if [[ "${ALL_NAMESPACES}" == true ]]; then
            log_warning "No ReplicaSets found in cluster"
        else
            log_warning "No ReplicaSets found in namespace '${NAMESPACE}'"
        fi
        exit 0
    fi

    log_debug "Found ${#rs_array[@]} ReplicaSets"

    # Process based on arguments and scope
    if [[ "${ALL_NAMESPACES}" == true ]]; then
        if [[ ${#REST_ARGS[@]} -gt 0 ]]; then
            log_warning "Deployment arguments are ignored when --all-namespaces is specified"
        fi

        # Group ReplicaSets by namespace
        local -A ns_rs_map=()
        for rs_json in "${rs_array[@]}"; do
            local ns
            ns=$(jq -r '.metadata.namespace' <<<"${rs_json}")
            if [[ -z "${ns_rs_map[${ns}]:-}" ]]; then
                ns_rs_map["${ns}"]="${rs_json}"
            else
                ns_rs_map["${ns}"]+=$'\n'"${rs_json}"
            fi
        done

        # Process each namespace
        local -a namespaces=()
        mapfile -t namespaces < <(printf "%s\n" "${!ns_rs_map[@]}" | sort)

        for ns in "${namespaces[@]}"; do
            local -a ns_rs_array=()
            mapfile -t ns_rs_array <<<"${ns_rs_map[${ns}]}"
            show_all_deployments_history "${ns}" "${ns_rs_array[@]}"
        done
    elif [[ ${#REST_ARGS[@]} -eq 0 ]]; then
        # No specific deployments specified, show all in namespace
        show_all_deployments_history "${NAMESPACE}" "${rs_array[@]}"
    else
        # Show specific deployments
        for deployment in "${REST_ARGS[@]}"; do
            show_deployment_history "${NAMESPACE}" "${deployment}" "${rs_array[@]}"
        done
    fi
}

main "$@"
