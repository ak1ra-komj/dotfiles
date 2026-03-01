#!/usr/bin/env bash
# Convert all pxder downloaded Pixiv .zip archive to .gif/.mp4
# ref: https://github.com/Tsuk1ko/pxder

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
USAGE:
    ${SCRIPT_NAME} [OPTIONS]

    Convert Pixiv pxder downloaded .zip archives to animated media.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -f, --format FORMAT       Output format (gif|mp4), default: mp4
    -D, --delay MILLISECONDS  Override frame delay in milliseconds
                              If not set, auto-detect from filename
    -j, --jobs NUMBER         Parallel jobs (GNU parallel -j), default: auto

EXAMPLES:
    ${SCRIPT_NAME}                                  # Convert with defaults
    ${SCRIPT_NAME} --format gif                     # Output as GIF
    ${SCRIPT_NAME} --delay 120                      # Override delay to 120ms
    ${SCRIPT_NAME} --jobs 4 --log-level DEBUG       # 4 parallel jobs with debug
    ${SCRIPT_NAME} --log-format level --format mp4  # With log levels

NOTES:
    File name pattern '(XXXXXXXX)title@80ms.zip' auto-detects delay if --delay not given.
    Default delay fallback is 80ms if pattern not matched.

EOF
    exit "${exit_code}"
}

