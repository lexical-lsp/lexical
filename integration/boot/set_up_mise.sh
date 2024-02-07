#!/usr/bin/env bash
set -eo pipefail

mise_dir=/version_managers/mise_vm
mkdir -p $mise_dir && cd $mise_dir

# Download the mise binary for the correct architecture
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

curl "https://mise.jdx.dev/mise-latest-linux-$architecture" >"$(pwd)/mise"
chmod +x ./mise

eval "$(./mise activate bash)"

export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-termcap --without-wx"
./mise plugin install -y erlang
./mise use --global "erlang@$ERLANG_VERSION"

./mise plugins install -y elixir
./mise use --global "elixir@$ELIXIR_VERSION"
