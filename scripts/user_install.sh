#/bin/bash

sudo apt install -y zsh neovim tmux htop stow
cargo install exa starship

git clone --branch server-friendly https://github.com/lightclient/dotfiles

cd $HOME/dotfiles

stow editor
stow shell

chsh -s /usr/bin/zsh
sudo reboot
