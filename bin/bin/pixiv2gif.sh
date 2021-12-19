#! /bin/bash

function pixiv2gif() {
    local infile="$1"
    local delay="$2"
    local infile_dir=$(dirname "$infile")
    local infile_basename=$(basename "$infile")
    local exdir="${infile_basename%.*}"

    test -n "$delay" || local delay="$(echo ${exdir#*@} | sed 's/ms//')"
    local outfile="${exdir%@*}@${delay}ms.webp"

    cd "$infile_dir"
    if [ ! -f "$outfile" ]; then
        echo "pixiv2gif '$infile' '$infile_dir/$outfile'"
        unzip -q -o -d "$exdir" "$infile_basename"

        cd "$exdir"
        local fps="$(echo 'scale=3;1000/'$delay'' | bc)"
        ffmpeg -y -framerate "$fps" -i "%06d.jpg" "../$outfile" 2>/dev/null
        cd ../

        rm -rf "$exdir"
    fi
    cd ../
}

export -f pixiv2gif
find . -type f -name '*.zip' -print0 | \
    parallel -0 pixiv2gif {}
