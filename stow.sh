#!/bin/bash

require_command() {
    for c in "$@"; do
        command -v "$c" >/dev/null || {
            echo >&2 "required command '$c' is not installed, aborting..."
            exit 1
        }
    done
}

stow_keep() {
    keep_dir="$1"
    test -d "${keep_dir}" || mkdir -p "${keep_dir}"
    touch "${keep_dir}/.stow_keep"
}

main() {
    require_command stow

    stow_keep "${HOME}/bin"
    test -L "${HOME}/.bashrc" || mv -v "${HOME}/.bashrc" "${HOME}/.bashrc.$(date +%F_%s)"
    test -L "${HOME}/.profile" || mv -v "${HOME}/.profile" "${HOME}/.profile.$(date +%F_%s)"
    stow bash
    stow cmdline

    # stow_keep ${XDG_CONFIG_HOME}/git
    stow_keep "${HOME}/.config/git"
    stow git

    stow vim

    stow_keep "${HOME}/.ansible/inventory"
    stow ansible

    # stow dig
    # stow wget
    # stow tmux
}

main "$@"
