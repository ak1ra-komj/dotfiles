#! /bin/bash
# Author: ak1ra
# Date: 2020-05-22
# Update:
#   * 2021-03-12, add invert-match

function docker_rm() {
    exited_containers="$(docker ps -a | awk '/Exited/ {print $1}')"
    if [ -n "$exited_containers" ]; then
        docker ps -a | awk '/Exited/'
        docker rm -f $exited_containers
    fi
}

function docker_image_rm() {
    pattern="$1"
    invert_match="$2"
    test -n "$pattern" || pattern="<none>"
    if [ "$pattern" == "<none>" ]; then
        images_to_del="$(docker image ls | awk '/'$pattern'/ {print $3}')"
    else
        if [ "$invert_match" == "invert-match" ]; then
            images_to_del="$(docker image ls | awk 'NR > 1 && !/'$pattern'/ {printf("%s:%s ", $1, $2)}')"
        else
            images_to_del="$(docker image ls | awk 'NR > 1 &&  /'$pattern'/ {printf("%s:%s ", $1, $2)}')"
        fi
    fi
    if [ -n "$images_to_del" ]; then
        if [ "$invert_match" == "invert-match" ]; then
            docker image ls | awk '!/'$pattern'/'
        else
            docker image ls | awk '/'$pattern'/'
        fi
        echo $images_to_del | tr ' ' '\n' | xargs -P10 -L1 docker image rm
    fi
}

docker_rm
docker_image_rm
docker_image_rm "ccr.ccs.tencentyun.com"
docker_image_rm "k8s.gcr.io|quay.io|calico|traefik" "invert-match"
