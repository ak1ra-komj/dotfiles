#!/usr/bin/env bash

set -o errexit -o nounset

apt-cache depends \
    --recurse \
    --no-recommends \
    --no-suggests \
    --no-conflicts \
    --no-breaks \
    --no-replaces \
    --no-enhances "$@" |
    grep -E "^\w" |
    xargs apt-get download
