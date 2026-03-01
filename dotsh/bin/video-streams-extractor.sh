#!/usr/bin/env bash

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
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="hc:d"
    local longoptions="help,log-level:,log-format:,codec:,dry-run"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"
    declare -g -a REST_ARGS=()

    declare -g DRY_RUN=false
    declare -g CODEC_TYPE="subtitle"

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
            -c | --codec)
                CODEC_TYPE="${2}"
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
                log_error "Unexpected option: ${1}"
                usage 1
                ;;
        esac
    done

    # Capture remaining positional arguments (input files)
    REST_ARGS=("${@}")

    if [[ ${#REST_ARGS[@]} -eq 0 ]]; then
        log_error "No input files provided"
        usage 1
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

    local mode
    [[ "${DRY_RUN}" == true ]] && mode="DRY-RUN" || mode="EXECUTE"

    log_info "Starting stream extraction..."
    log_info "Mode: ${mode}, Codec pattern: '${CODEC_TYPE}'"

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

main "${@}"
