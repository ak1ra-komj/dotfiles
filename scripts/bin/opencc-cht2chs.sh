#! /bin/bash
# author: ak1ra
# date: 2023-02-17
# convert cht text file (subtitles) to chs using opencc

if [ -f $HOME/.bash_functions ]; then
    source $HOME/.bash_functions
    check_command parallel encguess iconv opencc
fi

function opencc_cht2chs() {
    local infile="$1"
    local outfile="${infile%.cht.*}.utf8-chs.${infile##*.}"
    local encoding=$(encguess "$infile" | awk '{print $NF}' | head -n1)
    iconv -f "$encoding" -t "UTF-8" "$infile" | opencc -c t2s.json -i /dev/stdin -o "$outfile"
}

export -f opencc_cht2chs
find . -type f -name '*.cht.*' -print0 | parallel -0 opencc_cht2chs "{}"
