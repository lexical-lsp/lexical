#!/usr/bin/env bash

# Change the project dir
set_up_version_manager() {
    if [ -e $HOME/.asdf ]; then
        VERSION_MANAGER="asdf"
    elif [ -e $HOME/.rtx ]; then
        VERSION_MANAGER="rtx"
    else
        VERSION_MANAGER="none"
    fi
}

set_up_version_manager
cd $PROJECT_DIR

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

# Start the program in the background
# exec "$@" &
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
