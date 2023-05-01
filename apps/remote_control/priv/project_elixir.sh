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

set_up_version_manager
cd $PROJECT_DIR

case "$VERSION_MANAGER" in
    asdf)
        asdf env elixir elixir
        ;;
    rtx)
        rtx env -s bash elixir elixir
        ;;
    *)
        elixir
        ;;
esac
