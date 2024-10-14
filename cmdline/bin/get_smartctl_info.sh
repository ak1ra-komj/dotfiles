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

get_selftest_log() {
    printf "\n===== get_selftest_log =====\n"
    for disk in "${disks[@]}"; do
        printf "===== ${disk} =====\n"
        smartctl --log=selftest "${disk}"
    done
}

get_selftest_status() {
    printf "\n===== get_selftest_status =====\n"
    for disk in "${disks[@]}"; do
        selftest_status="$(smartctl -j -c "${disk}" | jq -r .ata_smart_data.self_test.status.string)"
        printf "%-60s %s\n" "${disk}" "${selftest_status}"
    done
}

main() {
    readarray -t disks < <(find /dev/disk/by-id | awk '/\/ata-/ && !/-part[0-9]+/')

    get_smartctl_info

    get_selftest_log
    get_selftest_status
}

require_command smartctl

main "$@"
