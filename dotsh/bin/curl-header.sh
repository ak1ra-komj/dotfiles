#!/bin/bash
# alias curl-header="curl -s --dump-header % -o /dev/null"

set -o errexit -o pipefail

(
    set -x
    curl -s --dump-header % -o /dev/null "$@"
)
