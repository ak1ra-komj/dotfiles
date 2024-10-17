#!/bin/sh
# date: 2024-08-19
# author: ak1ra
# create archives by directory

usage() {
    cat <<EOF
Usage:
    dir-archive.sh [7z|zip|tar]

Examples:
    Show archive commands:
        dir-archive.sh 7z

    The output is manually passed to 'sh' to be executed sequentially:
        dir-archive.sh 7z | sh

EOF
    exit 0
}

dir_archive() {
    case "$1" in
    7z)
        # 7zip has builin multiprocessing
        archive_cmd="$(command -v 7z) a -r -- '%s.7z' '%s'"
        ;;
    zip)
        archive_cmd="$(command -v zip) -r '%s.zip' -- '%s'"
        ;;
    *)
        archive_cmd="$(command -v tar) -cf '%s.tar' -- '%s'"
        ;;
    esac

    find . -maxdepth 1 -type d |
        LANG=C.UTF-8 sort |
        awk '!/\.(\.|git)?$/ {printf("'"${archive_cmd}"'\n", $0, $0)}'
}

if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    usage
fi

dir_archive "$@"
