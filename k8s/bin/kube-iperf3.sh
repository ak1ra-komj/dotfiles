#!/bin/bash
# date: 2025-08-01
# author: ak1ra
# Perform iperf3 tests between Kubernetes Pods

set -o errexit -o nounset -o pipefail

script_name="$(basename "$(readlink -f "$0")")"

iperf3_server_ns="iperf3-server"
iperf3_client_ns="iperf3-client"
iperf3_image="ghcr.io/ak1ra-lab/iperf3"

usage() {
    cat <<EOF
Usage:
    $script_name [init] | [iperf3 options]

    Use '$script_name init' to create iperf3-server and iperf3-client DaemonSet on Kubernetes,
    The remaining options will pass to iperf3 client pod directly.

    The iperf3 test results will be saved in the output/ directory of the current directory.

Examples:
    $script_name -t 30
    $script_name -t 120 -R

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

create_iperf3_server() {
    kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: $iperf3_server_ns
  name: $iperf3_server_ns
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iperf3-server
  namespace: $iperf3_server_ns
  labels:
    app: iperf3-server
spec:
  selector:
    matchLabels:
      app: iperf3-server
  template:
    metadata:
      labels:
        app: iperf3-server
    spec:
      containers:
        - name: iperf3-server
          image: $iperf3_image
          args: ["-s"]
          ports:
            - protocol: TCP
              containerPort: 5201
            - protocol: UDP
              containerPort: 5201
EOF
    kubectl -n "$iperf3_server_ns" rollout status daemonset/iperf3-server --timeout=120s
}

create_iperf3_client() {
    kubectl apply -f - <<EOF
---
apiVersion: v1
kind: Namespace
metadata:
  labels:
    kubernetes.io/metadata.name: $iperf3_client_ns
  name: $iperf3_client_ns
---
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: iperf3-client
  namespace: $iperf3_client_ns
  labels:
    app: iperf3-client
spec:
  selector:
    matchLabels:
      app: iperf3-client
  template:
    metadata:
      labels:
        app: iperf3-client
    spec:
      containers:
        - name: iperf3
          image: $iperf3_image
          command: ["sleep", "infinity"]
EOF
    kubectl -n "$iperf3_client_ns" rollout status daemonset/iperf3-client --timeout=120s
}

kubectl_exec_iperf3() {
    output_dir="$(pwd)/output"
    test -d "$output_dir" || mkdir -p "$output_dir"
    output_file="$output_dir/kube-iperf3.$(date +%F_%H%M%S).txt"

    mapfile -t client_pods < <(kubectl -n "$iperf3_client_ns" -l app=iperf3-client get pods --no-headers -o json | jq -c .items[])
    mapfile -t server_pods < <(kubectl -n "$iperf3_server_ns" -l app=iperf3-server get pods --no-headers -o json | jq -c .items[])

    if [[ "${#client_pods[@]}" -eq 0 ]] || [[ "${#server_pods[@]}" -eq 0 ]]; then
        echo "No iperf3 client pods or server pods can be found... Use './$script_name init' to create it"
        exit 1
    fi

    for client_pod in "${client_pods[@]}"; do
        client_pod_name="$(jq -r .metadata.name <<<"$client_pod")"
        # client_pod_ip="$(jq -r .status.podIP <<<"$client_pod")"
        client_pod_node_name="$(jq -r .spec.nodeName <<<"$client_pod")"

        for server_pod in "${server_pods[@]}"; do
            # server_pod_name="$(jq -r .metadata.name <<<"$server_pod")"
            server_pod_ip="$(jq -r .status.podIP <<<"$server_pod")"
            server_pod_node_name="$(jq -r .spec.nodeName <<<"$server_pod")"
            echo "iperf3 start: ${client_pod_node_name} -> ${server_pod_node_name}" 2>&1 | tee -a "$output_file"
            (
                set -x
                kubectl -n "$iperf3_client_ns" exec -it "$client_pod_name" -- iperf3 -c "$server_pod_ip" "$@"
            ) 2>&1 | tee -a "$output_file"
        done
    done
}

main() {
    if [[ "$#" -ge 1 ]]; then
        if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
            usage
        fi

        if [[ "$1" == "init" ]]; then
            create_iperf3_server
            create_iperf3_client
            return
        fi
    fi

    kubectl_exec_iperf3 "$@"
}

require_command kubectl jq

main "$@"
