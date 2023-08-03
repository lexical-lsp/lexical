#!/usr/bin/env bash

set_up_version_manager() {
    if [ -e $HOME/.asdf && ! asdf which erl ]; then
        VERSION_MANAGER="asdf"
    elif [ -e $HOME/.rtx && ! rtx which erl ]; then
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
