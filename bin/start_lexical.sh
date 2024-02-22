#!/usr/bin/env bash
set -o pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

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
