#!/bin/bash

set -euo pipefail

author="ak1ra-(komj|lab)"

convert_remote() {
    local repo_dir="$1"
    local reverse="$2"
    local dry_run="$3"
    cd "$repo_dir" || {
        return 1
    }
    echo "processing: $(pwd) ..."

    local -a changes
    if [ "$reverse" = true ]; then
        mapfile -t changes < <(git remote -v |
            awk '$2 ~ /git@github\.com:/ && $2 !~ /'"$author"'/ {print $1" "$2}' |
            sort -u |
            sed -E 's%git@github\.com:%https://github.com/%')
    else
        mapfile -t changes < <(git remote -v |
            awk '$2 ~ /https?:\/\/github\.com\/'"$author"'/ {print $1" "$2}' |
            sort -u |
            sed -E 's%https?://github\.com/('"$author"')%git@github.com:\1%')
    fi

    if [ ${#changes[@]} -gt 0 ]; then
        for change in "${changes[@]}"; do
            if [ "${dry_run}" = "true" ]; then
                echo git remote set-url $change
            else
                git remote set-url $change
            fi
        done
    fi

    cd - >/dev/null 2>&1 || return 1
}

main() {
    local reverse=false
    local dry_run=false
    while [ $# -gt 0 ]; do
        case "$1" in
        -r | --reverse)
            reverse=true
            shift
            ;;
        -d | --dry-run)
            dry_run=true
            shift
            ;;
        *) break ;;
        esac
    done

    while IFS= read -r -d '' git_dir; do
        repo="$(dirname "$(realpath -s "${git_dir}")")"
        convert_remote "${repo}" "${reverse}" "${dry_run}"
    done < <(find . -type d -name '.git' -print0)
}

main "$@"
