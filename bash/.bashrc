# ~/.bashrc: executed by bash(1) for non-login shells.
# see /usr/share/doc/bash/examples/startup-files (in the package bash-doc)
# for examples

# If not running interactively, don't do anything
case $- in
*i*) ;;
*) return ;;
esac

# don't put duplicate lines or lines starting with space in the history.
# See bash(1) for more options
HISTCONTROL=ignoreboth

# append to the history file, don't overwrite it
shopt -s histappend

# write every history using PROMPT_COMMAND
PROMPT_COMMAND="${PROMPT_COMMAND:-:}; history -a"

# for setting history length see HISTSIZE and HISTFILESIZE in bash(1)
# ref: https://felixc.at/2013/09/how-to-avoid-losing-any-history-lines/
HISTSIZE=10000
HISTFILESIZE=400000000

# /etc/os-release
OS_RELEASE_ID="$(awk -F= '/^ID=/ {print $2}' /etc/os-release | tr 'A-Z' 'a-z')"

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
#shopt -s globstar

# make less more friendly for non-text input files, see lesspipe(1)
[ -x /usr/bin/lesspipe ] && eval "$(SHELL=/bin/sh lesspipe)"

# set variable identifying the chroot you work in (used in the prompt below)
if [ -z "${debian_chroot:-}" ] && [ -r /etc/debian_chroot ]; then
    debian_chroot=$(cat /etc/debian_chroot)
fi

# set a fancy prompt (non-color, unless we know we "want" color)
case "$TERM" in
xterm-color | *-256color) color_prompt=yes ;;
esac

# uncomment for a colored prompt, if the terminal has the capability; turned
# off by default to not distract the user: the focus in a terminal window
# should be on the output of commands, not on the prompt
#force_color_prompt=yes

if [ -n "$force_color_prompt" ]; then
    if [ -x /usr/bin/tput ] && tput setaf 1 >&/dev/null; then
        # We have color support; assume it's compliant with Ecma-48
        # (ISO/IEC-6429). (Lack of such support is extremely rare, and such
        # a case would tend to support setf rather than setaf.)
        color_prompt=yes
    else
        color_prompt=
    fi
fi

if [ "$color_prompt" = yes ]; then
    PS1='${debian_chroot:+($debian_chroot)}\[\033[01;32m\]\u@\h\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '
else
    PS1='${debian_chroot:+($debian_chroot)}\u@\h:\w\$ '
fi
unset color_prompt force_color_prompt

# If this is an xterm set the title to user@host:dir
case "$TERM" in
xterm* | rxvt*)
    PS1="\[\e]0;${debian_chroot:+($debian_chroot)}\u@\h: \w\a\]$PS1"
    ;;
*) ;;
esac

# enable color support of ls and also add handy aliases
if [ "$OS_RELEASE_ID" == "freebsd" ]; then
    alias ls='ls -G --color=auto'
fi
if [ -x /usr/bin/dircolors ]; then
    test -r $HOME/.dircolors && eval "$(dircolors -b $HOME/.dircolors)" || eval "$(dircolors -b)"
    alias ls='ls --color=auto'
    alias dir='dir --color=auto'
    alias vdir='vdir --color=auto'

    alias grep='grep --color=auto'
    alias fgrep='fgrep --color=auto'
    alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
export GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'

# some more ls aliases
alias ll='ls -l'
alias la='ls -A'
alias l='ls -CF'

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ "$OS_RELEASE_ID" == "freebsd" ]; then
    if [ -n "$PS1" -a -f /usr/local/share/bash-completion/bash_completion.sh ]; then
        source /usr/local/share/bash-completion/bash_completion.sh
    fi
fi
if ! shopt -oq posix; then
    if [ -f /usr/share/bash-completion/bash_completion ]; then
        . /usr/share/bash-completion/bash_completion
    elif [ -f /etc/bash_completion ]; then
        . /etc/bash_completion
    fi
fi

# Alias definitions.
# You may want to put all your additions into a separate file like
# $HOME/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.
test -f $HOME/.bash_aliases && \. $HOME/.bash_aliases

# Custom settings
test -f $HOME/.bash_functions && \. $HOME/.bash_functions

# http_proxy / https_proxy
# 在文件 $HOME/.http_proxy 中填入 http_proxy 相关的信息
if [ -f $HOME/.http_proxy ]; then
    proxy_host=$(awk -F= '/^host=/ {print $2}' $HOME/.http_proxy | tr 'A-Z' 'a-z')
    if [ "$proxy_host" == "wsl" ]; then
        # proxy_host="$(awk '/^nameserver/ {print $2}' /etc/resolv.conf | head -n1)"
        proxy_host="$(ip route show default | awk '{print $3}')"
    fi

    proxy_port=$(awk -F= '/^port=/ {print $2}' $HOME/.http_proxy | tr 'A-Z' 'a-z')
    export http_proxy="http://$proxy_host:$proxy_port"
    export https_proxy="http://$proxy_host:$proxy_port"

    no_proxy=$(awk -F= '/^no_proxy=/ {print $2}' $HOME/.http_proxy | tr 'A-Z' 'a-z')
    test -n "$no_proxy" || \
        no_proxy="localhost,127.0.0.0/8,10.0.0.0/8,172.16.0.0/12,192.168.0.0/16"
    export no_proxy
    alias noproxy="unset http_proxy https_proxy no_proxy"
fi

# python3 -m pip install --user
export PATH=$HOME/bin:$HOME/.local/bin:$PATH

# golang
GOPATH=$HOME/.go
if [ -d "$GOPATH" ]; then
    export GOPATH
    export PATH=$GOPATH/bin:/usr/local/go/bin:$PATH
    export GOPROXY=https://goproxy.cn,direct
fi

# nvm
# curl https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh > nvm.sh
NVM_DIR="$HOME/.nvm"
if [ -d "$NVM_DIR" ]; then
    export NVM_DIR
    test -s "$NVM_DIR/nvm.sh" && \. "$NVM_DIR/nvm.sh"
    test -s "$NVM_DIR/bash_completion" && \. "$NVM_DIR/bash_completion"
fi

# rust
test -s "$HOME/.cargo/env" && \. "$HOME/.cargo/env"

# aws-cli
hash aws 2>&1 >/dev/null && complete -C aws_completer aws
