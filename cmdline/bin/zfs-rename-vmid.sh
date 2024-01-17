#!/bin/sh
# zfs-vmid-rename.sh apps/1010 local-zfs1/1253

zfs_snapshot_prefix="zfs-rename-snap"

zfs_rename() {
    zfs_zvol_old="$1"
    zfs_zvol_new="$2"

    test -b "${zfs_zvol_old}" || return
    test ! -b "${zfs_zvol_new}" || return

    # if cross zpool, use zfs send | zfs receive
    if [ "${zfs_zvol_old%/*}" = "${zfs_zvol_new%/*}" ]; then
        zfs_snapshot="${zfs_snapshot_prefix}-$(date --utc +%F-%H%M)"
        zfs snapshot "${zfs_zvol_old}@${zfs_snapshot}"
        zfs send "${zfs_zvol_old}@${zfs_snapshot}" |
            zfs receive "${zfs_zvol_new}@${zfs_snapshot}"
    else
        zfs rename "${zfs_zvol_old}" "${zfs_zvol_new}"
    fi
}

zfs_rename_vmid() {
    vm_old="$1"
    vm_new="$2"

    zpool_old="${vm_old%/*}"
    vmid_old="${vm_old#*/}"

    zpool_new="${vm_new%/*}"
    vmid_new="${vm_new#*/}"

    zfs_rename \
        "${zpool_old}/vm-${vmid_old}-cloudinit" \
        "${zpool_new}/vm-${vmid_new}-cloudinit"

    # what if there is disk-1, disk-2, ...?
    zfs_rename \
        "${zpool_old}/vm-${vmid_old}-disk-0" \
        "${zpool_new}/vm-${vmid_new}-disk-0"

    cd /etc/pve/qemu-server || return
    vm_disk_old_regex="${zpool_old}(:|/)(base|vm)-${vmid_old}-(cloudinit|disk-[0-9])"
    vm_disk_new_regex="${zpool_new}\1\2-${vmid_new}-\3"
    sed --regexp-extended \
        -e 's%'"${vm_disk_old_regex}"'%'"${vm_disk_new_regex}"'%' \
        "${vmid_old}.conf" >"${vmid_new}.conf"

    test -d ~/qemu-server || mkdir -p ~/qemu-server
    mv -v "${vmid_old}.conf" ~/qemu-server

    cd - || return
}

zfs_rename_vmid "$@"
