#!/bin/bash

set -o errexit -o nounset -o pipefail

farsee="${HOME}/.local/fars.ee"
test -d "${farsee}" || mkdir -p "${farsee}"

# https://fars.ee/
# alias pb='curl -H "Accept: application/json" -F "c=@-" "https://fars.ee/"'
pb() {
    curl -s -H "Accept: application/json" -F "c=@${1:--}" "https://fars.ee/" |
        jq -c . | tee -a "${farsee}/urls.json" | jq -r '.url'
}

pb "$@"
