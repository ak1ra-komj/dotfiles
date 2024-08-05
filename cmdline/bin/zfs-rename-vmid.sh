#!/bin/bash
# zfs-vmid-rename.sh tank/3101 data0/2101

set -o errexit
set -o xtrace

qemu_server="${HOME}/pve/qemu-server"
zfs_snapshot_prefix="zfs-rename-snap"

zfs_rename() {
    zfs_zvol_old="$1" # /dev/tank/vm-3101-disk-0
    zfs_zvol_new="$2" # /dev/data0/vm-2101-disk-0

    test -b "${zfs_zvol_old}" || return
    test ! -b "${zfs_zvol_new}" || return

    # remove /dev/ prefix
    _zvol_old="${zfs_zvol_old#/dev/}"
    _zvol_new="${zfs_zvol_new#/dev/}"

    _zpool_old="${_zvol_old%/*}"
    _zpool_new="${_zvol_new%/*}"

    # use 'zfs send | zfs receive' if zvol in different zpool
    if [ "${_zpool_old}" != "${_zpool_new}" ]; then
        zfs_snapshot="${zfs_snapshot_prefix}-$(date --utc +%F-%H%M)"
        zfs snapshot "${_zvol_old}@${zfs_snapshot}"
        zfs send "${_zvol_old}@${zfs_snapshot}" |
            zfs receive "${_zvol_new}@${zfs_snapshot}"
    else
        zfs rename "${_zvol_old}" "${_zvol_new}"
    fi
}

zfs_rename_vmid() {
    vm_old="$1" # tank/3101
    vm_new="$2" # data0/2101

    zpool_old="${vm_old%/*}"
    vmid_old="${vm_old#*/}"

    zpool_new="${vm_new%/*}"
    vmid_new="${vm_new#*/}"

    vm_disk_old_regex="${zpool_old}(:|/)(base|vm)-${vmid_old}-(cloudinit|disk-[0-9]+)"
    vm_disk_new_regex="${zpool_new}\1\2-${vmid_new}-\3"

    # exclude partition devices with '$' anchor
    readarray -t vm_disks < <(
        find "/dev/${zpool_old}" -type l | grep -E "${vm_disk_old_regex}$"
    )
    for vm_disk in "${vm_disks[@]}"; do
        vm_disk_new="$(echo "${vm_disk}" |
            sed -E 's%'"${vm_disk_old_regex}"'%'"${vm_disk_new_regex}"'%')"
        zfs_rename "${vm_disk}" "${vm_disk_new}"
    done

    cd /etc/pve/qemu-server || return
    test -d "${qemu_server}" || mkdir -p "${qemu_server}"
    mv -v "${vmid_old}.conf" "${qemu_server}"

    sed -E \
        -e 's%'"${vm_disk_old_regex}"'%'"${vm_disk_new_regex}"'%' \
        "${qemu_server}/${vmid_old}.conf" >"${vmid_new}.conf"
    diff "${qemu_server}/${vmid_old}.conf" "${vmid_new}.conf"

    cd - || return
}

zfs_rename_vmid "$@"
