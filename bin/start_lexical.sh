#!/usr/bin/env bash

set_up_version_manager() {
    if command -v asdf > /dev/null && asdf which elixir > /dev/null 2>&1 ; then
        VERSION_MANAGER="asdf"
    elif command -v rtx > /dev/null &&  rtx which elixir > /dev/null 2>&1 ; then
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
        eval "$(rtx env -s bash)"
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

"${ELIXIR_COMMAND}" \
    -pa "${SCRIPT_DIR}/../consolidated" \
    -pa "${SCRIPT_DIR}/../config/" \
    -pa "${SCRIPT_DIR}/../priv/" \
    --cookie "lexical" \
    --no-halt \
    "${SCRIPT_DIR}/../priv/boot.exs"
