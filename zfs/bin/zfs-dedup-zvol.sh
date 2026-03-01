#!/usr/bin/env bash

set -o errexit -o nounset -o errtrace

SCRIPT_NAME="$(basename "$(readlink -f "${0}")")"

info() { echo "${*}" >&2; }
warn() { echo "WARNING: ${*}" >&2; }
err() { echo "ERROR: ${*}" >&2; }

usage() {
    cat <<EOF
Usage:
    ${SCRIPT_NAME} [OPTIONS] <source_zpool> <destination_zpool>

    Delete zvols in the destination zpool that are duplicates of the source zpool.
    Identifies zvols matching '/vm-[0-9]+' in source and checks if they exist in
    destination. WARNING: Destructive and cannot be undone! Default is dry-run mode.

OPTIONS:
    -h, --help    Show this help message
    --apply       Actually execute the deletions (default is dry-run)

EXAMPLES:
    ${SCRIPT_NAME} data0 tank
    ${SCRIPT_NAME} --apply data0 tank
EOF
    exit 0
}

APPLY=false

args=$(getopt --options="h" --longoptions="help,apply" --name="${SCRIPT_NAME}" -- "$@") || usage
eval set -- "${args}"

while true; do
    case "${1}" in
        -h | --help) usage ;;
        --apply)
            APPLY=true
            shift
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
    err "Expected exactly two arguments: <source_zpool> <destination_zpool>"
    usage
fi

ZPOOL_SRC="${1}"
ZPOOL_DEST="${2}"

if [[ ! -d "/dev/${ZPOOL_SRC}" ]]; then
    err "Source zpool does not exist: ${ZPOOL_SRC}"
    exit 1
fi

if [[ ! -d "/dev/${ZPOOL_DEST}" ]]; then
    err "Destination zpool does not exist: ${ZPOOL_DEST}"
    exit 1
fi

info "Scanning for duplicate zvols from '${ZPOOL_SRC}' in '${ZPOOL_DEST}'"

readarray -t zvol_candidates < <(
    zfs list -H -o name -r "${ZPOOL_SRC}" |
        grep -E '/vm-[0-9]+' |
        sed "s%${ZPOOL_SRC}%${ZPOOL_DEST}%"
)

if [[ ${#zvol_candidates[@]} -eq 0 ]]; then
    info "No VM zvols found in source zpool"
    exit 0
fi

zvol_to_delete=()
for zvol in "${zvol_candidates[@]}"; do
    [[ -b "/dev/${zvol}" ]] && zvol_to_delete+=("${zvol}")
done

if [[ ${#zvol_to_delete[@]} -eq 0 ]]; then
    info "No duplicate zvols found in destination zpool"
    exit 0
fi

warn "Found ${#zvol_to_delete[@]} duplicate zvol(s) to delete:"
for zvol in "${zvol_to_delete[@]}"; do
    warn "  - ${zvol}"
done

if [[ "${APPLY}" == false ]]; then
    info "Dry-run mode: use --apply to execute the deletions"
    for zvol in "${zvol_to_delete[@]}"; do
        echo "zfs destroy -r ${zvol}"
    done
    exit 0
fi

warn "This will permanently destroy ${#zvol_to_delete[@]} zvol(s) and CANNOT be undone!"
read -r -p "Type 'YES_I_WANT_TO_DESTROY_MY_ZVOL' to continue: " choice

if [[ "${choice}" != "YES_I_WANT_TO_DESTROY_MY_ZVOL" ]]; then
    info "Operation cancelled"
    exit 0
fi

for zvol in "${zvol_to_delete[@]}"; do
    if [[ -b "/dev/${zvol}" ]]; then
        info "Destroying: ${zvol}"
        zfs destroy -r "${zvol}"
    fi
done

info "Deletion complete"
