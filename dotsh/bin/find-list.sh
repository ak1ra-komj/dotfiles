#!/usr/bin/env bash

set -o errexit -o nounset

basedir="$(realpath -s "${1:-$(pwd)}")"

if [[ ! -d "${basedir}" ]]; then
    echo "Not a directory: ${basedir}" >&2
    exit 1
fi

(cd "${basedir}" && find . -type f | LANG=C.UTF-8 sort) | tee "${basedir}.list"
