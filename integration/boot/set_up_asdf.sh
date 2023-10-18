#!/usr/bin/env bash
set -eo pipefail

asdf_dir=/version_managers/asdf_vm
mkdir -p $asdf_dir && cd $asdf_dir

git clone https://github.com/asdf-vm/asdf.git .

# shellcheck disable=SC1091
ASDF_DIR=$asdf_dir . asdf.sh

asdf update

export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-termcap --without-wx"
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf install erlang latest
asdf global erlang latest

asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
asdf install elixir latest
asdf global elixir latest
