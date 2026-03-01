#!/usr/bin/env bash

set -o errexit -o nounset

rootfs="${1:?Usage: $0 <rootfs>}"

if [[ "${rootfs}" =~ /$ ]]; then
    echo "rootfs cannot end with a slash (/): ${rootfs}" >&2
    exit 1
fi

while IFS= read -r snapshot; do
    while IFS= read -r hold; do
        echo "Releasing hold '${hold}' from '${snapshot}'"
        zfs release "${hold}" "${snapshot}"
    done < <(zfs holds -H "${snapshot}" | awk '{print $2}')
done < <(zfs list -t snapshot -Hr -oname "${rootfs}")
