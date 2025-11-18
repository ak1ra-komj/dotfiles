#! /bin/bash
# Author: ak1ra
# Date: 2020-05-22
# Update:
#   * 2021-03-12, add --invert-match option
#   * 2023-06-26, add --help option

function usage() {
    cat <<EOF
Usage:
    ./docker-rm.sh [-v|--invert-match] [pattern]

Examples:
    ./docker-rm.sh
    ./docker-rm.sh 'openjdk-base'
    ./docker-rm.sh --invert-match 'k8s.gcr.io|quay.io|calico|traefik'

    when no pattern provided, default pattern is '<none>'

EOF
    exit 1
}

function docker_rm() {
    local exited_containers="$(docker ps -a | awk '/Exited/ {print $1}')"
    if [ -n "$exited_containers" ]; then
        docker ps -a | awk '/Exited/'
        docker rm -f $exited_containers
    fi
}

function docker_image_rm() {
    local invert_match=false
    if [ "$1" == "-v" ] || [ "$1" == "--invert-match" ]; then
        invert_match=true
        shift
    fi
    local pattern="$1"

    local images_to_del=""
    test -n "$pattern" || pattern="<none>"
    if [ "$pattern" == "<none>" ]; then
        images_to_del="$(docker image ls | awk '/'$pattern'/ {print $3}')"
    else
        if [ "$invert_match" == "true" ]; then
            images_to_del="$(docker image ls | awk 'NR > 1 && !/'$pattern'/ {printf("%s:%s ", $1, $2)}')"
        else
            images_to_del="$(docker image ls | awk 'NR > 1 &&  /'$pattern'/ {printf("%s:%s ", $1, $2)}')"
        fi
    fi

    if [ -n "$images_to_del" ]; then
        if [ "$invert_match" == "true" ]; then
            docker image ls | awk '!/'$pattern'/'
        else
            docker image ls | awk ' /'$pattern'/'
        fi
        echo $images_to_del | tr ' ' '\n' | xargs -P10 -L1 docker image rm
    fi
}

if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    usage
fi

docker_rm
docker_image_rm $@
