#!/usr/bin/env bash
# author: ak1ra
# date: 2025-08-01
# description: Perform iperf3 tests between Kubernetes Pods

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
    ${SCRIPT_NAME} [OPTIONS] [-- IPERF3_OPTIONS]

    Perform iperf3 tests between Kubernetes Pods

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -i, --init                Initialize iperf3 server and client DaemonSets
    -c, --cleanup             Remove iperf3 server and client resources
    -o, --output DIR          Specify output directory
                              Default: ./kube-iperf3

ARGUMENTS:
    IPERF3_OPTIONS            Options to pass to iperf3 client (use -- to separate)

EXAMPLES:
    ${SCRIPT_NAME} --init
    ${SCRIPT_NAME} -- -t 30
    ${SCRIPT_NAME} -- -t 120 -R
    ${SCRIPT_NAME} --output /tmp/results -- -t 60
    ${SCRIPT_NAME} --log-level DEBUG --log-format full

NOTE:
    The iperf3 test results will be saved in the output directory.

EOF
    exit "${exit_code}"
}

readonly IPERF3_SERVER_NS="iperf3-server"
readonly IPERF3_CLIENT_NS="iperf3-client"
readonly IPERF3_IMAGE="ghcr.io/ak1ra-lab/iperf3"
readonly ROLLOUT_TIMEOUT="120s"

# Check if namespace exists
namespace_exists() {
    local namespace="$1"
    kubectl get namespace "${namespace}" &>/dev/null
}

# Wait for pods to be ready
wait_for_pods() {
    local namespace="$1"
    local label="$2"
    local timeout="${3:-120}"

    log_info "Waiting for pods in namespace '${namespace}' with label '${label}' to be ready..."

    if ! kubectl -n "${namespace}" wait --for=condition=ready pod \
        -l "${label}" --timeout="${timeout}s" &>/dev/null; then
        log_error "Timeout waiting for pods to be ready"
        return 1
    fi
}

# Create iperf3 server DaemonSet
create_iperf3_server() {
    log_info "Creating iperf3 server DaemonSet in namespace '${IPERF3_SERVER_NS}'..."

    if namespace_exists "${IPERF3_SERVER_NS}"; then
        log_warning "Namespace '${IPERF3_SERVER_NS}' already exists"
    fi

    kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: ${IPERF3_SERVER_NS}
  name: ${IPERF3_SERVER_NS}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iperf3-server
  namespace: ${IPERF3_SERVER_NS}
  labels:
    app: iperf3-server
spec:
  selector:
    matchLabels:
      app: iperf3-server
  template:
    metadata:
      labels:
        app: iperf3-server
    spec:
      containers:
        - name: iperf3-server
          image: ${IPERF3_IMAGE}
          args: ["-s"]
          ports:
            - protocol: TCP
              containerPort: 5201
              name: tcp
            - protocol: UDP
              containerPort: 5201
              name: udp
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 2000m
              memory: 512Mi
EOF

    if ! kubectl -n "${IPERF3_SERVER_NS}" rollout status daemonset/iperf3-server --timeout="${ROLLOUT_TIMEOUT}"; then
        log_error "Failed to deploy iperf3 server"
        return 1
    fi

    log_info "iperf3 server deployed successfully"
}

# Create iperf3 client DaemonSet
create_iperf3_client() {
    log_info "Creating iperf3 client DaemonSet in namespace '${IPERF3_CLIENT_NS}'..."

    if namespace_exists "${IPERF3_CLIENT_NS}"; then
        log_warning "Namespace '${IPERF3_CLIENT_NS}' already exists"
    fi

    kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: ${IPERF3_CLIENT_NS}
  name: ${IPERF3_CLIENT_NS}
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iperf3-client
  namespace: ${IPERF3_CLIENT_NS}
  labels:
    app: iperf3-client
spec:
  selector:
    matchLabels:
      app: iperf3-client
  template:
    metadata:
      labels:
        app: iperf3-client
    spec:
      containers:
        - name: iperf3
          image: ${IPERF3_IMAGE}
          command: ["sleep", "infinity"]
          resources:
            requests:
              cpu: 100m
              memory: 128Mi
            limits:
              cpu: 2000m
              memory: 512Mi
EOF

    if ! kubectl -n "${IPERF3_CLIENT_NS}" rollout status daemonset/iperf3-client --timeout="${ROLLOUT_TIMEOUT}"; then
        log_error "Failed to deploy iperf3 client"
        return 1
    fi

    log_info "iperf3 client deployed successfully"
}

