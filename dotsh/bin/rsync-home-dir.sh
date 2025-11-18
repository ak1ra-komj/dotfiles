#!/bin/bash
# --exclude=PATTERN, exclude files matching PATTERN
# --exclude-from=FILE, read exclude patterns from FILE

set -o errexit -o nounset -o pipefail

script_name="$(basename "$(readlink -f "$0")")"
env_file="${script_name%.sh}.env"

test -f "${env_file}" || exit 1
# shellcheck source=/dev/null
. "${env_file}"

# set `remote_dir` in env_file
: "${remote_dir?}"

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
        --exclude='.vscode-server' \
        --exclude='.cursor-server' \
        "${HOME}/" "${remote_dir}"
)
