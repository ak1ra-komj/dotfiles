# custom bash function

function sha256list {
    local dir="$1"
    local checksum="$(basename $dir).sha256"
    local filelist="$(basename $dir).list"

    if [ -d "$dir" ]; then
        pushd "$dir"
        find . -type f -exec sha256sum "{}" \; | tee -a "../$checksum"
        popd
        cut -d ' ' -f 2- $checksum | sed 's/^ *//' | LANG=C.UTF-8 sort > "$filelist"
    fi
}

function gen_list {
    local dir="$1"
    local list="$(basename $dir).list"

    if [ -d "$dir" ]; then
        pushd "$dir"
        find . -type f | LANG=C.UTF-8 sort | tee "../$list"
        popd
    fi
}
