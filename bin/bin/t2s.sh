#! /bin/bash

function t2s() {
    local input="$1"
    local output="$(echo $1 | sed 's/cht/chs/')"
    local enc=$(encguess "$1" | awk '{print $NF}' | head -n1)
    iconv -f "$enc" -t "UTF-8" "$1" | opencc -c t2s.json -i /dev/stdin -o "$output"
}

export -f t2s
find . -type f -name '*.cht.ssa' -print0 | parallel -0 t2s "{}"
