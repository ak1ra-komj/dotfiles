#!/bin/bash
# author: ak1ra
# date: 2023-07-31
# kube-dump Kubernetes resource manifests in particular namespace

set -o errexit -o nounset -o pipefail

usage() {
    cat <<EOF

Usage:
    ./kube-dump.sh [[-A|--all-namespaces] | ns1 [ns2]]

    '--all-namespaces' means dump ALL namespaces,
    when no '--all-namespaces' option present, multiple namespaces separated by space

EOF
    exit 0
}

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

kube_dump() {
    namespace="$1"

    # https://stackoverflow.com/a/42636398
    # with_entries(select( .key | test(PATTERN) | not))
    # walk(if type == "object" then with_entries(select(.key | test(PATTERN) | not)) else . end)
    # jq uses the Oniguruma regular expression library, as do PHP, ..., so the description here will focus on jq specifics.
    jq_cattle_regex='^(?:(?:authz\.cluster|secret\.user|field|lifecycle|listener|workload)\.)?cattle\.io\/'

    if ! kubectl get namespaces --no-headers --output=name | grep -qE "namespace/${namespace}$"; then
        echo "namespace: ${namespace} does not exist, ignore..."
        return
    fi

    for api_resource in "${api_resources[@]}"; do
        readarray -t resources_with_prefix < <(
            kubectl --namespace "${namespace}" get "${api_resource}" --no-headers --ignore-not-found --output=name
        )
        for resource in "${resources_with_prefix[@]}"; do
            resource_dir="${namespace}/${api_resource}"
            test -d "${resource_dir}" || mkdir -p "${resource_dir}"
            # 特别注意: --arg name value 不能添加 = 连接, 之前踩过好几次坑, 怎么使用 = 连接反而不生效呢?
            # jq 中的 test($jq_cattle_regex) 理应无需添加 "", 因为 --arg name value 传入的变量都会被当作 字符串 处理
            kubectl --namespace "${namespace}" get "${resource}" --output=json |
                jq --arg jq_cattle_regex "${jq_cattle_regex}" --indent 4 --sort-keys 'walk(
                    if type == "object" then with_entries(select(.key | test($jq_cattle_regex) | not)) else . end)
                    | del(
                        .metadata.namespace,
                        .metadata.annotations."deployment.kubernetes.io/revision",
                        .metadata.annotations."kubectl.kubernetes.io/last-applied-configuration",
                        .metadata.creationTimestamp,
                        .metadata.generation,
                        .metadata.managedFields,
                        .metadata.resourceVersion,
                        .metadata.selfLink,
                        .metadata.uid,
                        .metadata.ownerReferences,
                        .status,
                        .spec.clusterIP
                )' >"${resource_dir}/${resource#*/}.json"
        done
    done
}

main() {
    if [ "$#" -eq 0 ] || [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
        usage
    fi

    # Prefer readarray or read -a to split command output (or quote to avoid splitting).
    # https://www.shellcheck.net/wiki/SC2207
    readarray -t api_resources < <(kubectl api-resources --namespaced --no-headers --output=name | grep -v 'events')

    if [ "$1" = "-A" ] || [ "$1" = "--all-namespaces" ]; then
        readarray -t namespaces < <(kubectl get namespaces --no-headers --output=name)
        shift 1
    else
        # Assigning an array to a string! Assign as array, or use * instead of @ to concatenate.
        # https://www.shellcheck.net/wiki/SC2124
        namespaces=("$@")
    fi

    for namespace in "${namespaces[@]}"; do
        kube_dump "${namespace#namespace/}"
    done
}

require_command kubectl jq

main "$@"
