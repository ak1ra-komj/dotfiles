#!/bin/bash
# [SC2044 – For loops over find output are fragile](https://www.shellcheck.net/wiki/SC2044)
# [SC3045 (error): In dash, read -d is not supported](https://www.shellcheck.net/wiki/SC3045)

deb_extract() {
    find . -maxdepth 1 -type f -name '*.deb' -print0 | while IFS= read -r -d '' file; do
        realpath="$(realpath -s "$file")"
        test -d "${realpath%.deb}" || {
            mkdir -p "${realpath%.deb}"/{control,data}
            cd "${realpath%.deb}" || return
            ar x "$realpath"
            tar -xf control.tar.* -C control
            tar -xf data.tar.* -C data
            cd "$(dirname "$realpath")" || return
        }
    done
}

deb_extract_delete() {
    find . -maxdepth 1 -type f -name '*.deb' -print0 | while IFS= read -r -d '' file; do
        realpath="$(realpath -s "$file")"
        test -d "${realpath%.deb}" || rm -r "${realpath%.deb}"
    done
}

if [[ "$1" == "-d" ]] || [[ "$1" == "--delete" ]]; then
    shift
    deb_extract_delete "$@"
else
    deb_extract "$@"
fi