# Parse command line arguments
parse_args() {
    local args
    local options="hf:D:j:"
    local longoptions="help,log-level:,log-format:,format:,delay:,jobs:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"

    declare -g OUTPUT_FORMAT="mp4"
    declare -g OVERRIDE_DELAY=""
    declare -g PARALLEL_JOBS=""

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
            -f | --format)
                OUTPUT_FORMAT="${2}"
                shift 2
                ;;
            -D | --delay)
                OVERRIDE_DELAY="${2}"
                shift 2
                ;;
            -j | --jobs)
                PARALLEL_JOBS="${2}"
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

    # Capture remaining positional arguments
    # (none expected; all inputs are discovered via find)

    # Validate output format
    if [[ "${OUTPUT_FORMAT}" != "gif" && "${OUTPUT_FORMAT}" != "mp4" ]]; then
        log_error "Invalid format: ${OUTPUT_FORMAT} (expected gif|mp4)"
        exit 2
    fi

    # Validate delay if provided
    if [[ -n "${OVERRIDE_DELAY}" && ! "${OVERRIDE_DELAY}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid delay value: ${OVERRIDE_DELAY} (expected positive integer)"
        exit 2
    fi

    # Validate jobs if provided
    if [[ -n "${PARALLEL_JOBS}" && ! "${PARALLEL_JOBS}" =~ ^[0-9]+$ ]]; then
        log_error "Invalid jobs value: ${PARALLEL_JOBS} (expected positive integer)"
        exit 2
    fi

    log_debug "Configuration:"
    log_debug "  OUTPUT_FORMAT=${OUTPUT_FORMAT}"
    log_debug "  OVERRIDE_DELAY=${OVERRIDE_DELAY:-auto}"
    log_debug "  PARALLEL_JOBS=${PARALLEL_JOBS:-auto}"
    log_debug "  LOG_LEVEL=${LOG_LEVEL}"
    log_debug "  LOG_FORMAT=${LOG_FORMAT}"
}

# Convert single pixiv zip file to gif/mp4
pixiv_to_gif() {
    local infile="${1}"
    local format="${2}"
    local override_delay="${3}"

    # Resolve absolute path
    local infile_realpath
    if ! infile_realpath="$(realpath -s "${infile}")"; then
        log_error "Failed to resolve path: ${infile}"
        return 1
    fi

    if [[ ! -f "${infile_realpath}" ]]; then
        log_warning "Skipping non-regular file: ${infile_realpath}"
        return 0
    fi

    # Extract delay from filename if not overridden
    local delay="${override_delay}"
    if [[ -z "${delay}" ]]; then
        if [[ "${infile_realpath}" =~ @([0-9]+)ms\.zip$ ]]; then
            delay="${BASH_REMATCH[1]}"
            log_debug "Auto-detected delay from filename: ${delay}ms"
        else
            delay="80" # default fallback
            log_debug "Using default delay: ${delay}ms"
        fi
    fi

    # Prepare output filename
    local outfile_base="${infile_realpath%.zip}"
    # Normalize base without trailing @NNms if present, then append chosen delay
    outfile_base="${outfile_base%@*}"
    local outfile="${outfile_base}@${delay}ms.${format}"

    if [[ -f "${outfile}" ]]; then
        log_debug "Output already exists, skipping: $(basename "${outfile}")"
        return 0
    fi

    # Validate delay is numeric
    if ! [[ "${delay}" =~ ^[0-9]+$ ]]; then
        log_error "Non-numeric delay extracted: ${delay} (file: ${infile_realpath})"
        return 1
    fi

    # Frame rate calculation (1000ms / delay); keep three decimals
    local framerate
    framerate="$(awk -v d="${delay}" 'BEGIN {if (d==0) {print "1"} else {printf "%.3f", 1000/d}}')"

    # Create temporary directory
    local tmpdir
    if ! tmpdir="$(mktemp -d)"; then
        log_error "Failed to create temp directory"
        return 1
    fi

    log_info "Converting: $(basename "${infile_realpath}") -> $(basename "${outfile}") (delay=${delay}ms, fps=${framerate})"

    # Extract archive
    if ! unzip -q -o -d "${tmpdir}" "${infile_realpath}"; then
        log_error "Unzip failed: ${infile_realpath}"
        rm -rf "${tmpdir}"
        return 1
    fi

    if ! pushd "${tmpdir}" >/dev/null; then
        log_error "Failed to enter temp directory"
        rm -rf "${tmpdir}"
        return 1
    fi

    # Check for jpg frames
    if ! ls -- *.jpg >/dev/null 2>&1; then
        log_error "No .jpg frames found after extraction: ${infile_realpath}"
        popd >/dev/null || true
        rm -rf "${tmpdir}"
        return 1
    fi

    # Convert using ffmpeg (handles both gif and mp4)
    if ! ffmpeg -hide_banner -loglevel error -y -framerate "${framerate}" -i "%06d.jpg" "${outfile}"; then
        log_error "ffmpeg conversion failed: ${outfile}"
        popd >/dev/null || true
        rm -rf "${tmpdir}"
        return 1
    fi

    popd >/dev/null || true
    rm -rf "${tmpdir}"
    log_debug "Successfully created: $(basename "${outfile}")"
}

main() {
    require_command getopt ffmpeg unzip parallel awk realpath

    parse_args "$@"

    log_info "Starting Pixiv archive conversion..."
    log_info "Output format: ${OUTPUT_FORMAT}, Delay: ${OVERRIDE_DELAY:-auto}, Parallel jobs: ${PARALLEL_JOBS:-auto}"

    # Export variables and function for GNU parallel
    export LOG_LEVEL
    export LOG_FORMAT
    export -f log_color log_message log_error log_info log_warning log_debug log_critical
    export -f pixiv_to_gif

    # Find and process zip files
    local -a parallel_args=(-0)
    if [[ -n "${PARALLEL_JOBS}" ]]; then
        parallel_args+=(-j "${PARALLEL_JOBS}")
    fi

    local zip_count
    zip_count=$(find . -type f -name '*.zip' | wc -l)
    log_info "Found ${zip_count} .zip files to process"

    if [[ "${zip_count}" -eq 0 ]]; then
        log_warning "No .zip files found in current directory"
        exit 0
    fi

    find . -type f -name '*.zip' -print0 | parallel "${parallel_args[@]}" pixiv_to_gif {} "${OUTPUT_FORMAT}" "${OVERRIDE_DELAY}"

    log_info "Conversion completed"
}

main "${@}"
