#!/bin/bash

# SC3045 (error): In dash, read -d is not supported.
find . -maxdepth 1 -type f -name '*.deb' -print0 | while IFS= read -r -d '' file; do
    realpath="$(realpath -s "$file")"
    test -d "${realpath%.deb}" || {
        mkdir -p "${realpath%.deb}"
        cd "${realpath%.deb}" && {
            ar x "$realpath"
            mkdir control data
            tar -xf control.tar.xz -C control
            tar -xf data.tar.xz -C data
        }
    }
done
