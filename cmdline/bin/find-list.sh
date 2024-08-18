#!/bin/bash

find_list() {
    basedir="$1"
    test -n "${basedir}" || basedir="$(pwd)"
    realpath="$(realpath -s "${basedir}")"

    test -d "${realpath}" && {
        cd "${realpath}" || return
        find . -type f | LANG=C.UTF-8 sort | tee "${realpath}.list"
        cd "$(dirname "${realpath}")" || return
    }
}

find_list "$@"
