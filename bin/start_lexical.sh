#!/usr/bin/env bash

set_up_version_manager() {
    if [ -e $HOME/.asdf ] &&  asdf which elixir > /dev/null -eq 0; then
        VERSION_MANAGER="asdf"
    elif [ -e $HOME/.rtx ] && rtx which elixir > /dev/null -eq 0; then
        VERSION_MANAGER="rtx"
    else
        VERSION_MANAGER="none"
    fi
}


set_up_version_manager

# Start the program in the background
case "$VERSION_MANAGER" in
    asdf)
        asdf env erl exec "$@" &
        ;;
    rtx)
        rtx env -s bash erl exec "$@" &
        ;;
    *)
        ;;
esac

case $1 in
    iex)
        ELIXIR_COMMAND=iex
        ;;
    *)
        ELIXIR_COMMAND=elixir
        ;;
esac

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

export ERL_LIBS="${SCRIPT_DIR}/../lib"
"${ELIXIR_COMMAND}" -pa "${SCRIPT_DIR}/../consolidated" \
                    -pa "${SCRIPT_DIR}/../config/" \
                    -pa "${SCRIPT_DIR}/../priv/" \
                    --eval "LXical.Server.Boot.start" \
                    --no-halt
