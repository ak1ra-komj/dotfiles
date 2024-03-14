#!/bin/bash

main() {
    mapfile -t src_files < <(
        find "$1" -type f |
            xargs realpath --relative-to="$(pwd)" -s |
            grep -E '\.(md|txt|png|pdf|drawio)$'
    )

    for src in "${src_files[@]}"; do
        dirname="${src%/*}"
        basename="${src##*/}"

        date_prefix_regex="^(([0-9]{4}-[0-9]{2}-[0-9]{2}|[0-9]{2})-)?"
        # stat -c --format, %X - access, %Y - modify, %W - birth, %Z - status change
        date_prefix="$(date --date="@$(stat --format='%Y' "${src}")" +%F)-"
        dest="${dirname}/$(echo "${basename}" | sed -E 's%'"${date_prefix_regex}"'%'"${date_prefix}"'%')"

        mv -v "${src}" "${dest}"
    done
}

main "$@"
