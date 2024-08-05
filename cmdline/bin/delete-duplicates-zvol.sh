#!/bin/bash
# Delete zvols in the destination zpool that are duplicates of the source zpool
# ./delete_duplicates_zvol.sh data0 tank

set -o errexit

delete_duplicates_zvol() {
    zpool_src="$1"
    zpool_dest="$2"

    test -d "/dev/${zpool_src}" || return
    test -d "/dev/${zpool_dest}" || return

    readarray -t zvol_from_zpool_src < <(
        zfs list -H -o name -r "${zpool_src}" |
            grep -E '/vm-[0-9]+' |
            sed 's%'"${zpool_src}"'%'"${zpool_dest}"'%'
    )

    zvol_to_delete=()
    for zvol in "${zvol_from_zpool_src[@]}"; do
        test -b "/dev/${zvol}" && {
            printf "zfs destroy -r %s\n" "${zvol}"
            zvol_to_delete+=("${zvol}")
        }
    done

    if [ "${#zvol_to_delete[@]}" -eq 0 ]; then
        return
    fi

    read -r -p "Please answer YES_I_WANT_TO_DESTROY_MY_ZVOL to continue: " choice
    if [ "${choice}" != "YES_I_WANT_TO_DESTROY_MY_ZVOL" ]; then
        return
    fi

    for zvol in "${zvol_to_delete[@]}"; do
        test -b "/dev/${zvol}" && echo zfs destroy -r "${zvol}"
    done
}

if [ "$#" -eq 2 ]; then
    delete_duplicates_zvol "$@"
fi
