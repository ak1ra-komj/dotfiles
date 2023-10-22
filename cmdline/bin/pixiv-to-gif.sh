#! /bin/bash

function pixiv2gif() {
    infile="$1"
    outfile_format="$2"
    delay="$3"
    infile_dir=$(dirname "$infile")
    infile_basename=$(basename "$infile")
    exdir="${infile_basename%.*}"

    test -n "$delay" || delay="$(echo "${exdir#*@}" | sed 's/ms//')"
    outfile="${exdir%@*}@${delay}ms.${outfile_format}"
    framerate="$(echo 'scale=3;1000/'"$delay"'' | bc)"

    cd "$infile_dir" || return
    if [ ! -f "$outfile" ]; then
        echo "pixiv2gif '$infile' '$infile_dir/$outfile'"
        unzip -q -o -d "$exdir" "$infile_basename"

        cd "$exdir" || return
        ffmpeg -y -framerate "$framerate" -i "%06d.jpg" "../$outfile" 2>/dev/null
        cd ../ || return

        rm -rf "$exdir"
    fi
    cd ../ || return
}

main() {
    shlib="$(readlink -f ~/bin/shlib.sh)"
    test -f "$shlib" || return
    # shellcheck source=/dev/null
    . "$shlib"

    require_command ffmpeg unzip parallel

    outfile_format="$1"
    test -n "$outfile_format" || outfile_format=mp4

    export -f pixiv2gif
    find . -type f -name '*.zip' -print0 |
        parallel -0 pixiv2gif {} "$outfile_format"
}

main "$@"
