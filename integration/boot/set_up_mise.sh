#!/usr/bin/env bash
set -eo pipefail

mise_dir=/version_managers/mise_vm
mkdir -p $mise_dir && cd $mise_dir

# Download the mise binary for the correct architecture
arch=$(uname -m)
architecture=""

case $arch in
    "x86_64")
        architecture="linux-x64"
        ;;
    "aarch64")
        architecture="linux-arm64"
        ;;
    "arm64")
        architecture="macos-arm64"
        ;;
    *)
        echo "Unsupported architecture: $arch"
        exit 1
        ;;
esac

curl -L "https://github.com/jdx/mise/releases/download/v2025.2.6/mise-v2025.2.6-${architecture}.tar.gz" -o mise.tar.gz
tar xfvz mise.tar.gz
mv mise mise_download
mv mise_download/bin/mise .
chmod +x ./mise

eval "$(./mise activate bash)"
export MISE_VERBOSE=1
export KERL_CONFIGURE_OPTIONS="--disable-debug --without-javac --without-termcap --without-wx"

./mise use --global "erlang@$ERLANG_VERSION"
./mise use --global "elixir@$ELIXIR_VERSION"
