#!/bin/bash
# author: ak1ra
# date: 2024-03-14
# rename my obsidian-vault files with last modified date prefix

main() {
    mapfile -t src_files < <(
        find "$1" -type f -exec \
            realpath --strip --relative-to="$(pwd)" "{}" \; |
            grep -E '\.(md|txt|png|pdf|drawio|canvas)$'
    )

    for src in "${src_files[@]}"; do
        dirname="${src%/*}"
        basename="${src##*/}"

        date_prefix_regex="^(([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{2})-)?"
        # stat -c --format, %X - access, %Y - modify, %W - birth, %Z - status change
        date_prefix="$(date --date="@$(stat --format='%Y' "${src}")" +%F)-"
        dest="${dirname}/$(echo "${basename}" | sed -E 's%'"${date_prefix_regex}"'%'"${date_prefix}"'%')"

        if [ "${src}" != "${dest}" ]; then
            mv -v "${src}" "${dest}"
        fi
    done
}

main "$@"
