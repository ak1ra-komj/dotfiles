#!/bin/bash
# author: ak1ra
# date: 2024-10-16
# extract important fields from smartctl --all output

set -o errexit -o nounset -o pipefail

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            printf "required command '%s' is not installed, aborting...\n" "$c" 1>&2
            exit 1
        }
    done
}

declare -a disks
declare -a smartctl_error_msgs=(
    "Bit 0: Command line did not parse."
    "Bit 1: Device open failed, device did not return an IDENTIFY DEVICE structure, or device is in a low-power mode (see '-n' option above)."
    "Bit 2: Some SMART or other ATA command to the disk failed, or there was a checksum error in a SMART data structure (see '-b' option above)."
    "Bit 3: SMART status check returned 'DISK FAILING'."
    "Bit 4: We found prefail Attributes <= threshold."
    "Bit 5: SMART status check returned 'DISK OK' but we found that some (usage or prefail) Attributes have been <= threshold at some time in the past."
    "Bit 6: The device error log contains records of errors."
    "Bit 7: The device self-test log contains records of errors. [ATA only] Failed self-tests outdated by a newer successful extended self-test are ignored."
)

check_smartctl_error_msgs() {
    # https://linux.die.net/man/8/smartctl
    # The error_code of smartctl are defined by a bitmask
    local error_code="$1"
    for ((i = 0; i < 8; i++)); do
        if [ "$((error_code & 2 ** i && 1))" -eq 1 ]; then
            printf "%s\n" "${smartctl_error_msgs[$i]}" 1>&2
        fi
    done
}

get_smartctl_info() {
    for disk in "${disks[@]}"; do
        printf "====== %s ======\n" "${disk}"

        error_code=0
        disk_smart="$(smartctl --all --json "${disk}" | jq -c .)" || error_code="$?"
        check_smartctl_error_msgs "${error_code}"

        model_family="$(jq -r .model_family <<<"${disk_smart}")"
        printf "%-32s %s\n" "model_family" "${model_family}"

        model_name="$(jq -r .model_name <<<"${disk_smart}")"
        printf "%-32s %s\n" "model_name" "${model_name}"

        user_capacity="$(jq -r .user_capacity.bytes <<<"${disk_smart}")"
        user_capacity_gib="$(bc <<<"scale=2; ${user_capacity}/2^30")"
        printf "%-32s %s\n" "user_capacity" "${user_capacity_gib} GiB"

        rotation_rate="$(jq -r .rotation_rate <<<"${disk_smart}")"
        printf "%-32s %s\n" "rotation_rate" "${rotation_rate} rpm"

        interface_speed="$(jq -r .interface_speed.current.string <<<"${disk_smart}")"
        printf "%-32s %s\n" "interface_speed" "${interface_speed}"

        power_on_time="$(jq -r .power_on_time.hours <<<"${disk_smart}")"
        printf "%-32s %s\n" "power_on_time" "${power_on_time}"

        power_cycle_count="$(jq -r .power_cycle_count <<<"${disk_smart}")"
        printf "%-32s %s\n" "power_cycle_count" "${power_cycle_count}"

        temperature="$(jq -r .temperature.current <<<"${disk_smart}")"
        printf "%-32s %s\n" "temperature" "${temperature}"

        # Reallocated_Sector_Ct
        reallocated_sector_ct="$(jq -r '.ata_smart_attributes.table[] | select(.name=="Reallocated_Sector_Ct").raw.string' <<<"${disk_smart}")"
        if [[ -n "${reallocated_sector_ct}" && "${reallocated_sector_ct}" -gt 0 ]]; then
            printf "\e[31m%-32s %s\e[0m\n" "reallocated_sector_ct" "${reallocated_sector_ct}" # Red color
        else
            printf "%-32s %s\n" "reallocated_sector_ct" "${reallocated_sector_ct}"
        fi

        ata_smart_error_log="$(jq -r .ata_smart_error_log.summary.count <<<"${disk_smart}")"
        printf "%-32s %s\n" "ata_smart_error_log" "${ata_smart_error_log}"

        self_test_status="$(jq -r .ata_smart_data.self_test.status.string <<<"${disk_smart}")"
        printf "%-32s %s\n" "self_test_status" "${self_test_status}"

        printf "\n"
    done
}

main() {
    pattern=".*"
    if [[ "$#" -ge 1 ]]; then
        pattern="$1"
    fi

    readarray -t disks < <(
        find /dev/disk/by-id -type l |
            awk -v pattern="${pattern}" '/\/ata-/ && !/-part[0-9]+$/ && $0 ~ pattern' | sort
    )

    get_smartctl_info
}

require_command bc jq smartctl

main "$@"
