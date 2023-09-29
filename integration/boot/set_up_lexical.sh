#!/usr/bin/env bash
set -eo pipefail

cd /lexical

mix local.hex --force
mix deps.get
mix package
