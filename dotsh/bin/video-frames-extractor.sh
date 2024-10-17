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
    $this [--dry-run] [--sseof SECONDS] FILE [FILE [FILE...]]

Options:
    -d, --dry-run       dry run mode, only print 'ffmpeg' commands
    -s, --sseof         seconds from end to start extracting frames (default: 3)
    -h, --help          print this help message

EOF
    exit 0
}

video_frames_extractor() {
    infile="$1"
    test -n "${sseof}" || sseof=3

    temp_dir=$(mktemp -d)

    cmd='ffmpeg -nostdin -n -v quiet -sseof -'"${sseof}"' -i "'"${infile}"'" -vf "select=not(mod(n\,1))" -vsync vfr "'"${temp_dir}"'/frame_%03d.png"'
    echo "${cmd}"
    if [ "${dry_run}" = "true" ]; then
        rm -r "${temp_dir}"
        return
    fi
    eval "${cmd}"

    last_non_blank_frame=""
    readarray -t frames < <(find "${temp_dir}" -type f -name 'frame_*.png')
    for frame in "${frames[@]}"; do
        black_frame=$(ffmpeg -i "$frame" -vf "blackdetect=d=0:pix_th=0.1" -an -f null - 2>&1 | grep blackdetect || true)
        if [ -z "$black_frame" ]; then
            last_non_blank_frame="$frame"
            break
        fi
    done

    if [ -n "${last_non_blank_frame}" ]; then
        cp "${last_non_blank_frame}" "${infile%.*}.last.png"
    else
        echo "No non-blank frame found in the last ${sseof} seconds of ${infile}"
    fi

    rm -r "${temp_dir}"
}

main() {
    require_command ffmpeg

    # default options
    dry_run=false
    sseof=3

    getopt_args="$(getopt -a -o 'dhs:' -l 'dry-run,help,sseof:' -- "$@")"
    if ! eval set -- "${getopt_args}"; then
        usage
    fi

    while true; do
        case "$1" in
        -d | --dry-run)
            dry_run=true
            shift
            ;;
        -s | --sseof)
            sseof="$2"
            shift 2
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
