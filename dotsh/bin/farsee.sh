#!/bin/bash

set -o errexit -o nounset -o pipefail

pb_url="https://fars.ee/"
pb_dir="${HOME}/.local/fars.ee"
pb_jsonl="${pb_dir}/urls.jsonl"
test -d "${pb_dir}" || mkdir -p "${pb_dir}"

# https://fars.ee/a
pb() {
    curl -s -w "\n" -H "Accept: application/json" \
        -F "c=@${1:--}" "${pb_url}" | tee -a "${pb_jsonl}"
}

pb_delete_all() {
    mapfile -t uuid_array < <(jq -r .uuid "${pb_jsonl}")
    for uuid in "${uuid_array[@]}"; do
        [[ "${uuid}" = "null" ]] && continue
        (
            set -x
            curl -s -w "\n" -H "Accept: application/json" -XDELETE "${pb_url}${uuid}"
        )
    done
    rm -f "${pb_jsonl}"
}

main() {
    if [ "$#" = 1 ] && [ "$1" = "--delete" ]; then
        pb_delete_all
    fi
    pb "$@"
}

main "$@"
