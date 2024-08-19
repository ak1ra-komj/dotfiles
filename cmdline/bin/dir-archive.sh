#!/bin/sh
# date: 2024-08-19
# author: ak1ra
# create archives by directory

dir_archive() {
    case "$1" in
    7z)
        archive_cmd="7z a -- '%s.7z' '%s'"
        ;;
    zip)
        archive_cmd="zip -r '%s.zip' '%s'"
        ;;
    *)
        archive_cmd="tar -cf '%s.tar' '%s'"
        ;;
    esac

    find . -maxdepth 1 -type d |
        LANG=C.UTF-8 sort |
        awk '!/\.(\.|git)?$/ {printf("'"${archive_cmd}"'\n", $0, $0)}'
}

dir_archive "$@"
