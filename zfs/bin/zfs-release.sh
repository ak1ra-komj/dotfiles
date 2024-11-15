#!/bin/bash
# author: ak1ra
# date: 2024-11-15

set -o errexit -o nounset -o pipefail

usage() {
    cat <<EOF
Usage:
    zfs-release.sh <rootfs>

    exec 'zfs release' command on all snapshots on rootfs recursively.
    rootfs can not endswith slash (/).

Examples:
    zfs-release.sh main
    zfs-release.sh main/zrepl/sink

EOF
    exit 0
}

zfs_release() {
    [[ "$#" -eq 1 ]] || usage
    rootfs="$1"

    readarray -t filesystems < <(zfs list -Hr -oname "${rootfs}")
    for filesystem in "${filesystems[@]}"; do

        readarray -t snapshots < <(zfs list -t snapshot -H -oname "${filesystem}")
        for snapshot in "${snapshots[@]}"; do

            readarray -t holds < <(zfs holds -H "${snapshot}" | awk '{print $2}')
            for hold in "${holds[@]}"; do
                (
                    set -x
                    zfs release "${hold}" "${snapshot}"
                )
            done
        done
    done
}

zfs_release "$@"
