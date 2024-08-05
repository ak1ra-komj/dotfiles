#! /bin/bash
# ffprobe -v quiet -print_format json -show_streams video_file.mkv
# ffmpeg ... -map input_file_index:stream_type_specifier:stream_index

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
    $this [--dry-run] [--codec 'subtitle|audio|video'] FILE [FILE [FILE...]]

Options:
    -c, --codec         this is an 'egrep' regex pattern, indicate stream codec_type to select,
                        use 'audio|subtitle' to both select audio and subtitle streams, default is 'subtitle'.
    -d, --dry-run       dry run mode, only print 'ffmpeg' commands
    -h, --help          print this help message

Examples:
    # extract subtitles from input.mkv
    $this -c subtitle input.mkv

    # You can also use shell glob, for example,
    # extract subtitles and audio from *.mkv and *.mp4 files with shell glob expansion
    $this -c 'subtitle|audio' *.mkv *.mp4

EOF
    exit 0
}

extract_video_streams() {
    infile="$1"

    # ref: https://www.starkandwayne.com/blog/bash-for-loop-over-json-array-using-jq/
    readarray -t streams < <(
        ffprobe -v quiet -print_format json -show_streams "${infile}" | jq -c '.streams[]'
    )

    map_args=""
    for stream in "${streams[@]}"; do
        stream_codec_type="$(jq -r .codec_type <<<"${stream}")"
        if ! echo "${stream_codec_type}" | grep -qE "${codec_type}"; then
            continue
        fi

        stream_index="$(jq -r '.index' <<<"${stream}")"
        stream_codec_name="$(jq -r '.codec_name' <<<"${stream}" | sed 's/subrip/srt/g')"
        stream_language="$(jq -r '.tags.language' <<<"${stream}")"
        stream_output="${infile%.*}.${stream_language}.${stream_index}.${stream_codec_name}"

        map_args='-map "0:'"${stream_index}"'" "'"${stream_output}"'" '"${map_args}"''
    done

    if [ -n "${map_args}" ]; then
        cmd='ffmpeg -nostdin -n -v quiet -i "'"${infile}"'" '${map_args}''
        echo "${cmd}"
        if [ "${dry_run}" = "true" ]; then
            return
        fi
        eval "${cmd}"
    fi
}

main() {
    require_command ffmpeg ffprobe jq

    # default options
    dry_run=false
    codec_type="subtitle"

    getopt_args="$(getopt -a -o 'c:dh' -l 'codec:dry-run,help' -- "$@")"
    if ! eval set -- "${getopt_args}"; then
        usage
    fi

    while true; do
        case "$1" in
        -c | --codec)
            codec_type="$2"
            shift 2
            ;;
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
        extract_video_streams "${infile}"
    done
}

main "$@"
