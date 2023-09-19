#! /bin/bash
# author: ak1ra
# date: 2021-01-22
# alias kc="source ~/bin/k8s-kubeconfig-selector.sh"

clusters=($(find ~/.kube -type f -name '*.conf' | sort))

function menu() {
    for idx in ${!clusters[@]}; do
        printf "%3d | %s\n" "$((idx + 1))" "$(basename ${clusters[idx]} | cut -d. -f1)"
    done
}

menu
read -p "请根据索引选择 Kubernetes 集群: " choice
echo $choice | egrep -q '[1-9][0-9]?'
if [ $? -eq 0 ]; then
    export KUBECONFIG="${clusters[$((choice - 1))]}"
fi
