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
        rtx exec -- "$@" &
        ;;
    *)
        exec "$@" &
        ;;
esac
pid1=$!

# Silence warnings from here on
exec >/dev/null 2>&1

# Read from stdin in the background and
# kill running program when stdin closes
exec 0<&0 $(
  while read; do :; done
  kill -KILL $pid1
) &
pid2=$!

# Clean up
wait $pid1
ret=$?
kill -KILL $pid2
exit $ret
