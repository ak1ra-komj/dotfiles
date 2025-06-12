#!/bin/bash
# How to deal with virtual-packages and meta-packages?

apt_download() {
    apt-cache depends \
        --recurse \
        --no-recommends \
        --no-suggests \
        --no-conflicts \
        --no-breaks \
        --no-replaces \
        --no-enhances "$@" |
        grep "^\w" | xargs apt-get download
}

apt_download "$@"
