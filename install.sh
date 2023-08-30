#! /bin/bash

test -d ~/bin || mkdir -p ~/bin

for p in ansible bash dig git tmux vim wget; do
    stow $p
done
