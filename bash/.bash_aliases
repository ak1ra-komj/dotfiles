
# tmux
alias tm="tmux attach || tmux"

# using aria2 as external downloader
aria2c_args="--max-concurrent-downloads=8 --max-connection-per-server=16"
## pipx install youtube-dl
alias ytdl="youtube-dl --external-downloader=aria2c --external-downloader-args='$aria2c_args'"
## pipx install yt-dlp
alias ytdlp="yt-dlp --downloader=aria2c --downloader-args=aria2c:'$aria2c_args'"

# git cli
alias g="git status"
alias ga="git add"
alias gc="git commit -m"
alias gf="git fetch"
alias gp="git push"

# Kubenetes
alias k="kubectl"
complete -o default -F __start_kubectl k
test -f ~/bin/k8s-kubeconfig-selector.sh && alias kc="source ~/bin/k8s-kubeconfig-selector.sh"
