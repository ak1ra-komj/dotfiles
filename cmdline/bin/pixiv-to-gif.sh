#!/bin/bash
# Convert all pxder downloaded Pixiv .zip archive to .gif/.mp4
# ref: https://github.com/Tsuk1ko/pxder

pixiv_to_gif() {
    infile="$1"
    format="$2"
    delay="$3"

    infile_realpath="$(realpath -s "$infile")"
    extract_dir="${infile_realpath%.zip}"

    # infile="(46671388)miku 深海少女@80ms.zip"
    test -n "$delay" || delay="$(echo "$infile" | sed -E 's%.*@([0-9]+)ms\.zip$%\1%')"
    outfile="${infile_realpath%@*}@${delay}ms.${format}"
    framerate="$(echo "scale=3;1000/${delay}" | bc)"

    cd "$(dirname "$infile_realpath")" || return
    test -f "$outfile" || {
        echo "convert '$infile_realpath' '$outfile'"
        unzip -q -o -d "$extract_dir" "$infile_realpath"

        cd "$extract_dir" || return
        ffmpeg -y -framerate "$framerate" -i "%06d.jpg" "$outfile" 2>/dev/null
        cd .. || return

        rm -rf "$extract_dir"
    }
    cd .. || return
}

main() {
    shlib="$(readlink -f ~/bin/shlib.sh)"
    test -f "$shlib" || return
    # shellcheck source=/dev/null
    . "$shlib"

    require_command ffmpeg unzip parallel

    format="$1"
    test -n "$format" || format=mp4

    export -f pixiv_to_gif
    find . -type f -name '*.zip' -print0 |
        parallel -0 pixiv_to_gif {} "$format"
}

main "$@"
