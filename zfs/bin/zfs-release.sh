#!/bin/bash
# author: ak1ra
# date: 2024-11-15

set -o errexit -o nounset -o pipefail
script_name="$(basename "$(readlink -f "$0")")"

usage() {
    cat <<EOF
Usage:
    ${script_name} <rootfs>

    exec 'zfs release' command on all snapshots from rootfs recursively,
    don't use this if you don't know what you are doing,
    rootfs can not endswith slash (/).

Examples:
    ${script_name} main
    ${script_name} main/zrepl/sink

EOF
    exit 0
}

zfs_release() {
    [[ "$#" -eq 1 ]] || usage
    rootfs="$1"

    readarray -t snapshots < <(zfs list -t snapshot -Hr -oname "${rootfs}")
    for snapshot in "${snapshots[@]}"; do
        readarray -t holds < <(zfs holds -H "${snapshot}" | awk '{print $2}')
        for hold in "${holds[@]}"; do
            (
                set -x
                zfs release "${hold}" "${snapshot}"
            )
        done
    done
}

zfs_release "$@"
