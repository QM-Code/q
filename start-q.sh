#!/bin/bash
set -euo pipefail

sandbox_user=q

usage() {
  printf 'Usage: %s [-d <dir>]\n' "$(basename -- "$0")" >&2
  exit 1
}

target_home=$(getent passwd "$sandbox_user" | cut -d: -f6)

if [[ -z "$target_home" ]]; then
  echo "Error: user \"$sandbox_user\" not found." >&2
  exit 1
fi

start_dir=$target_home

while getopts ":d:" opt; do
  case "$opt" in
    d)
      if [[ ! -d "$OPTARG" ]]; then
        echo "Error: directory not found: $OPTARG" >&2
        exit 1
      fi
      start_dir=$(cd -- "$OPTARG" && pwd)
      ;;
    :)
      echo "Error: -$OPTARG requires a value." >&2
      usage
      ;;
    \?)
      echo "Error: invalid option -$OPTARG" >&2
      usage
      ;;
  esac
done

shift $((OPTIND - 1))

if [[ $# -ne 0 ]]; then
  usage
fi

if ! sudo -iu "$sandbox_user" -- q whoami >/dev/null 2>&1; then
  sudo -iu "$sandbox_user" -- q login
fi

exec sudo -u "$sandbox_user" HOME="$target_home" sh -c 'cd -- "$1" && exec q' sh "$start_dir"
