#! /bin/bash
# ffprobe -v quiet -print_format json -show_streams input.mkv
# ffmpeg ... -map input_file_index:stream_type_specifier:stream_index

function extract_streams() {
    local input="$1"
    local codec_type="$2"
    local dry_run="$3"
    # ref: https://www.starkandwayne.com/blog/bash-for-loop-over-json-array-using-jq/
    local streams_base64=$(ffprobe -v quiet -print_format json -show_streams "$input" | jq -r -c '.streams[] | @base64')
    local map_args=""
    for stream_base64 in $streams_base64; do
        local stream=$(echo $stream_base64 | base64 -d)
        local stream_codec_type=$(echo $stream | jq -r .codec_type)
        if ! echo "$stream_codec_type" | egrep -q "$codec_type"; then
            continue
        fi
        local stream_index=$(echo $stream | jq -r .index)
        local stream_codec_name=$(echo $stream | jq -r .codec_name | sed 's/subrip/srt/g')
        local stream_language=$(echo $stream | jq -r .tags.language)
        local stream_output="${input%.*}.${stream_language}.${stream_index}.${stream_codec_name}"
        local map_args="-map 0:$stream_index \"$stream_output\" $map_args"
    done

    if [ -n "$map_args" ]; then
        echo "ffmpeg -n -v warning -i \"$input\" $map_args"
        if [ "$dry_run" == "false" ]; then
            # about -nostdin option, ref: https://mywiki.wooledge.org/BashFAQ/089
            eval "ffmpeg -nostdin -n -v warning -i \"$input\" $map_args"
        fi
    fi
}

function usage() {
    cat << _EOF
Usage:
    extract-streams.sh [--dry-run] [--input-glob <input_glob>] [--codec-type <codec_type>]

Options:
    -h, --help          print this help message
    -d, --dry-run       dry run mode, only print 'ffmpeg' commands
    -i, --input-glob    input glob pattern for 'find ... -name <input_glob>', default is '*.mkv'
    -c, --codec-type    this is an 'egrep' regex pattern, indicate stream codec_type to select,
                        use 'audio|subtitle' to both select audio and subtitle streams,
                        default is 'subtitle'.

_EOF
    exit 1
}

# default options
dry_run=false
input_glob="*.mkv"
codec_type="subtitle"

getopt_args=$(getopt -a -o hdi:c: -l "help,dry-run,input-glob:,codec-type:" -- "$@")
getopt_ret=$?
if [ "$getopt_ret" != "0" ]; then
    usage
fi

eval set -- "$getopt_args"
while true; do
    case "$1" in
        -h | --help) usage; shift;;
        -d | --dry-run) dry_run=true; shift;;
        -i | --input-glob) input_glob="$2"; shift 2;;
        -c | --codec-type) codec_type="$2"; shift 2;;
        --) shift; break;;
        *) echo "unexpected option: $1 - this should not happen."; usage;;
    esac
done

find . -type f -name "$input_glob" -print0 | while IFS= read -r -d '' file; do
    extract_streams "$file" "$codec_type" "$dry_run"
done

# # 另一种方法, 使用 parallel 并行执行,
# # stream 提取应该还是 IO-bound 型任务, ffmpeg 似乎会读入一遍 input?
# export -f extract_streams
# export codec_type dry_run
# find . -type f -name "$input_glob" -print0 | \
#     parallel -0 -Ifile extract_streams "file" "$codec_type" "$dry_run"
