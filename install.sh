#! /bin/bash

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

stow_bash() {
    test -L ~/.bashrc || mv -v ~/.bashrc ~/.bashrc.$(date +%F_%s)
    test -L ~/.profile || mv -v ~/.profile ~/.profile.$(date +%F_%s)
    stow bash
}

stow_cmdline() {
    test -d ~/bin || mkdir -p ~/bin
    stow cmdline
}

stow_ansible() {
    test -d ~/.ansible || mkdir -p ~/.ansible
    stow ansible
}

main() {
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
