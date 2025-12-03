#!/bin/bash
# --exclude=PATTERN, exclude files matching PATTERN
# --exclude-from=FILE, read exclude patterns from FILE

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
    ${SCRIPT_NAME} [OPTIONS] [-- [RSYNC OPTIONS]]

    Sync home directory to remote location using rsync.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -a, --apply               Actually execute the rsync operation
                              Default: dry-run mode for safety
    -e, --env-file FILE       Specify environment file
                              Default: ${SCRIPT_NAME%.sh}.env

RSYNC OPTIONS:
    Any additional rsync options can be passed after '--'
    These will be appended to the default rsync options

EXAMPLES:
    ${SCRIPT_NAME}                                      # Dry-run with defaults
    ${SCRIPT_NAME} --apply                              # Execute sync
    ${SCRIPT_NAME} --apply --env-file custom.env        # Use custom env file
    ${SCRIPT_NAME} --log-level DEBUG --log-format level # Debug with levels
    ${SCRIPT_NAME} -- --verbose --progress              # Pass rsync options

NOTES:
    - Set 'REMOTE_DIR' variable in the environment file
    - Default mode is dry-run for safety
    - Excluded directories: .cache, .go, .rustup, .cargo, .nvm, .npm,
      .yarn, .vscode-server, .cursor-server, .antigravity-server

ENVIRONMENT FILE FORMAT:
    REMOTE_DIR="user@host:/path/to/destination"

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="hae:"
    local longoptions="help,log-level:,log-format:,apply,env-file:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g -a REST_ARGS=()

    declare -g DRY_RUN=true
    declare -g ENV_FILE="${SCRIPT_FILE%.sh}.env"

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
            -a | --apply)
                DRY_RUN=false
                shift
                ;;
            -e | --env-file)
                ENV_FILE="$2"
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

    # Capture remaining positional arguments (additional rsync options)
    REST_ARGS=("$@")

    log_debug "Configuration:"
    log_debug "  DRY_RUN=${DRY_RUN}"
    log_debug "  ENV_FILE=${ENV_FILE}"
    log_debug "  LOG_LEVEL=${LOG_LEVEL}"
    log_debug "  LOG_FORMAT=${LOG_FORMAT}"
    if [[ ${#REST_ARGS[@]} -gt 0 ]]; then
        log_debug "  Additional rsync options: ${REST_ARGS[*]}"
    fi
}

# Load and validate environment file
load_environment() {
    if [[ ! -f "${ENV_FILE}" ]]; then
        log_error "Environment file '${ENV_FILE}' not found"
        exit 1
    fi

    log_debug "Loading environment from: ${ENV_FILE}"
    # shellcheck source=/dev/null
    source "${ENV_FILE}"

    # Verify REMOTE_DIR is set
    if [[ -z "${REMOTE_DIR:-}" ]]; then
        log_error "Variable 'REMOTE_DIR' is not set in ${ENV_FILE}"
        exit 1
    fi

    log_debug "Remote directory: ${REMOTE_DIR}"
}

# Execute rsync with appropriate options
execute_rsync() {
    local -a rsync_opts=(
        --archive
        --delete
        --delete-excluded
        --prune-empty-dirs
        --exclude='.cache'
        --exclude='.go'
        --exclude='.rustup'
        --exclude='.cargo'
        --exclude='.nvm'
        --exclude='.npm'
        --exclude='.yarn'
        --exclude='.vscode-server'
        --exclude='.cursor-server'
        --exclude='.antigravity-server'
    )

    # Append additional rsync options from REST_ARGS
    if [[ ${#REST_ARGS[@]} -gt 0 ]]; then
        log_debug "Appending additional rsync options: ${REST_ARGS[*]}"
        rsync_opts+=("${REST_ARGS[@]}")
    fi

    if [[ "${DRY_RUN}" == true ]]; then
        rsync_opts+=(--dry-run --verbose)
        log_info "Running in DRY-RUN mode"
    else
        log_warning "Running in APPLY mode - changes will be made"
    fi

    log_debug "Source: ${HOME}/"
    log_debug "Destination: ${REMOTE_DIR}"

    log_info "Executing rsync command..."
    (
        set -x
        rsync "${rsync_opts[@]}" "${HOME}/" "${REMOTE_DIR}"
    )
}

main() {
    require_command rsync getopt readlink date

    parse_args "$@"

    load_environment

    log_info "Starting rsync operation"
    execute_rsync
    log_info "Rsync operation completed successfully"
}

main "$@"
