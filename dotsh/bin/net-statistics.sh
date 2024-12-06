#!/bin/bash
# author: ak1ra & ChatGPT
# date: 2024-12-06

set -o errexit -o nounset -o pipefail

net_statistics() {
    local interface="$1"
    local rx_bytes rx_packets tx_bytes tx_packets

    rx_bytes=$(bc <<<"scale=2; $(cat /sys/class/net/${interface}/statistics/rx_bytes)/2^30")
    rx_packets=$(cat /sys/class/net/${interface}/statistics/rx_packets)

    tx_bytes=$(bc <<<"scale=2; $(cat /sys/class/net/${interface}/statistics/tx_bytes)/2^30")
    tx_packets=$(cat /sys/class/net/${interface}/statistics/tx_packets)

    printf "%-${max_interface_len}s : RX %6.2f GiB, %12d packets, TX %6.2f GiB, %12d packets\n" \
        "${interface}" "${rx_bytes}" "${rx_packets}" "${tx_bytes}" "${tx_packets}"
}

main() {
    local pattern="${1:-.*}" # Default pattern matches all interfaces

    # Use find with regex to filter interfaces
    mapfile -t interfaces < <(find /sys/class/net -type l -printf "%f\n" | awk "/${pattern}/")

    # Calculate the maximum interface name length for alignment
    max_interface_len=0
    for interface in "${interfaces[@]}"; do
        ((${#interface} > max_interface_len)) && max_interface_len=${#interface}
    done

    # Check if any interface matches the pattern
    if [[ ${#interfaces[@]} -eq 0 ]]; then
        echo "No interfaces match the pattern: ${pattern}" >&2
        exit 1
    fi

    # Display statistics for each matching interface
    for interface in "${interfaces[@]}"; do
        net_statistics "${interface}"
    done
}

main "$@"
