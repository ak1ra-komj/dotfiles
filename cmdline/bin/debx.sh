#!/bin/bash

debx() {
    # [SC2044 – For loops over find output are fragile](https://www.shellcheck.net/wiki/SC2044)
    # [SC3045 (error): In dash, read -d is not supported](https://www.shellcheck.net/wiki/SC3045)
    find . -maxdepth 1 -type f -name '*.deb' -print0 | while IFS= read -r -d '' file; do
        realpath="$(realpath -s "$file")"
        test -d "${realpath%.deb}" || {
            mkdir -p "${realpath%.deb}"
            cd "${realpath%.deb}" || return
            ar x "$realpath"
            mkdir control data
            tar -xf control.tar.* -C control
            tar -xf data.tar.* -C data
            cd "$(dirname "$realpath")" || return
        }
    done
}

debx "$@"
