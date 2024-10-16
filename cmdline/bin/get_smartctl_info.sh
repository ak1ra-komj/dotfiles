#!/bin/bash
# author: ak1ra
# date: 2024-10-16
# extract important fields from smartctl --all output

set -o errexit -o nounset -o pipefail

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

get_smartctl_info() {
    declare -a disks

    readarray -t disks < <(
        find /dev/disk/by-id -type l |
            awk -v pattern="${pattern}" '/\/ata-/ && !/-part[0-9]+$/ && $0 ~ pattern' | sort
    )

    printf_format="%-32s %s\n"
    for disk in "${disks[@]}"; do
        printf "====== %s ======\n" "${disk}"
        disk_smart="$(smartctl --all --json "${disk}" | jq -c .)"

        model_family="$(jq -r .model_family <<<"${disk_smart}")"
        printf "${printf_format}" "model_family" "${model_family}"

        model_name="$(jq -r .model_name <<<"${disk_smart}")"
        printf "${printf_format}" "model_name" "${model_name}"

        user_capacity="$(jq -r .user_capacity.bytes <<<"${disk_smart}")"
        user_capacity_gib="$(bc <<<"scale=2; ${user_capacity}/2^30")"
        printf "${printf_format}" "user_capacity" "${user_capacity_gib} GiB"

        rotation_rate="$(jq -r .rotation_rate <<<"${disk_smart}")"
        printf "${printf_format}" "rotation_rate" "${rotation_rate}"

        interface_speed="$(jq -r .interface_speed.current.string <<<"${disk_smart}")"
        printf "${printf_format}" "interface_speed" "${interface_speed}"

        power_on_time="$(jq -r .power_on_time.hours <<<"${disk_smart}")"
        printf "${printf_format}" "power_on_time" "${power_on_time}"

        power_cycle_count="$(jq -r .power_cycle_count <<<"${disk_smart}")"
        printf "${printf_format}" "power_cycle_count" "${power_cycle_count}"

        ata_smart_error_log="$(jq -r .ata_smart_error_log.summary.count <<<"${disk_smart}")"
        printf "${printf_format}" "ata_smart_error_log" "${ata_smart_error_log}"

        self_test_status="$(jq -r .ata_smart_data.self_test.status.string <<<"${disk_smart}")"
        printf "${printf_format}" "self_test_status" "${self_test_status}"

        temperature="$(jq -r .temperature.current <<<"${disk_smart}")"
        printf "${printf_format}" "temperature" "${temperature}"

        printf "\n"
    done
}

main() {
    pattern=""
    if [[ "$#" -ge 1 ]]; then
        pattern="$1"
    fi

    get_smartctl_info
}

require_command bc jq smartctl

main "$@"
