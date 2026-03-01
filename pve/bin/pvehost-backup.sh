#!/usr/bin/env bash

set -o errexit -o nounset

readonly BACKUP_PATH="${HOME}/pvehost-backup"
readonly RETENTION_DAYS=30

BACKUP_PATHS=(
    /etc/apt/
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
    /etc/cron.d/
    /etc/cron.daily/
    /etc/cron.hourly/
    /etc/cron.monthly/
    /etc/cron.weekly/
    /etc/crontab
    /etc/aliases
    /etc/apcupsd/
)

mkdir -p "${BACKUP_PATH}"

existing_paths=()
for path in "${BACKUP_PATHS[@]}"; do
    [[ -e "${path}" ]] && existing_paths+=("${path}")
done

backup_file="${BACKUP_PATH}/$(hostname)-$(date +%F.%s).tar.gz"

tar -czf "${backup_file}" --absolute-names "${existing_paths[@]}"
sha256sum "${backup_file}" >"${backup_file}.sha256"
echo "Backup: ${backup_file} ($(du -h "${backup_file}" | cut -f1))"

while IFS= read -r old; do
    rm -f "${old}" "${old}.sha256"
done < <(find "${BACKUP_PATH}" -name "*.tar.gz" -type f -mtime "+${RETENTION_DAYS}")
