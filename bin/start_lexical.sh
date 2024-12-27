#!/usr/bin/env bash
set -o pipefail

# find script file, even if we're a link pointing to it
script_file=${BASH_SOURCE[0]}
while [ -L "$script_file" ]; do
    script_dir=$(cd -P "$( dirname "$script_file" )" >/dev/null 2>&1 && pwd)
    script_file=$(readlink "$script_file")
    [[ $script_file != /* ]] && script_file=$script_dir/$script_file
done

# set script_dir to parent dir of script_file
script_dir=$(cd -P "$( dirname "$script_file" )" >/dev/null 2>&1 && pwd)

# shellcheck disable=SC1091
if ! . "$script_dir"/activate_version_manager.sh; then
    echo >&2 "Could not activate a version manager. Trying system installation."
fi

case $1 in
    iex)
        elixir_command=iex
        ;;
    *)
        elixir_command=elixir
        ;;
esac

$elixir_command \
    --cookie "lexical" \
    --no-halt \
    "$script_dir/boot.exs"
