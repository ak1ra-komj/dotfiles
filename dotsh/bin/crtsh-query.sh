#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

ALGORITHM="sha256"

main() {
    local cert_files=("$@")
    for cert in "${cert_files[@]}"; do
        if [[ ! -f "${cert}" ]]; then
            continue
        fi
        openssl x509 -noout -subject -issuer -dateopt iso_8601 -dates -in "${cert}"
        openssl x509 -noout -fingerprint -"${ALGORITHM}" -in "${cert}" |
            cut -d= -f2 |
            tr -d ':' |
            tr '[:upper:]' '[:lower:]' |
            sed "s|^|https://crt.sh/?${ALGORITHM}=|"
        echo
    done
}

main "$@"
