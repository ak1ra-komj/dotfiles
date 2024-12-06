#!/bin/bash

net_statistics() {
    interface="$1"

    rx_bytes="$(bc <<<"scale=2; $(cat /sys/class/net/${interface}/statistics/rx_bytes)/2^30")"
    rx_packets="$(cat /sys/class/net/${interface}/statistics/rx_packets)"

    tx_bytes="$(bc <<<"scale=2; $(cat /sys/class/net/${interface}/statistics/tx_bytes)/2^30")"
    tx_packets="$(cat /sys/class/net/${interface}/statistics/tx_packets)"

    printf "%s: RX %.2f GiB, %d packets, TX %.2f GiB, %d packets\n" \
        "${interface}" "${rx_bytes}" "${rx_packets}" "${tx_bytes}" "${tx_packets}"
}

main() {
    mapfile -t interfaces < <(find /sys/class/net -type l)
    for interface in "${interfaces[@]}"; do
        net_statistics "${interface##*/}"
    done
}

main "$@"
