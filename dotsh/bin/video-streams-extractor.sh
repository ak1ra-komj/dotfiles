#!/bin/bash

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
    ${SCRIPT_NAME} [OPTIONS] FILE [FILE...]

    Extract streams (subtitle/audio/video) from video files.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -c, --codec PATTERN       Stream codec_type regex pattern to select
                              Use 'audio|subtitle' to select both
                              Default: subtitle
    -d, --dry-run             Dry run mode, only print ffmpeg commands

ARGUMENTS:
    FILE                      Video file(s) to process

EXAMPLES:
    ${SCRIPT_NAME} input.mkv
    ${SCRIPT_NAME} -c subtitle input.mkv
    ${SCRIPT_NAME} -c 'subtitle|audio' *.mkv *.mp4
    ${SCRIPT_NAME} --log-level DEBUG --codec audio file.mp4
    ${SCRIPT_NAME} --dry-run --codec video input.mkv

NOTES:
    - Output format: <filename>.<language>.<stream_index>.<codec_name>
    - Language defaults to 'und' (undefined) if not present
    - Codec name 'subrip' is automatically converted to 'srt'

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="hc:d"
    local longoptions="help,log-level:,log-format:,codec:,dry-run"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g -a REST_ARGS=()

    declare -g DRY_RUN=false
    declare -g CODEC_TYPE="subtitle"

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
            -c | --codec)
                CODEC_TYPE="$2"
                shift 2
                ;;
            -d | --dry-run)
                DRY_RUN=true
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

    # Capture remaining positional arguments (input files)
    REST_ARGS=("$@")

    if [[ ${#REST_ARGS[@]} -eq 0 ]]; then
        log_error "No input files provided"
        usage
    fi

    log_debug "Configuration:"
    log_debug "  DRY_RUN=${DRY_RUN}"
    log_debug "  CODEC_TYPE=${CODEC_TYPE}"
    log_debug "  LOG_LEVEL=${LOG_LEVEL}"
    log_debug "  LOG_FORMAT=${LOG_FORMAT}"
    log_debug "  Input files: ${REST_ARGS[*]}"
}

# Extract streams from a single video file
extract_streams() {
    local infile="$1"

    if [[ ! -f "${infile}" ]]; then
        log_warning "Skipping non-existent file: ${infile}"
        return 0
    fi

    log_debug "Processing file: ${infile}"

    # Get stream information using ffprobe
    local streams_json
    if ! streams_json="$(ffprobe -v quiet -print_format json -show_streams "${infile}" 2>&1)"; then
        log_error "ffprobe failed for: ${infile}"
        return 1
    fi

    # Collect stream objects
    local -a stream_objects=()
    while IFS= read -r line; do
        stream_objects+=("${line}")
    done < <(jq -c '.streams[]' <<<"${streams_json}")

    log_debug "Found ${#stream_objects[@]} total streams in ${infile}"

    # Build ffmpeg arguments for matching streams
    local -a ffmpeg_args=()
    local stream
    for stream in "${stream_objects[@]}"; do
        local stream_codec_type
        stream_codec_type="$(jq -r '.codec_type' <<<"${stream}")"

        # Check if stream codec type matches pattern
        if ! printf '%s' "${stream_codec_type}" | grep -qE "${CODEC_TYPE}"; then
            continue
        fi

        local stream_index stream_codec_name stream_language
        stream_index="$(jq -r '.index' <<<"${stream}")"
        stream_codec_name="$(jq -r '.codec_name' <<<"${stream}" | sed 's/subrip/srt/g')"
        stream_language="$(jq -r '.tags.language' <<<"${stream}")"

        # Default language to 'und' if not present
        if [[ -z "${stream_language}" || "${stream_language}" == "null" ]]; then
            stream_language="und"
        fi

        local output="${infile%.*}.${stream_language}.${stream_index}.${stream_codec_name}"
        ffmpeg_args+=(-map "0:${stream_index}" "${output}")

        log_debug "Matched stream ${stream_index}: ${stream_codec_type} (${stream_codec_name}, ${stream_language})"
    done

    if [[ ${#ffmpeg_args[@]} -eq 0 ]]; then
        log_info "No matching streams found in: ${infile}"
        return 0
    fi

    log_info "Extracting ${#ffmpeg_args[@]} stream(s) from: ${infile}"

    # Build and execute ffmpeg command
    local -a cmd=(ffmpeg -nostdin -n -v quiet -i "${infile}" "${ffmpeg_args[@]}")

    if [[ "${DRY_RUN}" == true ]]; then
        printf 'Dry-run: '
        printf ' %q' "${cmd[@]}"
        printf '\n'
        return 0
    fi

    if ! "${cmd[@]}"; then
        log_error "ffmpeg extraction failed for: ${infile}"
        return 1
    fi

    log_info "Successfully extracted streams from: ${infile}"
}

main() {
    require_command getopt ffmpeg ffprobe jq

    parse_args "$@"

    log_info "Starting stream extraction..."
    log_info "Mode: ${DRY_RUN:+DRY-RUN}${DRY_RUN:-EXECUTE}, Codec pattern: '${CODEC_TYPE}'"

    local processed=0
    local failed=0

    for infile in "${REST_ARGS[@]}"; do
        if extract_streams "${infile}"; then
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

main "$@"
