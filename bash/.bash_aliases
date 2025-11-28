# shellcheck shell=bash

alias fd="find . -wholename"

# apt install ripgrep
# https://github.com/BurntSushi/ripgrep
# alias rg="grep -Er"

# git
alias g="git status"
# PRETTY FORMATS:
# colors: %Cred, %Cgreen, %Cblue, %Creset
# %h, abbreviated commit hash
# %d, ref names, like the --decorate option of git-log(1)
# %s, subject
# %cr, committer date, relative
# %ci, committer date, ISO 8601-like format; %cI, committer date, strict ISO 8601 format
# %an, author name; %aN, author name (respecting .mailmap, see git-shortlog(1) or git-blame(1))
alias gl="git log --abbrev-commit --graph --pretty=tformat:'%Cred%h%Creset -%C(auto)%d%Creset %s %Cgreen(%ci) %Cblue%an <%ae>%Creset'"

# wget
# -e command, --execute=command, Execute command as if it were a part of .wgetrc.
#    robots, Setting this to off makes Wget not download /robots.txt.
# -i file, --input-file=file, Read URLs from a local or external file.
# -B, --base=URL, Resolves relative links using URL as the point of reference
# -c, --continue, Continue getting a partially-downloaded file.
# -r, --recursive, Turn on recursive retrieving. The default maximum depth is 5 (-l depth, --level=depth).
# -k, --convert-links, After the download is complete, convert the links in the document to make them suitable for local viewing.
# -x, --force-directories, The opposite of -nd, create a hierarchy of directories, even if one would not have been created otherwise.
# -np, --no-parent, Do not ever ascend to the parent directory when retrieving recursively
# -nH, --no-host-directories, Disable generation of host-prefixed directories.
# -N, --timestamping, Turn on time-stamping.
# -m, --mirror, Turn on options suitable for mirroring, equivalent to "-r -N -l inf --no-remove-listing"
alias wget-crawler="wget --continue --recursive --convert-links --force-directories --no-parent --execute=robots=off"

## curl
# alias curl-header="curl -s --dump-header % -o /dev/null"

# tmux
alias tm="tmux attach || tmux"

# use aria2 as external downloader
# -j, --max-concurrent-downloads=N Set maximum number of parallel downloads for every static (HTTP/FTP) URL, torrent and metalink. (default: 5)
# -x, --max-connection-per-server=NUM The maximum number of connections to one server for each download. (default: 1)
## pipx install youtube-dl
alias ytdl='youtube-dl --external-downloader=aria2c --external-downloader-args="--max-concurrent-downloads=8 --max-connection-per-server=4"'
## pipx install yt-dlp
alias ytdlp='yt-dlp --downloader=aria2c --downloader-args="aria2c:--max-concurrent-downloads=8 --max-connection-per-server=4" --embed-subs --sub-langs="all,-live_chat"'

# apt install bat
# https://github.com/sharkdp/bat
command -v batcat >/dev/null && {
    alias less='batcat --style=plain'
    alias more='batcat --style=plain'
    alias cat='batcat --style=plain --paging=never'
}

# shfmt
# https://github.com/mvdan/sh
command -v shfmt >/dev/null && {
    alias shfmt="shfmt -w -i=4 -ci"
}

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

test -L ~/bin/kube-config-selector.sh && {
    alias kc="source ~/bin/kube-config-selector.sh"
}
