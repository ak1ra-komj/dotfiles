#!/bin/bash
# custom shell function

shasum_list() {
    basedir="$1"
    algorithm="$2"
    # algorithm: 1, 224, 256 (default), 384, 512
    test -n "$algorithm" || algorithm=256
    shasum="sha${algorithm}sum"

    realpath="$(realpath -s "$basedir")"
    test -d "$realpath" && {
        tempfile="$(mktemp)"
        cd "$realpath" || return
        # bookworm: dpkg -S /usr/bin/shasum -> perl ?
        find . -type f -print0 |
            parallel -0 --max-lines=1 "$(command -v "$shasum")" | tee -a "$tempfile"
        cd "$(dirname "$realpath")" || return
        LANG=C.UTF-8 sort -k2 "$tempfile" >"${realpath}.${shasum}"
        rm -f "$tempfile"
    }
}

find_list() {
    basedir="$1"
    realpath="$(realpath -s "$basedir")"

    test -d "$realpath" && {
        cd "$realpath" || return
        find . -type f | LANG=C.UTF-8 sort | tee "${realpath}.list"
        cd "$(dirname "$realpath")" || return
    }
}
