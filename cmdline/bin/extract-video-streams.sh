#! /bin/bash
# ffprobe -v quiet -print_format json -show_streams infile.mkv
# ffmpeg ... -map input_file_index:stream_type_specifier:stream_index

usage() {
    this="$(readlink -f "$0")"

    cat <<_EOF
Usage:
    $this [--dry-run] [--glob <glob>] [--codec-type <codec_type>]

Options:
    -h, --help          print this help message
    -d, --dry-run       dry run mode, only print 'ffmpeg' commands
    -g, --glob          infile glob pattern for 'find ... -name <glob>', default is '*.mkv'
    -c, --codec-type    this is an 'egrep' regex pattern, indicate stream codec_type to select,
                        use 'audio|subtitle' to both select audio and subtitle streams,
                        default is 'subtitle'.

_EOF
    exit 1
}

extract_video_streams() {
    infile="$1"
    codec_type="$2"
    dry_run="$3"
    # ref: https://www.starkandwayne.com/blog/bash-for-loop-over-json-array-using-jq/
    mapfile -t streams_base64 < <(ffprobe -v quiet -print_format json -show_streams "$infile" | jq -r -c '.streams[] | @base64')
    map_args=""
    for stream_base64 in "${streams_base64[@]}"; do
        stream="$(echo "$stream_base64" | base64 -d)"
        stream_codec_type="$(echo "$stream" | jq -r .codec_type)"
        if ! echo "$stream_codec_type" | grep -qE "$codec_type"; then
            continue
        fi
        stream_index="$(echo "$stream" | jq -r .index)"
        stream_codec_name="$(echo "$stream" | jq -r .codec_name | sed 's/subrip/srt/g')"
        stream_language="$(echo "$stream" | jq -r .tags.language)"
        stream_output="${infile%.*}.${stream_language}.${stream_index}.${stream_codec_name}"
        map_args="-map 0:$stream_index \"$stream_output\" $map_args"
    done

    if [ -n "$map_args" ]; then
        echo "ffmpeg -n -v warning -i \"$infile\" $map_args"
        if [ "$dry_run" = "false" ]; then
            # about -nostdin option, ref: https://mywiki.wooledge.org/BashFAQ/089
            eval "ffmpeg -nostdin -n -v warning -i \"$infile\" $map_args"
        fi
    fi
}

main() {
    shlib="$(readlink -f ~/bin/shlib.sh)"
    test -f "$shlib" || return
    # shellcheck source=/dev/null
    . "$shlib"

    require_command ffmpeg ffprobe jq

    # default options
    dry_run=false
    glob="*.mkv"
    codec_type="subtitle"

    getopt_args="$(getopt -a -o hdg:c: -l "help,dry-run,glob:,codec-type:" -- "$@")"
    getopt_ret=$?
    if [ "$getopt_ret" != "0" ]; then
        usage
    fi

    eval set -- "$getopt_args"
    while true; do
        case "$1" in
        -h | --help)
            usage
            ;;
        -d | --dry-run)
            dry_run=true
            shift
            ;;
        -g | --glob)
            glob="$2"
            shift 2
            ;;
        -c | --codec-type)
            codec_type="$2"
            shift 2
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "unexpected option: $1 - this should not happen."
            usage
            ;;
        esac
    done

    find . -type f -name "$glob" -print0 | while IFS= read -r -d '' file; do
        extract_video_streams "$file" "$codec_type" "$dry_run"
    done
}

main "$@"
