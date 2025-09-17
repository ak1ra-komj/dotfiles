#!/bin/bash

set -o errexit -o pipefail

crtsh_fingerprint() {
    local cert="$1"
    local algo="$2"
    test -n "${algo}" || algo=sha256
    openssl x509 -noout -subject -issuer -dateopt iso_8601 -dates -in "${cert}"
    openssl x509 -noout -fingerprint -"${algo}" -in "${cert}" |
        cut -d= -f2 |
        tr -d ':' |
        tr '[:upper:]' '[:lower:]' |
        sed "s|^|https://crt.sh/?${algo}=|"
}

crtsh_query() {
    for cert in "$@"; do
        echo "=== ${cert} ==="
        crtsh_fingerprint "$cert"
        echo
    done
}

crtsh_query "$@"
