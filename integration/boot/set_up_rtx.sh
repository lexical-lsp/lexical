#!/usr/bin/env bash
set -eo pipefail

rtx_dir=/version_managers/rtx_vm
mkdir -p $rtx_dir && cd $rtx_dir

# Download the rtx binary for the correct architecture
arch=$(uname -m)
architecture=""

case $arch in
    "x86_64")
        architecture="x64"
        ;;
    "aarch64")
        architecture="arm64"
        ;;
    *)
        echo "Unsupported architecture: $arch"
        exit 1
        ;;
esac

curl "https://rtx.pub/rtx-latest-linux-$architecture" >"$(pwd)/rtx"
chmod +x ./rtx

eval "$(./rtx activate bash)"

export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-termcap --without-wx"
./rtx plugins install erlang
./rtx use --global "erlang@$ERLANG_VERSION"

./rtx plugins install elixir
./rtx use --global "elixir@$ELIXIR_VERSION"
