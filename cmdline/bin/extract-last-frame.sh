#! /bin/bash
# select any frame, ref: https://superuser.com/a/1010108
# ffmpeg -i <infile> -vf "select=eq(n\,34)" -vframes 1 out.png
# select last frame, ref: https://superuser.com/a/1448673
# ffmpeg -sseof -3 -i input.mp4 -update 1 -q:v 1 last.png

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

extract_last_frame() {
    require_command ffmpeg

    find . -type f -print0 | while IFS= read -r -d '' infile; do
        if echo "$infile" | grep -qE '\.(mp4|mkv)$'; then
            ffmpeg -nostdin -n -v warning -sseof -1 -i "$infile" -update 1 "${infile%.*}.last-frame.png"
        fi
    done
}

extract_last_frame "$@"
