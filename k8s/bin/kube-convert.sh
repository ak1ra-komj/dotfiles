#!/bin/bash
# a kubectl-convert plugin wrapper, convert all manifests between different API versions
# before you running this script, remember to git init your kube-dump.sh directory first
# https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/#install-kubectl-convert-plugin

set -o errexit
set -o nounset
set -o pipefail

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

kube_convert() {
    tempdir=$(mktemp -d /tmp/kube-dump.XXXXXX)
    find . -type f -name '*.yaml' -print0 | while IFS= read -r -d '' f; do
        tempf=$(mktemp "${tempdir}/kube-convert.XXXXXXXXX")
        if kubectl convert --local -f "$f" -o yaml >"$tempf"; then
            mv "$tempf" "$f"
        fi
    done
    rm -rf "$tempdir"
}

require_command kubectl kubectl-convert

kube_convert
