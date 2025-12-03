#!/bin/bash
# Author: ak1ra
# Date: 2024-10-16
# Description: Extract important fields from smartctl --all output

set -o errexit -o nounset -o pipefail

SCRIPT_FILE="$(readlink -f "$0")"
SCRIPT_NAME="$(basename "${SCRIPT_FILE}")"

# Display constants
readonly FIELD_WIDTH=32
readonly COLOR_RED='\e[31m'
readonly COLOR_RESET='\e[0m'

# smartctl exit code error messages
declare -g -a SMARTCTL_ERROR_MSGS=(
    "Bit 0: Command line did not parse."
    "Bit 1: Device open failed, device did not return an IDENTIFY DEVICE structure, or device is in a low-power mode."
    "Bit 2: Some SMART or other ATA command to the disk failed, or there was a checksum error in a SMART data structure."
    "Bit 3: SMART status check returned 'DISK FAILING'."
    "Bit 4: We found prefail Attributes <= threshold."
    "Bit 5: SMART status check returned 'DISK OK' but we found that some (usage or prefail) Attributes have been <= threshold at some time in the past."
    "Bit 6: The device error log contains records of errors."
    "Bit 7: The device self-test log contains records of errors. [ATA only] Failed self-tests outdated by a newer successful extended self-test are ignored."
)

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
    ${SCRIPT_NAME} [OPTIONS] [PATTERN]

    Extract and display important SMART information from disk devices.

OPTIONS:
    -h, --help                Show this help message
    --log-level LEVEL         Set log level (ERROR, WARNING, INFO, DEBUG)
                              Default: INFO
    --log-format FORMAT       Set log output format (simple, level, full)
                              simple: message only
                              level:  [LEVEL] message
                              full:   [timestamp][LEVEL] message
                              Default: simple

ARGUMENTS:
    PATTERN                   Regex pattern to filter disk devices
                              Default: .* (all ATA disks)

EXAMPLES:
    ${SCRIPT_NAME}                              # Show SMART info for all ATA disks
    ${SCRIPT_NAME} 'WDC'                        # Show info for WDC disks only
    ${SCRIPT_NAME} 'sda|sdb'                    # Show info for sda or sdb
    ${SCRIPT_NAME} --log-level DEBUG 'Samsung'  # Debug mode for Samsung disks
    ${SCRIPT_NAME} --log-format level           # Show with log levels

NOTES:
    - This script typically requires root privileges to access SMART data
    - Required commands: bc, jq, smartctl
    - Searches in /dev/disk/by-id for ATA devices (excludes partitions)

