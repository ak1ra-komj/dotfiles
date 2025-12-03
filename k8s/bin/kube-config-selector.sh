#!/bin/bash
# author: ak1ra
# date: 2021-01-22
# alias kc="source ~/bin/kube-config-selector.sh"

# https://www.shellcheck.net/wiki/SC2207
readarray -t clusters < <(
    find ~/.kube -type f -name '*.conf' | sort
)

menu() {
    for idx in "${!clusters[@]}"; do
        printf "%3d | %s\n" "$((idx + 1))" "$(basename "${clusters[idx]}" | cut -d. -f1)"
    done
}

menu
printf "请根据索引选择 Kubernetes 集群: "
read -r choice
if echo "$choice" | grep -qE '[1-9][0-9]?'; then
    export KUBECONFIG="${clusters[$((choice - 1))]}"
fi
