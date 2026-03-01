#!/usr/bin/env bash
# Sync home directory to a remote location using rsync.
# Any extra arguments are passed directly to rsync, e.g.:
#   rsync-home-dir.sh --dry-run --verbose
#   rsync-home-dir.sh --progress

set -o errexit -o nounset

readonly ENV_FILE="${0%.sh}.env"

if [[ ! -f "${ENV_FILE}" ]]; then
    echo "Environment file not found: ${ENV_FILE}" >&2
    exit 1
fi

# shellcheck source=/dev/null
source "${ENV_FILE}"

if [[ -z "${REMOTE_DIR:-}" ]]; then
    echo "REMOTE_DIR is not set in ${ENV_FILE}" >&2
    exit 1
fi

(
    set -x
    rsync \
        --archive \
        --delete \
        --delete-excluded \
        --prune-empty-dirs \
        --exclude='.cache' \
        --exclude='.go' \
        --exclude='.rustup' \
        --exclude='.cargo' \
        --exclude='.nvm' \
        --exclude='.npm' \
        --exclude='.yarn' \
        --exclude='.vscode-server' \
        --exclude='.cursor-server' \
        --exclude='.antigravity-server' \
        "${@}" \
        "${HOME}/" "${REMOTE_DIR}"
)