# Cleanup iperf3 resources
cleanup_iperf3() {
    log_info "Cleaning up iperf3 resources..."

    if namespace_exists "${IPERF3_SERVER_NS}"; then
        log_info "Deleting namespace '${IPERF3_SERVER_NS}'..."
        kubectl delete namespace "${IPERF3_SERVER_NS}" --wait=true --timeout=60s || true
    fi

    if namespace_exists "${IPERF3_CLIENT_NS}"; then
        log_info "Deleting namespace '${IPERF3_CLIENT_NS}'..."
        kubectl delete namespace "${IPERF3_CLIENT_NS}" --wait=true --timeout=60s || true
    fi

    log_info "Cleanup completed"
}

# Execute iperf3 tests
kubectl_exec_iperf3() {
    local output_dir="$1"
    shift

    if [[ ! -d "${output_dir}" ]]; then
        mkdir -p "${output_dir}"
        log_info "Created output directory: ${output_dir}"
    fi

    local output_file
    output_file="${output_dir}/kube-iperf3.$(date +%F_%H%M%S).txt"
    log_info "Test results will be saved to: ${output_file}"

    local client_pods=()
    local server_pods=()

    readarray -t client_pods < <(
        kubectl -n "${IPERF3_CLIENT_NS}" get pods -l app=iperf3-client \
            -o json | jq -c '.items[]'
    )

    readarray -t server_pods < <(
        kubectl -n "${IPERF3_SERVER_NS}" get pods -l app=iperf3-server \
            -o json | jq -c '.items[]'
    )

    if [[ "${#client_pods[@]}" -eq 0 ]]; then
        log_error "No iperf3 client pods found in namespace '${IPERF3_CLIENT_NS}'"
        log_error "Use '${SCRIPT_NAME} --init' to create resources"
        exit 1
    fi

    if [[ "${#server_pods[@]}" -eq 0 ]]; then
        log_error "No iperf3 server pods found in namespace '${IPERF3_SERVER_NS}'"
        log_error "Use '${SCRIPT_NAME} --init' to create resources"
        exit 1
    fi

    log_info "Found ${#client_pods[@]} client pod(s) and ${#server_pods[@]} server pod(s)"

    local test_count=0
    for client_pod in "${client_pods[@]}"; do
        local client_pod_name client_pod_node_name
        client_pod_name="$(jq -r '.metadata.name' <<<"${client_pod}")"
        client_pod_node_name="$(jq -r '.spec.nodeName' <<<"${client_pod}")"

        for server_pod in "${server_pods[@]}"; do
            local server_pod_ip server_pod_node_name
            server_pod_ip="$(jq -r '.status.podIP' <<<"${server_pod}")"
            server_pod_node_name="$(jq -r '.spec.nodeName' <<<"${server_pod}")"

            test_count=$((test_count + 1))
            log_info "Test ${test_count}: ${client_pod_node_name} -> ${server_pod_node_name}" | tee -a "${output_file}"

            (
                set -x
                kubectl -n "${IPERF3_CLIENT_NS}" exec -it "${client_pod_name}" -- \
                    iperf3 -c "${server_pod_ip}" "$@"
            ) 2>&1 | tee -a "${output_file}"

            local exit_code="${PIPESTATUS[0]}"
            if [[ "${exit_code}" -ne 0 ]]; then
                log_warning "iperf3 test failed for ${client_pod_name} -> ${server_pod_ip} (exit code: ${exit_code})"
            fi

            echo "" | tee -a "${output_file}"
        done
    done

    log_info "All tests completed. Results saved to: ${output_file}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="hico:"
    local longoptions="help,log-level:,log-format:,init,cleanup,output:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g DO_INIT="false"
    declare -g DO_CLEANUP="false"
    declare -g OUTPUT_DIR
    OUTPUT_DIR="$(pwd)/kube-iperf3"
    declare -g -a IPERF3_ARGS=()

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
            -i | --init)
                DO_INIT="true"
                shift
                ;;
            -c | --cleanup)
                DO_CLEANUP="true"
                shift
                ;;
            -o | --output)
                OUTPUT_DIR="$2"
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

    IPERF3_ARGS=("$@")
}

main() {
    require_command kubectl jq getopt

    parse_args "$@"

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"

    if [[ "${DO_INIT}" == "true" ]]; then
        create_iperf3_server
        create_iperf3_client
        return 0
    fi

    if [[ "${DO_CLEANUP}" == "true" ]]; then
        cleanup_iperf3
        return 0
    fi

    kubectl_exec_iperf3 "${OUTPUT_DIR}" "${IPERF3_ARGS[@]}"
}

main "${@}"
