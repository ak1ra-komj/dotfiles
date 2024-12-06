#!/bin/bash
# author: ak1ra & ChatGPT
# date: 2024-12-06

set -o errexit -o nounset -o pipefail

convert_bytes() {
    local bytes=$1 value unit
    if ((bytes >= 2 ** 40)); then
        value=$(bc <<<"scale=2; ${bytes}/2^40")
        unit="TiB"
    else
        value=$(bc <<<"scale=2; ${bytes}/2^30")
        unit="GiB"
    fi
    # Ensure consistent width for numeric value and unit
    printf "%6.2f %s" "${value}" "${unit}"
}

format_packets() {
    local packets=$1
    # Format packets with either scientific notation or integer
    if ((packets >= 1000000)); then
        printf "%8.2e packets" "${packets}"
    else
        printf "%8d packets" "${packets}"
    fi
}

process_interface() {
    local interface="$1"
    local rx_bytes_raw rx_stats rx_packets rx_pkts
    local tx_bytes_raw tx_stats tx_packets tx_pkts

    # Read raw data
    rx_bytes_raw=$(cat /sys/class/net/${interface}/statistics/rx_bytes)
    rx_packets=$(cat /sys/class/net/${interface}/statistics/rx_packets)
    tx_bytes_raw=$(cat /sys/class/net/${interface}/statistics/tx_bytes)
    tx_packets=$(cat /sys/class/net/${interface}/statistics/tx_packets)

    # Process RX and TX stats
    rx_stats=$(convert_bytes "${rx_bytes_raw}")
    rx_pkts=$(format_packets "${rx_packets}")
    tx_stats=$(convert_bytes "${tx_bytes_raw}")
    tx_pkts=$(format_packets "${tx_packets}")

    # Construct formatted output for this interface
    printf "%-${max_interface_len}s : RX %s, %s, TX %s, %s\n" \
        "${interface}" "${rx_stats}" "${rx_pkts}" "${tx_stats}" "${tx_pkts}"
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

    # Process and output statistics for each matching interface
    for interface in "${interfaces[@]}"; do
        process_interface "${interface}"
    done
}

main "$@"
