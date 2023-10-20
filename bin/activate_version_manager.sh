#!/usr/bin/env bash

# The purpose of these functions is to detect and activate the correct
# installed version manager in the current shell session. Currently, we
# try to detect asdf and rtx.
#
# The general approach involves the following steps:
#
#   1. Try to detect an already activated version manager that provides
#      Elixir. If one is present, there's nothing more to do.
#   2. Try to find and activate an asdf installation. If it provides
#      Elixir, we're all set.
#   3. Try to find and activate an rtx installation. If it provides
#      Elixir, we're all set.
#

activate_version_manager() {
    if (_detect_asdf || _detect_rtx); then
        return 0
    fi

    echo >&2 "No activated version manager detected. Searching for version manager..."

    _try_activating_asdf && _detect_asdf ||
        _try_activating_rtx && _detect_rtx
    return $?
}

_detect_asdf() {
    if command -v asdf >/dev/null && asdf which elixir >/dev/null 2>&1 && _ensure_which_elixir asdf; then
        echo >&2 "Detected Elixir through asdf: $(asdf which elixir)"
        return 0
    else
        return 1
    fi
}

_detect_rtx() {
    if command -v rtx >/dev/null && rtx which elixir >/dev/null 2>&1 && _ensure_which_elixir rtx; then
        echo >&2 "Detected Elixir through rtx: $(rtx which elixir)"
        return 0
    else
        return 1
    fi
}

_ensure_which_elixir() {
    [[ $(which elixir) == *"$1"* ]]
    return $?
}

_try_activating_asdf() {
    local asdf_dir="${ASDF_DIR:-"$HOME/.asdf"}"
    local asdf_vm="$asdf_dir/asdf.sh"

    if test -f "$asdf_vm"; then
        echo >&2 "Found asdf. Activating..."
        # shellcheck disable=SC1090
        . "$asdf_vm"
        return $?
    else
        return 1
    fi
}

_try_activating_rtx() {
    if which rtx >/dev/null; then
        echo >&2 "Found rtx. Activating..."
        eval "$(rtx activate bash)"
        eval "$(rtx env)"
        return $?
    else
        return 1
    fi
}

activate_version_manager
