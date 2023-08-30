# custom http_proxy / https_proxy
# 在文件 ~/.http_proxy.json 中填入 proxy_host, proxy_port and no_proxy
if uname -a | grep --ignore-case -qE '(microsoft|wsl2?)'; then
    proxy_host="$(ip route show default | awk '{print $3}')"
else
    proxy_host=$(jq -r '.proxy_host' ~/.http_proxy.json)
fi
proxy_port=$(jq -r '.proxy_port' ~/.http_proxy.json)

export http_proxy="http://$proxy_host:$proxy_port"
export https_proxy="http://$proxy_host:$proxy_port"
export no_proxy=$(jq -r '.no_proxy' ~/.http_proxy.json)
alias noproxy="unset http_proxy https_proxy no_proxy"
