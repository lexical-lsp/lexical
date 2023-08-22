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
        eval "$(rtx env -s bash erl)"
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

PATH_APPEND_ARGS=$(for f in $(find ${SCRIPT_DIR}/../lib -name '*.ez')
do
    lib=$(basename $f | sed -e 's/.ez//g')
    echo "-pa $f/$lib/ebin"
done)

"${ELIXIR_COMMAND}" $(echo $PATH_APPEND_ARGS) \
                    -pa "${SCRIPT_DIR}/../consolidated" \
                    -pa "${SCRIPT_DIR}/../config/" \
                    -pa "${SCRIPT_DIR}/../priv/" \
                    --eval "LXical.Server.Boot.start" \
                    --cookie "lexical" \
                    --no-halt
