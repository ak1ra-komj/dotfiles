#!/bin/sh

PVE_BACKUP_SET="
    /etc/pve/
    /etc/lvm/
    /etc/modprobe.d/
    /etc/network/interfaces
    /etc/vzdump.conf
    /etc/sysctl.conf
    /etc/resolv.conf
    /etc/ksmtuned.conf
    /etc/hosts
    /etc/hostname
    /etc/cron*
    /etc/aliases
    /etc/apcupsd/
"

BACKUP_PATH="/local-zfs1/pvehost-backup"
test -d "${BACKUP_PATH}" || mkdir -p "${BACKUP_PATH}"

BACKUP_FILE="$(hostname)-$(date +%F.%s).tar.gz"

# shellcheck disable=SC2086
tar -czf "${BACKUP_PATH}/${BACKUP_FILE}" --absolute-names ${PVE_BACKUP_SET}
