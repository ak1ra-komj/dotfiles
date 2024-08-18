# shellcheck shell=bash

alias fd="find . -wholename"
alias gr="grep -Er"

# git
alias g="git status"

# tmux
alias tm="tmux attach || tmux"

# use aria2 as external downloader
# -j, --max-concurrent-downloads=N Set maximum number of parallel downloads for every static (HTTP/FTP) URL, torrent and metalink. (default: 5)
# -x, --max-connection-per-server=NUM The maximum number of connections to one server for each download. (default: 1)
## pipx install youtube-dl
alias ytdl='youtube-dl --external-downloader=aria2c --external-downloader-args="-j 8 -x 4"'
## pipx install yt-dlp
alias ytdlp='yt-dlp --downloader=aria2c --downloader-args="aria2c:"-j 8 -x 4""'

# Kubenetes
command -v kubectl >/dev/null && {
    alias k="kubectl"
    complete -o default -F __start_kubectl k

    alias kns='kubectl config get-contexts && kubectl config set-context --current --namespace'
}

# Helm
command -v helm >/dev/null && {
    alias hdd='test -f Chart.yaml && helm install --generate-name --debug --dry-run .'
}

test -L ~/bin/k8s-kubeconfig-selector.sh && {
    alias kc="source ~/bin/k8s-kubeconfig-selector.sh"
}
