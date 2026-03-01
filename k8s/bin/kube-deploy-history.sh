#!/usr/bin/env bash

set -o errexit -o nounset -o errtrace

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

# Logging configuration
declare -g LOG_LEVEL="INFO"
declare -g LOG_FORMAT="simple"

# Temporary directory for caching
declare -g TEMP_DIR=""

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
        simple | level | full) LOG_FORMAT="${1}" ;;
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
    if [[ -n "${TEMP_DIR}" ]] && [[ -d "${TEMP_DIR}" ]]; then
        log_debug "Cleaning up temporary directory: ${TEMP_DIR}"
        rm -rf "${TEMP_DIR}"
    fi
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
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} awesome-deployment
    ${SCRIPT_NAME} awesome-deployment another-deployment
    ${SCRIPT_NAME} -n production awesome-deployment another-deployment

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

# Create temporary directory for caching ReplicaSets
create_temp_dir() {
    TEMP_DIR=$(mktemp -d -t "kube-deploy-history.XXXXXXXXXX")
    log_debug "Created temporary directory: ${TEMP_DIR}"
}

# Index ReplicaSets by deployment into temporary files
index_replicasets() {
    local namespace="$1"
    shift
    local -a rs_array=("$@")

    log_debug "Indexing ${#rs_array[@]} ReplicaSets for namespace: ${namespace}"

    local ns_dir="${TEMP_DIR}/${namespace}"
    mkdir -p "${ns_dir}"

    for rs_json in "${rs_array[@]}"; do
        # Extract deployment name from owner references
        local deploy_name
        deploy_name=$(jq -r '
            .metadata.ownerReferences[]?
            | select(.kind == "Deployment")
            | .name
        ' <<<"${rs_json}" 2>/dev/null || true)

        if [[ -n "${deploy_name}" ]]; then
            local deploy_file="${ns_dir}/${deploy_name}.json"
            echo "${rs_json}" >>"${deploy_file}"
        fi
    done

    log_debug "Indexed ReplicaSets into $(find "${ns_dir}" -type f 2>/dev/null | wc -l) deployment files"
}

# Show image history for a single deployment
show_deployment_history() {
    local namespace="$1"
    local deployment_name="$2"

    log_debug "Processing deployment: ${deployment_name} in namespace: ${namespace}"

    local deploy_file="${TEMP_DIR}/${namespace}/${deployment_name}.json"
    if [[ ! -f "${deploy_file}" ]]; then
        log_warning "No ReplicaSets found for deployment '${deployment_name}' in namespace '${namespace}'"
        return 0
    fi

    # Read ReplicaSets from file
    local -a matching_rs=()
    mapfile -t matching_rs <"${deploy_file}"

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

    log_debug "Getting all deployments in namespace: ${namespace}"

    local ns_dir="${TEMP_DIR}/${namespace}"
    if [[ ! -d "${ns_dir}" ]]; then
        log_warning "No deployments found in namespace '${namespace}'"
        return 0
    fi

    # Get deployment names from files
    local -a deployment_names=()
    while IFS= read -r -d '' deploy_file; do
        local deploy_name
        # basename NAME [SUFFIX], If SUFFIX specified, also remove a trailing SUFFIX.
        deploy_name=$(basename "${deploy_file}" .json)
        deployment_names+=("${deploy_name}")
    done < <(find "${ns_dir}" -type f -name "*.json" -print0 2>/dev/null)

    if [[ ${#deployment_names[@]} -eq 0 ]]; then
        log_warning "No deployments found in namespace '${namespace}'"
        return 0
    fi

    # Sort deployment names
    mapfile -t deployment_names < <(printf "%s\n" "${deployment_names[@]}" | sort)

    # Process each deployment
    for deployment in "${deployment_names[@]}"; do
        show_deployment_history "${namespace}" "${deployment}"
    done
}

# Parse command line arguments
parse_args() {
    local args
    local options="hn:A"
    local longoptions="help,log-level:,log-format:,namespace:,all-namespaces"

    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
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

    # Create temporary directory
    create_temp_dir

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

        # Group ReplicaSets by namespace and index them
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

        # Index ReplicaSets for each namespace
        for ns in "${!ns_rs_map[@]}"; do
            local -a ns_rs_array=()
            mapfile -t ns_rs_array <<<"${ns_rs_map[${ns}]}"
            index_replicasets "${ns}" "${ns_rs_array[@]}"
        done

        # Process each namespace
        local -a namespaces=()
        mapfile -t namespaces < <(printf "%s\n" "${!ns_rs_map[@]}" | sort)

        for ns in "${namespaces[@]}"; do
            show_all_deployments_history "${ns}"
        done
    elif [[ ${#REST_ARGS[@]} -eq 0 ]]; then
        # No specific deployments specified, show all in namespace
        index_replicasets "${NAMESPACE}" "${rs_array[@]}"
        show_all_deployments_history "${NAMESPACE}"
    else
        # Show specific deployments
        index_replicasets "${NAMESPACE}" "${rs_array[@]}"
        for deployment in "${REST_ARGS[@]}"; do
            show_deployment_history "${NAMESPACE}" "${deployment}"
        done
    fi
}

main "${@}"
