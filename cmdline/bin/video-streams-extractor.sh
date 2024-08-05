#! /bin/bash
# ffprobe -v quiet -print_format json -show_streams infile.mkv
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
    this="$(readlink -f "$0")"

    cat <<_EOF
Usage:
    $this [--dry-run] [--glob <glob>] [--codec <codec_type>]

Options:
    -c, --codec         this is an 'egrep' regex pattern, indicate stream codec_type to select,
                        use 'audio|subtitle' to both select audio and subtitle streams, default is 'subtitle'.
    -g, --glob          infile glob pattern for 'find ... -name \$glob', default is '*.mkv'
    -d, --dry-run       dry run mode, only print 'ffmpeg' commands
    -h, --help          print this help message

_EOF
    exit 1
}

extract_video_streams() {
    infile="$1"
    codec_type="$2"
    dry_run="$3"
    # ref: https://www.starkandwayne.com/blog/bash-for-loop-over-json-array-using-jq/
    readarray -t streams < <(
        ffprobe -loglevel quiet -print_format json -show_streams "${infile}" | jq -c '.streams[]'
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
        cmd='ffmpeg -nostdin -n -loglevel quiet -i "'"${infile}"'" '${map_args}''
        if [ "${dry_run}" = "true" ]; then
            cmd="echo '${cmd}'"
        fi
        (
            set -x
            eval "${cmd}"
        )
    fi
}

main() {
    require_command ffmpeg ffprobe jq

    # default options
    dry_run=false
    glob="*.mkv"
    codec_type="subtitle"

    getopt_args="$(getopt -a -o 'g:c:dh' -l 'glob:,codec:dry-run,help' -- "$@")"
    if ! eval set -- "${getopt_args}"; then
        usage
    fi

    while true; do
        case "$1" in
        -c | --codec)
            codec_type="$2"
            shift 2
            ;;
        -g | --glob)
            glob="$2"
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

    find . -type f -name "$glob" -print0 | while IFS= read -r -d '' file; do
        extract_video_streams "$file" "$codec_type" "$dry_run"
    done
}

main "$@"
