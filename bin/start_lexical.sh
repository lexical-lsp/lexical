#!/usr/bin/env bash

detect_version_manager() {
    if command -v asdf > /dev/null && asdf which elixir > /dev/null 2>&1 ; then
        echo "asdf"
    elif command -v rtx > /dev/null &&  rtx which elixir > /dev/null 2>&1 ; then
        echo "rtx"
    else
        echo "not_detected"
    fi
}

# Start the program in the background
case "$(detect_version_manager)" in
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
    --cookie "lexical" \
    --no-halt \
    "${SCRIPT_DIR}/../bin/boot.exs"
