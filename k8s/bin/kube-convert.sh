#!/bin/bash
# a kubectl-convert plugin wrapper, convert all manifests between different API versions
# before you running this script, remember to git init your kube-dump.sh directory first
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-convert-plugin

set -o errexit
set -o nounset
set -o pipefail

kube_convert() {
    shlib="$(readlink -f ~/bin/shlib.sh)"
    test -f "$shlib" || return
    # shellcheck source=/dev/null
    . "$shlib"

    require_command kubectl kubectl-convert

    tempdir=$(mktemp -d /tmp/kube-dump.XXXXXX)
    find . -type f -name '*.json' -print0 | while IFS= read -r -d '' f; do
        tempf=$(mktemp "${tempdir}/kube-convert.XXXXXXXXX")
        if kubectl convert --local -f "$f" -o json >"$tempf"; then
            mv "$tempf" "$f"
        fi
    done
    rm -rf "$tempdir"
}

kube_convert
