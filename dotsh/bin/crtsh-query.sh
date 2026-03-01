#!/usr/bin/env bash

set -o errexit -o nounset -o pipefail

crtsh_fingerprint() {
    local cert="${1}"
    local algo="${2:-sha256}"
    openssl x509 -noout -subject -issuer -dateopt iso_8601 -dates -in "${cert}"
    openssl x509 -noout -fingerprint -"${algo}" -in "${cert}" |
        cut -d= -f2 |
        tr -d ':' |
        tr '[:upper:]' '[:lower:]' |
        sed "s|^|https://crt.sh/?${algo}=|"
}

for cert in "${@}"; do
    echo "=== ${cert} ==="
    crtsh_fingerprint "${cert}"
    echo
done
