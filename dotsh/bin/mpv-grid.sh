#!/usr/bin/env bash

set -o errexit -o nounset -o errtrace

SCRIPT_FILE="$(readlink -f "${0}")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

declare -r -a VIDEO_EXTENSIONS=(mp4 mkv avi mov flv wmv webm)

# --- Logging subsystem ---

declare -g LOG_LEVEL="INFO"
declare -g LOG_FORMAT="simple"
declare -g -A LOG_PRIORITY=(
    [DEBUG]=10
    [INFO]=20
    [WARNING]=30
    [ERROR]=40
    [CRITICAL]=50
)

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

    if [[ "${LOG_PRIORITY[${level}]}" -lt "${LOG_PRIORITY[${LOG_LEVEL}]}" ]]; then
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
        simple | level | full)
            LOG_FORMAT="${1}"
            ;;
        *)
            log_error "Invalid log format: ${1}. Valid formats: simple, level, full"
            exit 1
            ;;
    esac
}

# --- Dependency check ---

require_command() {
    local missing=()
    for c in "${@}"; do
        if ! command -v "${c}" >/dev/null 2>&1; then
            missing+=("${c}")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_error "Required command(s) not installed: ${missing[*]}"
        log_error "Please install the missing dependencies and try again."
        exit 1
    fi
}

# --- Core functions ---

# Outputs "X Y W H" for the given monitor index, sourced from xrandr --listmonitors.
# xrandr --listmonitors example output:
#   Monitors: 2
#    0: +*eDP-1 1920/294x1080/165+0+0  eDP-1
#    1: +HDMI-1 1920/527x1080/296+1920+0  HDMI-1
get_monitor_area() {
    local monitor_index="${1}"

    local -a monitors=()
    mapfile -t monitors < <(
        xrandr --listmonitors | grep -E '^\s+[0-9]+:' |
            sed -E 's|[^0-9]*[0-9]+: [+*]+[^ ]+ ([0-9]+)/[0-9]+x([0-9]+)/[0-9]+\+([0-9]+)\+([0-9]+).*|\3 \4 \1 \2|'
    )

    if [[ ${#monitors[@]} -eq 0 ]]; then
        log_error "No active monitors detected. Is DISPLAY set?"
        exit 1
    fi

    if [[ ${monitor_index} -lt 0 || ${monitor_index} -ge ${#monitors[@]} ]]; then
        log_error "Invalid monitor index: ${monitor_index}. Available: 0 to $((${#monitors[@]} - 1))."
        exit 1
    fi

    echo "${monitors[${monitor_index}]}"
}

# Prints one mpv geometry string per grid cell: WxH+X+Y
get_grid_positions() {
    local layout="${1}"
    local area_x="${2}"
    local area_y="${3}"
    local area_width="${4}"
    local area_height="${5}"

    local rows="${layout%%x*}"
    local cols="${layout#*x}"

    local win_width=$((area_width / cols))
    local win_height=$((area_height / rows))

    for ((row = 0; row < rows; row++)); do
        for ((col = 0; col < cols; col++)); do
            printf '%dx%d+%d+%d\n' \
                "${win_width}" "${win_height}" \
                "$((area_x + col * win_width))" \
                "$((area_y + row * win_height))"
        done
    done
}

find_video_files() {
    local path="${1:-.}"
    local first=true
    local -a name_args=()

    for ext in "${VIDEO_EXTENSIONS[@]}"; do
        if [[ "${first}" == "true" ]]; then
            first=false
        else
            name_args+=("-o")
        fi
        name_args+=("-iname" "*.${ext}")
    done

    find "${path}" -type f \( "${name_args[@]}" \)
}

start_mpv() {
    local file_path="${1}"
    local geometry="${2}"

    # Unset WAYLAND_DISPLAY to force mpv onto the XWayland backend.
    # Wayland compositors (e.g. KWin) ignore client-specified window positions,
    # but XWayland respects the --geometry placement hint.
    WAYLAND_DISPLAY='' mpv --geometry="${geometry}" --no-border "${file_path}" &
    log_info "Playing: ${file_path} (geometry: ${geometry}, pid: $!)"
}

# --- Usage and argument parsing ---

usage() {
    local exit_code="${1:-0}"
    cat <<EOF
USAGE:
    ${SCRIPT_NAME} [OPTIONS] [VIDEO ...]

    Arrange and play multiple videos simultaneously in a grid layout using mpv.
    If no videos are specified, video files are searched recursively in the
    current directory and a random selection is made to fill the grid.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple
    -m, --monitor INDEX       Monitor index to use (default: 0)
    -l, --layout ROWSxCOLS    Grid layout, e.g. 2x2, 3x4 (default: 2x2)

EXAMPLES:
    ${SCRIPT_NAME}
    ${SCRIPT_NAME} --monitor 1 --layout 4x4
    ${SCRIPT_NAME} --layout 3x3 video1.mp4 video2.mp4 video3.mp4

EOF
    exit "${exit_code}"
}

parse_args() {
    local args
    local options="hm:l:"
    local longoptions="help,log-level:,log-format:,monitor:,layout:"

    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "${@}"); then
        usage 1
    fi

    eval set -- "${args}"
    declare -g MONITOR=0
    declare -g LAYOUT="2x2"
    declare -g -a REST_ARGS=()

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
            -m | --monitor)
                if [[ ! "${2}" =~ ^[0-9]+$ ]]; then
                    log_error "Monitor index must be a non-negative integer: '${2}'"
                    usage 1
                fi
                MONITOR="${2}"
                shift 2
                ;;
            -l | --layout)
                if [[ ! "${2}" =~ ^[1-9][0-9]*x[1-9][0-9]*$ ]]; then
                    log_error "Invalid layout: '${2}'. Expected format: ROWSxCOLS (e.g. 2x2, 3x4)."
                    usage 1
                fi
                LAYOUT="${2}"
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

    REST_ARGS=("${@}")
}

# --- Main ---

main() {
    require_command getopt mpv shuf xrandr

    parse_args "${@}"

    log_debug "Monitor: ${MONITOR}, Layout: ${LAYOUT}"

    # Resolve monitor area
    local area
    area=$(get_monitor_area "${MONITOR}")
    local area_x area_y area_width area_height
    read -r area_x area_y area_width area_height <<<"${area}"

    log_debug "Monitor area: ${area_width}x${area_height} at +${area_x}+${area_y}"

    # Calculate grid positions
    local -a positions=()
    mapfile -t positions < <(get_grid_positions "${LAYOUT}" "${area_x}" "${area_y}" "${area_width}" "${area_height}")

    local max_count="${#positions[@]}"

    # Resolve video list
    local -a videos=()
    if [[ ${#REST_ARGS[@]} -gt 0 ]]; then
        videos=("${REST_ARGS[@]}")
    else
        log_info "No videos specified, searching current directory..."
        local -a found=()
        mapfile -t found < <(find_video_files ".")
        if [[ ${#found[@]} -eq 0 ]]; then
            log_error "No video files found in the current directory."
            exit 1
        fi
        mapfile -t videos < <(printf '%s\n' "${found[@]}" | shuf -n "${max_count}")
    fi

    if [[ ${#videos[@]} -lt ${max_count} ]]; then
        log_warning "Fewer videos (${#videos[@]}) than grid positions (${max_count})."
    fi

    local count
    count=$((${#videos[@]} < max_count ? ${#videos[@]} : max_count))

    for ((i = 0; i < count; i++)); do
        start_mpv "${videos[${i}]}" "${positions[${i}]}"
    done

    log_info "All ${count} video(s) launched."
}

main "${@}"
