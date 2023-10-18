#!/usr/bin/env bash
set -eo pipefail

docker build -t lx -f integration/Dockerfile .
