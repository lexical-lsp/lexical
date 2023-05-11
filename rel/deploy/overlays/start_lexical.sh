#!/usr/bin/env bash

set_up_version_manager() {
    if [ -e $HOME/.asdf ]; then
        VERSION_MANAGER="asdf"
    elif [ -e $HOME/.rtx ]; then
        VERSION_MANAGER="rtx"
    else
        VERSION_MANAGER="none"
    fi
}

readlink_f () {
  cd "$(dirname "$1")" > /dev/null || exit 1
  filename="$(basename "$1")"
  if [ -h "$filename" ]; then
    readlink_f "$(readlink "$filename")"
  else
    echo "$(pwd -P)/$filename"
  fi
}

if [ -z "${ELS_INSTALL_PREFIX}" ]; then
  dir="$(dirname "$(readlink_f "$0")")"
else
  dir=${ELS_INSTALL_PREFIX}
fi

set_up_version_manager

case "$VERSION_MANAGER" in
    asdf)
        asdf env elixir "${dir}/bin/lexical" start
        ;;
    rtx)
        rtx env -s bash elixir "${dir}/bin/lexical" start
        ;;
    *)
        "${dir}/bin/lexical" start
        ;;
esac
