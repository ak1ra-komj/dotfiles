#! /bin/bash
# select any frame, ref: https://superuser.com/a/1010108
# ffmpeg -i <input> -vf "select=eq(n\,34)" -vframes 1 out.png
# select last frame, ref: https://superuser.com/a/1448673
# ffmpeg -sseof -3 -i input.mp4 -update 1 -q:v 1 last.png

function check_exec() {
    for exe in $@; do
        hash "$exe" 2>/dev/null || {
            echo >&2 "Required command '$exe' is not installed. Aborting."
            exit 1
        }
    done
}
check_exec ffmpeg

function extract_last_frame() {
    local input="$1"
    local output="${input%.*}.last.png"
    echo "ffmpeg -nostdin -n -v warning -sseof -1 -i \"$input\" -update 1 \"$output\""
    eval "ffmpeg -nostdin -n -v warning -sseof -1 -i \"$input\" -update 1 \"$output\""
}

find . -type f -print0 | while IFS= read -r -d '' file; do
    if echo $file | grep -qE '*\.(mp4|mkv)$'; then
        extract_last_frame "$file"
    fi
done
