#!/usr/bin/env bash
set -eo pipefail

asdf_dir=/version_managers/asdf_vm
mkdir -p $asdf_dir && cd $asdf_dir

git clone https://github.com/asdf-vm/asdf.git .

# shellcheck disable=SC1091
ASDF_DIR=$asdf_dir . asdf.sh

export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-termcap --without-wx"
asdf plugin add erlang https://github.com/asdf-vm/asdf-erlang.git
asdf install erlang "$ERLANG_VERSION"
asdf global erlang "$ERLANG_VERSION"

asdf plugin add elixir https://github.com/asdf-vm/asdf-elixir.git
asdf install elixir "$ELIXIR_VERSION"
asdf global elixir "$ELIXIR_VERSION"
