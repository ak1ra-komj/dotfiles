#!/bin/bash
# --exclude=PATTERN, exclude files matching PATTERN
# --exclude-from=FILE, read exclude patterns from FILE
# shellcheck shell=bash source=dotsh/bin/rsync-home-dir.env

set -o errexit -o nounset -o pipefail

self="$(readlink -f "${BASH_SOURCE[0]}")"
env_file="${self%.sh}.env"

test -f "${env_file}" || exit 1
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
