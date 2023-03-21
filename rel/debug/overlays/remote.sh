#!/bin/sh
readlink_f () {
  cd "$(dirname "$1")" > /dev/null || exit 1
  filename="$(basename "$1")"
  if [ -h "$filename" ]; then
    readlink_f "$(readlink "$filename")"
  else
    echo "$(pwd -P)/$filename"
  fi
}

if [ -z "${ELS_INSTALL_PREFIX}" ]; then
  dir="$(dirname "$(readlink_f "$0")")"
else
  dir=${ELS_INSTALL_PREFIX}
fi

project_name=$1
node_name=$(epmd -names | grep manager-$project_name | awk '{print $2}')

export RELEASE_NODE="${node_name}@127.0.0.1"
exec "${dir}/bin/lexical_debug" remote
