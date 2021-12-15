
# http_proxy
if [ -f ~/.bashrc.d/http_proxy ]; then
    if [ -n "$WSL_DISTRO_NAME" ]; then
        # wsl_host="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | head -n1)"
        wsl_host="$(ip route show default | awk '{print $3}')"
        export http_proxy="http://$wsl_host:1082"
        export https_proxy="$http_proxy"
    else
        export http_proxy="http://127.0.0.1:1082"
        export https_proxy="$http_proxy"
    fi
    export no_proxy="localhost,127.0.0.1,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    alias noproxy="unset http_proxy https_proxy no_proxy"
fi

