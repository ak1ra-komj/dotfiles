#! /bin/bash
# author: ak1ra
# date: 2023-02-17
# convert cht text file (subtitles) to chs using opencc

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

opencc_cht2chs() {
    infile="$1"
    outfile="${infile%.cht.*}.utf8-chs.${infile##*.}"
    encoding=$(encguess "$infile" | awk '{print $NF}' | head -n1)
    iconv -f "$encoding" -t "UTF-8" "$infile" |
        opencc -c t2s.json -i /dev/stdin -o "$outfile"
}

main() {
    require_command parallel encguess iconv opencc

    export -f opencc_cht2chs
    find . -type f -name '*.cht.*' -print0 | parallel -0 opencc_cht2chs "{}"
}

main "$@"
