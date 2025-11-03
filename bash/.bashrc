# shellcheck shell=bash disable=SC1090,SC1091
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
if [ -f /etc/os-release ]; then
	OS_RELEASE_ID="$(awk -F= '/^ID=/ {print $2}' /etc/os-release | tr '[:upper:]' '[:lower:]')"
fi

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
if [ "$OS_RELEASE_ID" = "freebsd" ]; then
	alias ls='ls -G --color=auto'
fi
if command -v dircolors >/dev/null; then
	if [ -r ~/.dircolors ]; then
		eval "$(dircolors -b ~/.dircolors)"
	else
		eval "$(dircolors -b)"
	fi
	alias ls='ls --color=auto'
	alias dir='dir --color=auto'
	alias vdir='vdir --color=auto'

	alias grep='grep --color=auto'
	alias fgrep='fgrep --color=auto'
	alias egrep='egrep --color=auto'
fi

# colored GCC warnings and errors
#GCC_COLORS='error=01;31:warning=01;35:note=01;36:caret=01;32:locus=01:quote=01'
#export GCC_COLORS

# some more ls aliases
alias ll='ls -l'
alias la='ls -lA'
alias lh='ls -lhA'
alias l='ls -CF'

# Alias definitions.
# You may want to put all your additions into a separate file like
# ~/.bash_aliases, instead of adding them here directly.
# See /usr/share/doc/bash-doc/examples in the bash-doc package.

if [ -f ~/.bash_aliases ]; then
	source ~/.bash_aliases
fi

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if [ "$OS_RELEASE_ID" = "freebsd" ]; then
	if [ -n "$PS1" ] && [ -f /usr/local/share/bash-completion/bash_completion.sh ]; then
		source /usr/local/share/bash-completion/bash_completion.sh
	fi
fi
if ! shopt -oq posix; then
	if [ -f /usr/share/bash-completion/bash_completion ]; then
		source /usr/share/bash-completion/bash_completion
	elif [ -f /etc/bash_completion ]; then
		source /etc/bash_completion
	fi
fi

# ###############################################################

test -d ~/.ssh/ssh-agent && {
	# /etc/ssh/sshd_config: 受限于 MaxAuthTries, 其默认值是 6
	# 当 ~/.ssh/ssh-agent 目录中超过 MaxAuthTries 个公钥时会报错, 因为其本质上是一个个去尝试
	readarray -t ssh_agent < <(find ~/.ssh/ssh-agent -type f ! -name '*.pub')
	if command -v keychain >/dev/null; then
		# apt install keychain
		# keychain: re-use ssh-agent and/or gpg-agent between logins
		eval "$(keychain --eval --agents ssh "${ssh_agent[@]}")"
	else
		# apt install openssh-client
		# ssh-agent: setup SSH_AUTH_SOCK & SSH_AGENT_PID env
		eval "$(ssh-agent)"
		ssh-add "${ssh_agent[@]}" 2>/dev/null
	fi
}

# ###############################################################

# custom http_proxy / https_proxy
# test -f ~/.http_proxy.json && source ~/.http_proxy.sh

# ###############################################################
# python3
# apt install pipx
# sudo activate-global-python-argcomplete

# pipx install poetry
# command -v poetry >/dev/null && source <(poetry completions bash)

# pipx install pdm
command -v pdm >/dev/null && source <(pdm completion bash)

# curl -LsSf https://astral.sh/uv/install.sh | sh
command -v uv >/dev/null && source <(uv generate-shell-completion bash)
command -v uvx >/dev/null && source <(uvx --generate-shell-completion bash)

# Load pyenv automatically by appending the following to
# ~/.bash_profile if it exists, otherwise ~/.profile (for login shells)
# and ~/.bashrc (for interactive shells):
# command -v pyenv >/dev/null && {
#     PYENV_ROOT="${HOME}/.pyenv"
#     export PYENV_ROOT
#     test -d "${PYENV_ROOT}/bin" && {
#         export PATH="${PYENV_ROOT}/bin:${PATH}"
#     }
#     eval "$(pyenv init - bash)"
# }

# ###############################################################

# golang
# sudo ln -s /usr/local/go/bin/* /usr/local/bin
command -v go >/dev/null && {
	GOPATH=~/.go
	PATH="${GOPATH}/bin:$PATH"
	export PATH GOPATH
	# GOPROXY=https://goproxy.cn,direct
	# export PATH GOPATH GOPROXY
}

# ###############################################################

# rustup, cargo, rustc
# rustup 用于安装 toolchain, cargo 是 package manager, rustc 是编译器
test -s ~/.cargo/env && source ~/.cargo/env

# https://github.com/jj-vcs/jj
# https://jj-vcs.github.io/jj/latest/install-and-setup/#bash
command -v jj >/dev/null && {
	# Standard
	# source <(jj util completion bash)
	# Dynamic
	# Generally, dynamic completions provide a much better completion experience.
	source <(COMPLETE=bash jj)
}

# ###############################################################

# nvm 用于管理不同版本的 nodejs
# git clone https://github.com/nvm-sh/nvm.git ~/.nvm && bash ~/.nvm/install.sh
# NVM_DIR=~/.nvm
# test -d "${NVM_DIR}" && {
#     export NVM_DIR
#     test -s "${NVM_DIR}/nvm.sh" && . "${NVM_DIR}/nvm.sh"
#     test -s "${NVM_DIR}/bash_completion" && . "${NVM_DIR}/bash_completion"
# }

# How to use `npm` package from APT repo?
# https://stackoverflow.com/a/59227497
# apt install nodejs npm
# npm config set prefix '~/.local'
# npm install -g @google/gemini-cli
# npm install -g @openai/codex
command -v codex >/dev/null && source <(codex completion bash)

# ###############################################################

# https://github.com/aws/aws-cli/tree/v2
command -v aws >/dev/null && {
	if command -v aws_completer >/dev/null; then
		complete -C aws_completer aws
	else
		# apt install awscli
		complete -C /usr/libexec/aws_completer aws
	fi
}

# ###############################################################

# gcloud, google-cloud-cli
# https://cloud.google.com/sdk/docs/install
# /etc/bash_completion.d/gcloud -> /usr/lib/google-cloud-sdk/completion.bash.inc

# ###############################################################

# tccli: https://github.com/TencentCloud/tencentcloud-cli
command -v tccli >/dev/null && {
	if command -v tccli_completer >/dev/null; then
		complete -C tccli_completer tccli
	else
		# pipx install tccli
		complete -C ~/.local/pipx/venvs/tccli/bin/tccli_completer tccli
	fi
}

# aliyun-cli
# https://github.com/aliyun/aliyun-cli

# ###############################################################

# terraform
# https://www.hashicorp.com/official-packaging-guide
command -v terraform >/dev/null && complete -C /usr/bin/terraform terraform

# asdf-vm/asdf
# go install github.com/asdf-vm/asdf/cmd/asdf@latest
# https://asdf-vm.com/guide/getting-started.html
# command -v asdf >/dev/null && {
#     export PATH="${ASDF_DATA_DIR:-${HOME}/.asdf}/shims:${PATH}"
#     source <(asdf completion bash)
# }

# gitlab-org/cli
# asdf plugin add glab; asdf install glab latest; asdf global glab latest
# https://gitlab.com/gitlab-org/cli/-/tree/main/docs/source/completion
# command -v glab >/dev/null && {
#     source <(glab completion -s bash)
# }

# ###############################################################
