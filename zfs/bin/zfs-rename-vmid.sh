#!/usr/bin/env bash

set -o errexit -o nounset -o errtrace

SCRIPT_NAME="$(basename "$(readlink -f "${0}")")"

readonly PVE_QEMU_SERVER="/etc/pve/qemu-server"

info() { echo "${*}" >&2; }
warn() { echo "WARNING: ${*}" >&2; }
err() { echo "ERROR: ${*}" >&2; }

usage() {
    cat <<EOF
Usage:
    ${SCRIPT_NAME} [OPTIONS] <source_zpool>/<source_vmid> <dest_zpool>/<dest_vmid>

    Rename VM zvols and configuration from source to destination.
    Handles cross-pool migration (via zfs send|receive) and same-pool rename.
    WARNING: Modifies ZFS datasets and VM configs! Default is dry-run mode.

OPTIONS:
    -h, --help            Show this help message
    --apply               Actually execute the rename (default is dry-run)
    --backup-dir DIR      Base directory for timestamped config backups
                          Default: ~/pve/qemu-server

EXAMPLES:
    ${SCRIPT_NAME} tank/3101 data0/2101
    ${SCRIPT_NAME} --apply tank/3101 data0/2101
    ${SCRIPT_NAME} --apply --backup-dir /backup tank/3101 tank/2101
EOF
    exit 0
}

APPLY=false
BACKUP_DIR_BASE="${HOME}/pve/qemu-server"

args=$(getopt --options="h" --longoptions="help,apply,backup-dir:" \
    --name="${SCRIPT_NAME}" -- "$@") || usage
eval set -- "${args}"

while true; do
    case "${1}" in
        -h | --help) usage ;;
        --apply)
            APPLY=true
            shift
            ;;
        --backup-dir)
            BACKUP_DIR_BASE="${2}"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            err "Unexpected option: ${1}"
            usage
            ;;
    esac
done

if [[ $# -ne 2 ]]; then
    err "Expected exactly two arguments: <source_zpool/vmid> <dest_zpool/vmid>"
    usage
fi

SOURCE="${1}"
DEST="${2}"

if [[ ! "${SOURCE}" =~ ^[^/]+/[^/]+$ ]]; then
    err "Invalid source format: ${SOURCE}. Expected: zpool/vmid"
    exit 1
fi

if [[ ! "${DEST}" =~ ^[^/]+/[^/]+$ ]]; then
    err "Invalid destination format: ${DEST}. Expected: zpool/vmid"
    exit 1
fi

src_zpool="${SOURCE%/*}"
src_vmid="${SOURCE#*/}"
dst_zpool="${DEST%/*}"
dst_vmid="${DEST#*/}"

BACKUP_DIR="${BACKUP_DIR_BASE}/$(date -u +%Y-%m-%d-%H%M%S)"

if [[ ! -d "/dev/zvol/${src_zpool}" ]]; then
    err "Source zpool does not exist: ${src_zpool}"
    exit 1
fi

if [[ ! -d "/dev/zvol/${dst_zpool}" ]]; then
    err "Destination zpool does not exist: ${dst_zpool}"
    exit 1
fi

if [[ ! -f "${PVE_QEMU_SERVER}/${src_vmid}.conf" ]]; then
    err "Source VM config does not exist: ${PVE_QEMU_SERVER}/${src_vmid}.conf"
    exit 1
fi

if [[ -f "${PVE_QEMU_SERVER}/${dst_vmid}.conf" ]]; then
    err "Destination VM config already exists: ${PVE_QEMU_SERVER}/${dst_vmid}.conf"
    exit 1
fi

# Rename a single zvol (same-pool: zfs rename; cross-pool: zfs send|receive)
zfs_rename_zvol() {
    local src_zvol_dev="${1}"
    local dst_zvol_dev="${2}"

    if [[ ! -b "${src_zvol_dev}" ]]; then
        warn "Source zvol does not exist, skipping: ${src_zvol_dev}"
        return 0
    fi

    if [[ -b "${dst_zvol_dev}" ]]; then
        err "Destination zvol already exists: ${dst_zvol_dev}"
        return 1
    fi

    local src_zvol="${src_zvol_dev#/dev/}"
    local dst_zvol="${dst_zvol_dev#/dev/}"
    local src_pool="${src_zvol%%/*}"
    local dst_pool="${dst_zvol%%/*}"

    info "Renaming: ${src_zvol} -> ${dst_zvol}"

    if [[ "${APPLY}" == false ]]; then
        if [[ "${src_pool}" != "${dst_pool}" ]]; then
            local snap
            snap="zfs-rename-snap-$(date --utc +%F-%H%M%S)"
            echo "zfs snapshot ${src_zvol}@${snap}"
            echo "zfs send ${src_zvol}@${snap} | zfs receive ${dst_zvol}@${snap}"
        else
            echo "zfs rename ${src_zvol} ${dst_zvol}"
        fi
        return 0
    fi

    if [[ "${src_pool}" != "${dst_pool}" ]]; then
        local snap
        snap="zfs-rename-snap-$(date --utc +%F-%H%M%S)"
        zfs snapshot "${src_zvol}@${snap}"
        zfs send "${src_zvol}@${snap}" | zfs receive "${dst_zvol}@${snap}"
    else
        zfs rename "${src_zvol}" "${dst_zvol}"
    fi
    info "Done: ${src_zvol} -> ${dst_zvol}"
}

# Pattern for matching VM disk zvols
src_disk_regex="${src_zpool}(:|/)(base|vm)-${src_vmid}-(cloudinit|disk-[0-9]+)"
dst_disk_replacement="${dst_zpool}\1\2-${dst_vmid}-\3"

info "Processing VM rename: ${SOURCE} -> ${DEST}"

# Find and rename all VM zvols
readarray -t src_disks < <(
    find "/dev/zvol/${src_zpool}" -type l 2>/dev/null |
        grep -E "${src_disk_regex}$" || true
)

if [[ ${#src_disks[@]} -eq 0 ]]; then
    warn "No VM disks found for ${SOURCE}"
else
    info "Found ${#src_disks[@]} disk(s) to rename"
    for src_disk in "${src_disks[@]}"; do
        dst_disk="$(echo "${src_disk}" | sed -E "s%${src_disk_regex}%${dst_disk_replacement}%")"
        zfs_rename_zvol "${src_disk}" "${dst_disk}"
    done
fi

# Handle VM configuration file
src_conf="${PVE_QEMU_SERVER}/${src_vmid}.conf"
dst_conf="${PVE_QEMU_SERVER}/${dst_vmid}.conf"
backup_conf="${BACKUP_DIR}/${src_vmid}.conf"

info "Processing VM config: ${src_vmid}.conf -> ${dst_vmid}.conf"

if [[ "${APPLY}" == false ]]; then
    info "Dry-run: would backup and update VM config"
    echo "mkdir -p ${BACKUP_DIR}"
    echo "cp ${src_conf} ${backup_conf}"
    echo "sed -E 's%${src_disk_regex}%${dst_disk_replacement}%' ${backup_conf} >${dst_conf}"
    echo "rm ${src_conf}"
    exit 0
fi

mkdir -p "${BACKUP_DIR}"
cp -v "${src_conf}" "${backup_conf}"
sed -E "s%${src_disk_regex}%${dst_disk_replacement}%" "${backup_conf}" >"${dst_conf}"
diff "${backup_conf}" "${dst_conf}" || true
rm "${src_conf}"

info "VM rename complete. Config backup: ${BACKUP_DIR}"
