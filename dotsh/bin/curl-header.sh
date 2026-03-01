#!/usr/bin/env bash
# alias curl-header="curl -s --dump-header % -o /dev/null"

set -o errexit -o nounset
set -x

curl -s --dump-header % -o /dev/null "${@}"
