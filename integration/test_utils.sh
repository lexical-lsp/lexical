#!/usr/bin/env bash

reset="\033[0m"
faint="$reset\033[0;2m"
red="$reset\033[0;31m"
green="$reset\033[0;32m"
cyan="$reset\033[0;36m"

# Asserts that the given string contains all given substrings.
#
#   assert_contains STRING SUBSTRING*
#
# Example:
#
#   assert_contains "foobar" "foo" "bar"
#
assert_contains() {
    local output=$1
    local expectations=("${@:2}")
    local not_found=()

    for expected in "${expectations[@]}"; do
        if [[ $output != *"$expected"* ]]; then
            not_found+=("$expected")
        fi
    done

    if [ ${#not_found[@]} -ne 0 ]; then
        log_error "Assertion failed!"
        log_section "Expected" "${not_found[@]}"
        log_section "To be in" "$output"
        log "\n\n"
        return 1
    fi
}

# Runs every function that starts with "test_" in the current script,
# exits 1 if any tests exit non-zero
#
# Example:
#
#   test_foo() { ... }
#   test_bar() { ... }
#
#   # automatically runs test_foo and test_bar
#   run_tests_and_exit
#
run_tests_and_exit() {
    local tests
    tests=$(declare -F | awk '/test_/ {print $3}')

    local exit_code=0

    for test in $tests; do
        if ! "$test"; then
            exit_code=1
        fi
    done

    exit $exit_code
}

log() {
    echo -ne "$1"
}

log_error() {
    log "${red}$1${reset}\n"
}

log_success() {
    log "${green}$1${reset}\n"
}

log_info() {
    log "${faint}$1${reset}\n"
}

log_section() {
    local title="$1"
    local content=("${@:2}")

    log "\n  ${cyan}${title}:${reset}\n\n"

    for item in "${content[@]}"; do
        prefix_lines "    " "$item"
    done
}

prefix_lines() {
    local prefix_with=$1
    echo "$2" | sed "s/^/$prefix_with/" | cat
}