REFERENCE:
    https://linux.die.net/man/8/smartctl

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    local args
    local options="h"
    local longoptions="help,log-level:,log-format:"
    if ! args=$(getopt --options="${options}" --longoptions="${longoptions}" --name="${SCRIPT_NAME}" -- "$@"); then
        usage
    fi

    eval set -- "${args}"
    declare -g -a REST_ARGS=()

    declare -g PATTERN=".*"

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

    # Capture remaining positional arguments
    REST_ARGS=("$@")

    # Use first positional argument as PATTERN if provided
    if [[ ${#REST_ARGS[@]} -gt 0 ]]; then
        PATTERN="${REST_ARGS[0]}"
        log_debug "Using positional argument as pattern: ${PATTERN}"
    fi

    log_debug "Configuration:"
    log_debug "  PATTERN=${PATTERN}"
    log_debug "  LOG_LEVEL=${LOG_LEVEL}"
    log_debug "  LOG_FORMAT=${LOG_FORMAT}"
}

# Check for root privileges
check_root_privilege() {
    if [[ ${EUID} -ne 0 ]]; then
        log_warning "This script typically requires root privileges to access SMART data"
        log_warning "Some information may not be available"
    fi
}

# Check and report smartctl exit codes
check_smartctl_error_code() {
    local error_code="$1"
    local i bit_set

    if [[ "${error_code}" -eq 0 ]]; then
        return 0
    fi

    log_error "smartctl returned error code: ${error_code}"

    for ((i = 0; i < 8; i++)); do
        bit_set=$(((error_code >> i) & 1))
        if [[ "${bit_set}" -eq 1 ]]; then
            log_error "  ${SMARTCTL_ERROR_MSGS[$i]}"
        fi
    done
}

# Safe jq query with default fallback
safe_jq() {
    local query="$1"
    local json="$2"
    local default="${3:-N/A}"
    local result

    result="$(jq -r "${query}" <<<"${json}" 2>/dev/null)" || result="${default}"

    if [[ -z "${result}" || "${result}" == "null" ]]; then
        echo "${default}"
    else
        echo "${result}"
    fi
}

# Print formatted field with optional color
print_field() {
    local name="$1"
    local value="$2"
    local color="${3:-}"

    if [[ -n "${color}" ]]; then
        printf "${color}%-${FIELD_WIDTH}s %s${COLOR_RESET}\n" "${name}" "${value}"
    else
        printf "%-${FIELD_WIDTH}s %s\n" "${name}" "${value}"
    fi
}

# Get and display SMART info for all disks
get_smartctl_info() {
    local -a disks=("$@")
    local disk error_code disk_smart
    local model_family model_name user_capacity user_capacity_gib
    local rotation_rate interface_speed power_on_time power_cycle_count
    local temperature reallocated_sector_ct ata_smart_error_log self_test_status

    for disk in "${disks[@]}"; do
        printf "====== %s ======\n" "${disk}"

        # Fetch SMART data
        error_code=0
        if ! disk_smart="$(smartctl --all --json "${disk}" 2>/dev/null | jq -c .)"; then
            error_code=$?
        fi

        check_smartctl_error_code "${error_code}"

        # Extract and display information
        model_family="$(safe_jq '.model_family' "${disk_smart}")"
        print_field "model_family" "${model_family}"

        model_name="$(safe_jq '.model_name' "${disk_smart}")"
        print_field "model_name" "${model_name}"

        user_capacity="$(safe_jq '.user_capacity.bytes' "${disk_smart}" "0")"
        if [[ "${user_capacity}" =~ ^[0-9]+$ ]] && [[ "${user_capacity}" -gt 0 ]]; then
            user_capacity_gib="$(bc <<<"scale=2; ${user_capacity}/2^30" 2>/dev/null || echo "N/A")"
            print_field "user_capacity" "${user_capacity_gib} GiB"
        else
            print_field "user_capacity" "N/A"
        fi

        rotation_rate="$(safe_jq '.rotation_rate' "${disk_smart}")"
        if [[ "${rotation_rate}" != "N/A" && "${rotation_rate}" != "0" ]]; then
            print_field "rotation_rate" "${rotation_rate} rpm"
        else
            print_field "rotation_rate" "SSD (no rotation)"
        fi

        interface_speed="$(safe_jq '.interface_speed.current.string' "${disk_smart}")"
        print_field "interface_speed" "${interface_speed}"

        power_on_time="$(safe_jq '.power_on_time.hours' "${disk_smart}")"
        print_field "power_on_time" "${power_on_time} hours"

        power_cycle_count="$(safe_jq '.power_cycle_count' "${disk_smart}")"
        print_field "power_cycle_count" "${power_cycle_count}"

        temperature="$(safe_jq '.temperature.current' "${disk_smart}")"
        print_field "temperature" "${temperature}°C"

        # Reallocated_Sector_Ct - highlight if > 0
        reallocated_sector_ct="$(safe_jq '.ata_smart_attributes.table[] | select(.name=="Reallocated_Sector_Ct").raw.string' "${disk_smart}" "0")"
        if [[ "${reallocated_sector_ct}" =~ ^[0-9]+$ ]] && [[ "${reallocated_sector_ct}" -gt 0 ]]; then
            print_field "reallocated_sector_ct" "${reallocated_sector_ct}" "${COLOR_RED}"
        else
            print_field "reallocated_sector_ct" "${reallocated_sector_ct}"
        fi

        ata_smart_error_log="$(safe_jq '.ata_smart_error_log.summary.count' "${disk_smart}" "0")"
        print_field "ata_smart_error_log" "${ata_smart_error_log}"

        self_test_status="$(safe_jq '.ata_smart_data.self_test.status.string' "${disk_smart}")"
        print_field "self_test_status" "${self_test_status}"

        printf "\n"
    done
}

# Find disk devices matching pattern
find_disk_devices() {
    local pattern="$1"
    local -a disks

    log_info "Searching for disk devices matching pattern: ${pattern}"

    mapfile -t disks < <(
        find /dev/disk/by-id -type l 2>/dev/null |
            awk -v pattern="${pattern}" '/\/ata-/ && !/-part[0-9]+$/ && $0 ~ pattern' |
            sort
    )

    if [[ ${#disks[@]} -eq 0 ]]; then
        log_error "No disk devices found matching pattern: ${pattern}"
        exit 1
    fi

    log_info "Found ${#disks[@]} disk(s):"
    for disk in "${disks[@]}"; do
        log_debug "  ${disk}"
    done

    printf '%s\n' "${disks[@]}"
}

main() {
    require_command bc jq smartctl getopt

    parse_args "$@"

    check_root_privilege

    local -a disks
    mapfile -t disks < <(find_disk_devices "${PATTERN}")

    get_smartctl_info "${disks[@]}"
}

main "$@"
