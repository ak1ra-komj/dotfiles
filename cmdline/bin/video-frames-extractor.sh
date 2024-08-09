#! /bin/bash
# select any frame, ref: https://superuser.com/a/1010108
# ffmpeg -i <infile> -vf "select=eq(n\,34)" -vframes 1 out.png
# select last frame, ref: https://superuser.com/a/1448673
# ffmpeg -sseof -3 -i input.mp4 -update 1 -q:v 1 last.png

set -o errexit

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

usage() {
    this="$(basename $(readlink -f "$0"))"

    cat <<EOF
Usage:
    $this [--dry-run] FILE [FILE [FILE...]]

Options:
    -d, --dry-run       dry run mode, only print 'ffmpeg' commands
    -h, --help          print this help message

EOF
    exit 0
}

video_frames_extractor() {
    infile="$1"
    test -n "${sseof}" || sseof=3

    cmd='ffmpeg -nostdin -n -v quiet -sseof -'"${sseof}"' -i "'"${infile}"'" -update 1 "'"${infile%.*}"'.last.png"'
    echo "${cmd}"
    if [ "${dry_run}" = "true" ]; then
        return
    fi
    eval "${cmd}"
}

main() {
    require_command ffmpeg

    # default options
    dry_run=false

    getopt_args="$(getopt -a -o 'dh' -l 'dry-run,help' -- "$@")"
    if ! eval set -- "${getopt_args}"; then
        usage
    fi

    while true; do
        case "$1" in
        -d | --dry-run)
            dry_run=true
            shift
            ;;
        -h | --help)
            usage
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "unexpected option: $1"
            usage
            ;;
        esac
    done

    readarray -t infiles < <(ls "$@")
    for infile in "${infiles[@]}"; do
        video_frames_extractor "${infile}"
    done
}

main "$@"
