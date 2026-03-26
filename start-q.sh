#!/bin/bash
set -euo pipefail

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

if ! sudo -iu q -- q whoami >/dev/null 2>&1; then
  sudo -iu q -- q login
fi

exec sudo -u q HOME=/home/q sh -c 'cd -- "$1" && exec q' sh "$script_dir"
