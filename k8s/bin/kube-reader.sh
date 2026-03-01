#!/usr/bin/env bash

# Strict mode
set -o errexit -o nounset -o errtrace

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

# Logging configuration (aligned with template.sh)
declare -g LOG_LEVEL="INFO"    # ERROR, WARNING, INFO, DEBUG
declare -g LOG_FORMAT="simple" # simple, level, full

declare -g -A LOG_PRIORITY=(
    ["DEBUG"]=10
    ["INFO"]=20
    ["WARNING"]=30
    ["ERROR"]=40
    ["CRITICAL"]=50
)

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
        full)
            log_color "${color}" "[$(date --utc --iso-8601=seconds)][${level}] ${message}"
            ;;
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
    ${SCRIPT_NAME} [OPTIONS] NAME

Create a read-only RBAC (Role, ServiceAccount, RoleBinding) for common Kubernetes resources.

NAME (positional):
    Reader name: svc-reader | deploy-reader (required unless --name used)

OPTIONS:
    -h, --help                  Show this help message
    --log-level LEVEL           Set log level (ERROR, WARNING, INFO, DEBUG). Default: INFO
    --log-format FORMAT         Set log output format (simple, level, full). Default: simple
    -n, --namespace NAMESPACE   Kubernetes namespace (optional; defaults to current context or 'default')
    --name NAME                 (Optional) Explicit reader name (alternative to positional NAME)
    --apply                     Apply generated manifests (idempotent). Default: print YAML to stdout

EXAMPLES:
    ${SCRIPT_NAME} deploy-reader
    ${SCRIPT_NAME} svc-reader --apply
    ${SCRIPT_NAME} -n kube-system svc-reader --apply
    ${SCRIPT_NAME} --name deploy-reader --apply
EOF
    exit "${exit_code}"
}

# Argument parsing
parse_args() {
    local options="hn:"
    local longoptions="help,log-level:,log-format:,namespace:,name:,apply"
    local args
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi
    eval set -- "${args}"

    declare -g NAMESPACE=""
    declare -g NAME=""
    declare -g APPLY="false"
    declare -g -a REST_ARGS=()

    while true; do
        case "$1" in
            -h | --help) usage ;;
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
            --name)
                NAME="$2"
                shift 2
                ;;
            --apply)
                APPLY="true"
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

    REST_ARGS=("$@")

    # Positional NAME fallback if --name not used
    if [[ -z "${NAME}" && ${#REST_ARGS[@]} -gt 0 ]]; then
        NAME="${REST_ARGS[0]}"
    fi

    if [[ -z "${NAME}" ]]; then
        log_error "Missing reader NAME (positional) or --name"
        exit 1
    fi
    # Namespace optional; resolved later
}

# Resolve resource set by name
resolve_resources() {
    local name="$1"
    case "${name}" in
        svc-reader) printf "%s" "pods,services,endpoints,endpointslices" ;;
        deploy-reader) printf "%s" "pods,services,endpoints,endpointslices,daemonsets,deployments,statefulsets" ;;
        *)
            log_error "Unknown reader name: ${name}. Valid: svc-reader, deploy-reader"
            exit 1
            ;;
    esac
}

# Render manifests to stdout (YAML only)
render_rbac_yaml() {
    local ns="$1"
    local name="$2"
    local resources="$3"
    local verbs="get,list,watch"

    echo '---'
    kubectl -n "${ns}" create serviceaccount "${name}" --dry-run=client -oyaml
    echo '---'
    kubectl -n "${ns}" create role "${name}" --verb="${verbs}" --resource="${resources}" --dry-run=client -oyaml
    echo '---'
    kubectl -n "${ns}" create rolebinding "${name}" --role="${name}" --serviceaccount="${ns}:${name}" --dry-run=client -oyaml
}

# Execute kubectl commands
create_rbac() {
    local ns="$1"
    local name="$2"
    local resources="$3"

    if [[ "${APPLY}" == "true" ]]; then
        log_info "Applying RBAC for name='${name}' namespace='${ns}' (idempotent via apply)"
        render_rbac_yaml "${ns}" "${name}" "${resources}" | kubectl -n "${ns}" apply -f -
    else
        log_info "Printing RBAC manifests for name='${name}' namespace='${ns}' to stdout"
        render_rbac_yaml "${ns}" "${name}" "${resources}"
    fi
}

get_current_namespace() {
    # Returns current context namespace or 'default'
    local ns
    ns="$(kubectl config view --minify --output 'jsonpath={..namespace}' 2>/dev/null || true)"
    if [[ -z "${ns}" ]]; then
        ns="default"
    fi
    printf "%s" "${ns}"
}

main() {
    require_command getopt kubectl
    parse_args "$@"

    if [[ -z "${NAMESPACE}" ]]; then
        NAMESPACE="$(get_current_namespace)"
        log_debug "Namespace not provided; using current context namespace: ${NAMESPACE}"
    fi

    log_debug "Log level: ${LOG_LEVEL}, Log format: ${LOG_FORMAT}"
    log_debug "Namespace: ${NAMESPACE}, Name: ${NAME}, Apply: ${APPLY}"

    local resources
    resources="$(resolve_resources "${NAME}")"
    create_rbac "${NAMESPACE}" "${NAME}" "${resources}"
}

main "${@}"
