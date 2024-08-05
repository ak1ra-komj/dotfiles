
# tmux
alias tm="tmux attach || tmux"

# using aria2 as external downloader
aria2c_args='--max-concurrent-downloads=8 --max-connection-per-server=16'
## pipx install youtube-dl
alias ytdl='youtube-dl --external-downloader=aria2c --external-downloader-args="'"$aria2c_args"'"'
## pipx install yt-dlp
alias ytdlp='yt-dlp --downloader=aria2c --downloader-args="aria2c:'"$aria2c_args"'"'

# git cli
alias g="git status"

# Kubenetes
command -v kubectl >/dev/null && {
    alias k="kubectl"
    complete -o default -F __start_kubectl k

    alias kns='kubectl config get-contexts && kubectl config set-context --current --namespace'
}

command -v helm >/dev/null && {
    alias hdd='test -f Chart.yaml && helm install --generate-name --debug --dry-run .'
}

test -f ~/bin/k8s-kubeconfig-selector.sh && alias kc="source ~/bin/k8s-kubeconfig-selector.sh"

