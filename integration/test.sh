#!/usr/bin/env bash

# Disable warning for interpolations in single quotes:
# shellcheck disable=2016

set -eo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

# shellcheck disable=SC1091
. "$script_dir/test_utils.sh"

# Ensure the Docker image is up-to-date unless NO_BUILD=1
if [ -z "$NO_BUILD" ]; then
    "$script_dir"/build.sh
fi

start_lexical() {
    local command='LX_HALT_AFTER_BOOT=1 _build/dev/package/lexical/bin/start_lexical.sh; exit $?'

    if [[ $1 != "" ]]; then
        command="$1 && $command"
    fi

    docker run -i lx bash -c "$command" 2>&1
    return $?
}

run_test() {
    local setup=$1
    local expected=("${@:2}")

    # $FUNCNAME is a special array containing the stack of function calls,
    # with the current function at the head.
    local test="${FUNCNAME[1]}"
    log "$test... "

    local output
    output=$(start_lexical "$setup")
    local exit_code=$?

    if [[ -n $LX_DEBUG ]]; then
        log_info "\n$(prefix_lines "> " "$output")"
    fi

    assert_contains "$output" "${expected[@]}"
    local assert_exit_code=$?

    if [ $exit_code -ne 0 ]; then
        log_error "Fail (exit_code=$exit_code)"
        return 1
    elif [ $assert_exit_code -ne 0 ]; then
        return 1
    else
        log_success "Pass"
    fi
}

test_system_installation() {
    local expect=(
        "No activated version manager detected"
        "Could not activate a version manager"
    )

    run_test "" "${expect[@]}"
    return $?
}

test_asdf_already_activated() {
    local setup=(
        'mv "$(which elixir)" "$(which elixir).hidden" && '
        'ASDF_DIR=/version_managers/asdf_vm . /version_managers/asdf_vm/asdf.sh'
    )
    local expect=(
        "Detected Elixir through asdf"
    )

    run_test "${setup[*]}" "${expect[@]}"
    return $?
}

test_asdf_dir_found() {
    local setup=(
        'mv "$(which elixir)" "$(which elixir).hidden" && '
        'export ASDF_DIR=/version_managers/asdf_vm'
    )
    local expect=(
        "No activated version manager detected"
        "Found asdf. Activating"
        "Detected Elixir through asdf"
    )

    run_test "${setup[*]}" "${expect[@]}"
    return $?
}

test_asdf_used_when_activated_mise_missing_elixir() {
    local setup=(
        'mv "$(which elixir)" "$(which elixir).hidden" && '
        'eval "$(/version_managers/mise_vm/mise activate bash)" && '
        'mise uninstall "elixir@$ELIXIR_VERSION" && '
        'export ASDF_DIR=/version_managers/asdf_vm'
    )
    local expect=(
        "No activated version manager detected"
        "Found asdf. Activating"
        "Detected Elixir through asdf"
    )

    run_test "${setup[*]}" "${expect[@]}"
    return $?
}

test_mise_already_activated() {
    local setup=(
        'mv "$(which elixir)" "$(which elixir).hidden" && '
        'eval "$(/version_managers/mise_vm/mise activate bash)"'
    )
    local expect=(
        "Detected Elixir through mise"
    )

    run_test "${setup[*]}" "${expect[@]}"
    return $?
}

test_mise_binary_found_and_activated() {
    local setup=(
        'mv "$(which elixir)" "$(which elixir).hidden" && '
        'export PATH="/version_managers/mise_vm:$PATH"'
    )
    local expect=(
        "No activated version manager detected"
        "Found mise"
        "Detected Elixir through mise"
    )

    run_test "${setup[*]}" "${expect[@]}"
    return $?
}

test_mise_used_when_activated_asdf_missing_elixir() {
    local setup=(
        'mv "$(which elixir)" "$(which elixir).hidden" && '
        'ASDF_DIR=/version_managers/asdf_vm . /version_managers/asdf_vm/asdf.sh && '
        'asdf uninstall elixir "$ELIXIR_VERSION" && '
        'export PATH="/version_managers/mise_vm:$PATH"'
    )
    local expect=(
        "No activated version manager detected"
        "Found mise. Activating"
        "Detected Elixir through mise"
    )

    run_test "${setup[*]}" "${expect[@]}"
    return $?
}

run_tests_and_exit
