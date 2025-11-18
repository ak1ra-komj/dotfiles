#! /bin/bash
# Author: ak1ra
# Date: 2020-05-22
# Update:
#   * 2021-03-12, add --invert-match option
#   * 2023-06-26, add --help option
#   * 2025-11-18, refactoring docker-rm.sh

set -o errexit -o nounset -o pipefail

script_name="$(basename "$(readlink -f "$0")")"

usage() {
    cat <<EOF
Usage:
    $script_name [options] [pattern]

Options:
    -v, --invert-match      Invert the pattern match
    --apply                 Actually delete images (default: dry-run)
    -h, --help              Show this help

Examples:
    $script_name                       # Dry-run, match <none>
    $script_name --apply               # Apply deletion of <none> images
    $script_name 'openjdk-base'        # Dry-run, match 'openjdk-base'
    $script_name --invert-match 'k8s.gcr.io|quay.io|calico|traefik'
EOF
    exit 1
}

docker_rm() {
    mapfile -t exited_containers < <(
        docker ps -a --format '{{.ID}} {{.Status}}' |
            awk '/Exited/ {print $1}'
    )

    if ((${#exited_containers[@]} > 0)); then
        echo "Exited containers to remove:"
        docker ps -a | awk '/Exited/'
        if $apply; then
            docker rm -f "${exited_containers[@]}"
        else
            echo "[Dry-run] Would remove exited containers: ${exited_containers[*]}"
        fi
    else
        echo "No exited containers found."
    fi
}

docker_image_rm() {
    # Fetch all images once
    mapfile -t images < <(
        docker image ls --format '{{.ID}} {{.Repository}} {{.Tag}}'
    )

    images_to_del=()

    for entry in "${images[@]}"; do
        read -r id repo tag <<<"$entry"
        name="$repo:$tag"

        if [[ "$pattern" == "<none>" ]]; then
            [[ "$tag" == "<none>" ]] && images_to_del+=("$id")
            continue
        fi

        if $invert_match; then
            [[ ! "$name" =~ $pattern ]] && images_to_del+=("$name")
        else
            [[ "$name" =~ $pattern ]] && images_to_del+=("$name")
        fi
    done

    if ((${#images_to_del[@]} > 0)); then
        echo "Images selected for deletion (dry-run by default):"
        printf "%s\n" "${images_to_del[@]}"

        if $apply; then
            printf "%s\n" "${images_to_del[@]}" | xargs -P10 -L1 docker image rm
            echo "Deletion completed."
        else
            echo "[Dry-run] No images deleted. Use --apply to actually delete."
        fi
    else
        echo "No images match the pattern."
    fi
}

main() {
    # Default values
    invert_match=false
    apply=false
    pattern="<none>"

    # Use getopt for robust parsing
    ARGS=$(getopt -o vh --long invert-match,apply,help -n "$script_name" -- "$@")
    if ! eval set -- "$ARGS"; then
        usage
    fi

    while true; do
        case "$1" in
            -v | --invert-match)
                invert_match=true
                shift
                ;;
            --apply)
                apply=true
                shift
                ;;
            -h | --help)
                usage
                ;;
            --)
                shift
                break
                ;;
            *)
                echo "Unknown option: $1"
                usage
                ;;
        esac
    done

    # Remaining argument is the pattern
    if [ $# -ge 1 ]; then
        pattern="$1"
    fi

    docker_rm
    docker_image_rm
}

main "$@"
