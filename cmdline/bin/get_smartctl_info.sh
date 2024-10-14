#!/bin/bash
# author: ak1ra
# date: 2024-10-14

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

get_smartctl_info() {
    printf "===== SMART Attributes Data =====\n"
    for disk in "${disks[@]}"; do
        printf "===== ${disk} =====\n"
        smartctl -a "${disk}" |
            grep -E 'Start_Stop_Count|Power_Cycle_Count|Power_On_Hours|Temperature_Celsius'
    done
}

get_self_test_status() {
    printf "\n===== self_test_status =====\n"
    for disk in "${disks[@]}"; do
        self_test_status="$(smartctl -j -c "${disk}" | jq -r .ata_smart_data.self_test.status.string)"
        printf "%s\t%s\n" "${disk}" "${self_test_status}"
    done
}

main() {
    readarray -t disks < <(find /dev/disk/by-id | awk '/\/ata-/ && !/-part[0-9]+/')

    get_smartctl_info
    get_self_test_status
}

require_command smartctl

main "$@"
