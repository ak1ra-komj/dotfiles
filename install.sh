#! /bin/bash

stow_bash() {
    test -L ~/.bashrc || cp -v ~/.bashrc ~/.bashrc.$(date +%F_%s)
    test -L ~/.profile || cp -v ~/.profile ~/.profile.$(date +%F_%s)
    stow bash
}

stow_cmdline() {
    test -d ~/bin || mkdir ~/bin
    stow cmdline
}

stow_ansible() {
    test -d ~/.ansible || mkdir -p ~/.ansible
    stow ansible
}

main() {
    shlib="$(readlink -f ~/bin/shlib.sh)"
    test -f "$shlib" || return
    # shellcheck source=/dev/null
    . "$shlib"

    require_command stow

    stow_bash
    stow_cmdline
    # stow_ansible

    stow git
    stow vim

    # stow tmux
    # stow dig
    # stow wget
}

main "$@"
