#!/usr/bin/env bash
#
# Extract the last non-blank frame from video files
#
# References:
# - Select any frame: https://superuser.com/a/1010108
# - Select last frame: https://superuser.com/a/1448673

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
Usage:
    ${SCRIPT_NAME} [OPTIONS] FILE [FILE...]

    Extract the last non-blank frame from video files.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -d, --dry-run             Dry run mode, only print ffmpeg commands
    -s, --sseof SECONDS       Seconds from end to start extracting
                              Default: 3

ARGUMENTS:
    FILE                      Video file(s) to process

EXAMPLES:
    ${SCRIPT_NAME} video.mp4
    ${SCRIPT_NAME} --sseof 5 video1.mp4 video2.mp4
    ${SCRIPT_NAME} --dry-run *.mp4
    ${SCRIPT_NAME} --log-level DEBUG --sseof 4 clip.mp4
    ${SCRIPT_NAME} --log-format level --dry-run video.mp4

NOTES:
    - Output file will be named: <input_filename>.last.png
    - Uses ffmpeg blackdetect filter to identify non-blank frames
    - Searches from the last frame backwards for efficiency

EOF
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="hds:"
    local longoptions="help,log-level:,log-format:,dry-run,sseof:"

    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"
    declare -g -a REST_ARGS=()

    declare -g DRY_RUN=false
    declare -g SSEOF=3

    while true; do
        case "${1}" in
            -h | --help)
                usage 0
                ;;
            --log-level)
                set_log_level "${2}"
                shift 2
                ;;
            --log-format)
                set_log_format "${2}"
                shift 2
                ;;
            -d | --dry-run)
                DRY_RUN=true
                shift
                ;;
            -s | --sseof)
                SSEOF="${2}"
                shift 2
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

    # Capture remaining positional arguments (input files)
    REST_ARGS=("$@")

    # Validate SSEOF is numeric (int or float)
    if [[ ! "${SSEOF}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        log_error "Invalid --sseof value (must be numeric): ${SSEOF}"
        exit 1
    fi

    log_debug "Configuration:"
    log_debug "  DRY_RUN=${DRY_RUN}"
    log_debug "  SSEOF=${SSEOF}"
    log_debug "  LOG_LEVEL=${LOG_LEVEL}"
    log_debug "  LOG_FORMAT=${LOG_FORMAT}"
    if [[ ${#REST_ARGS[@]} -gt 0 ]]; then
        log_debug "  Input files: ${REST_ARGS[*]}"
    fi
}

# Extract last non-blank frame from a video file
extract_last_frame() {
    local infile="$1"
    local temp_dir
    local last_non_blank_frame=""
    local -a frames=()

    if [[ ! -f "${infile}" ]]; then
        log_error "File not found: ${infile}"
        return 1
    fi

    local -a cmd=(
        ffmpeg
        -nostdin
        -n
        -v quiet
        -sseof "-${SSEOF}"
        -i "${infile}"
        -vf "select=not(mod(n\,1))"
        -vsync vfr
    )

    log_info "Processing: ${infile}"

    if [[ "${DRY_RUN}" == true ]]; then
        printf '%s' "Command: "
        printf ' %q' "${cmd[@]}" "TEMP_DIR/frame_%03d.png"
        printf '\n'
        return 0
    fi

    # Create temporary directory
    if ! temp_dir="$(mktemp -d)"; then
        log_error "Failed to create temporary directory"
        return 1
    fi
    log_debug "Created temp directory: ${temp_dir}"

    # Extract frames
    if ! "${cmd[@]}" "${temp_dir}/frame_%03d.png"; then
        log_error "Failed to extract frames: ${infile}"
        rm -rf "${temp_dir}"
        return 1
    fi

    # Find extracted frames
    readarray -t frames < <(find "${temp_dir}" -type f -name 'frame_*.png' | sort)
    if [[ ${#frames[@]} -eq 0 ]]; then
        log_warning "No frames extracted from last ${SSEOF}s: ${infile}"
        rm -rf "${temp_dir}"
        return 1
    fi

    log_debug "Extracted ${#frames[@]} frames, analyzing for non-blank frame..."

    # Iterate from last to first to find last non-blank frame
    for ((idx = ${#frames[@]} - 1; idx >= 0; idx--)); do
        local frame="${frames[idx]}"
        local black_frame

        log_debug "Checking frame $((idx + 1))/${#frames[@]}: $(basename "${frame}")"

        black_frame="$(ffmpeg -i "${frame}" -vf "blackdetect=d=0:pix_th=0.1" -an -f null - 2>&1 | grep blackdetect || true)"
        if [[ -z "${black_frame}" ]]; then
            last_non_blank_frame="${frame}"
            log_debug "Found non-blank frame: $(basename "${frame}")"
            break
        fi
    done

    # Save the last non-blank frame
    if [[ -n "${last_non_blank_frame}" ]]; then
        local output_file="${infile%.*}.last.png"
        if cp "${last_non_blank_frame}" "${output_file}"; then
            log_info "Saved last non-blank frame: ${output_file}"
        else
            log_error "Failed to save output file: ${output_file}"
            rm -rf "${temp_dir}"
            return 1
        fi
    else
        log_warning "No non-blank frame found in last ${SSEOF}s: ${infile}"
    fi

    # Cleanup
    rm -rf "${temp_dir}"
    log_debug "Removed temp directory: ${temp_dir}"
}

main() {
    require_command ffmpeg getopt

    parse_args "$@"

    if [[ ${#REST_ARGS[@]} -eq 0 ]]; then
        log_error "No input files specified"
        usage 1
    fi

    local mode
    [[ "${DRY_RUN}" == true ]] && mode="DRY-RUN" || mode="EXECUTE"

    log_info "Starting video frame extraction..."
    log_info "Mode: ${mode}, SSEOF: ${SSEOF}s"

    local processed=0
    local failed=0

    for infile in "${REST_ARGS[@]}"; do
        if extract_last_frame "${infile}"; then
            ((processed++)) || true
        else
            ((failed++)) || true
        fi
    done

    log_info "Extraction completed: ${processed} successful, ${failed} failed"

    if [[ "${failed}" -gt 0 ]]; then
        exit 1
    fi
}

main "${@}"
