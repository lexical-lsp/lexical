#!/bin/sh

project_name=$1
node_name=$(epmd -names | grep manager-$project_name | awk '{print $2}')

iex --name "shell@127.0.0.1" \
    --remsh "${node_name}" \
    --dot-iex .iex.namespaced.exs \
    --cookie lexical
