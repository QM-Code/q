#!/bin/bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
Usage: sudo ./install-q.sh -u <username>
EOF
  exit 1
}

if [[ $# -eq 0 ]]; then
  usage
fi

target_user=""

while getopts ":u:" opt; do
  case "$opt" in
    u)
      target_user=$OPTARG
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

if [[ $# -ne 0 || -z "$target_user" ]]; then
  usage
fi

if [[ $EUID -ne 0 || -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
  echo "Error: run this script with sudo from the user account whose AWS and Amazon Q files should be copied." >&2
  exit 1
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_user=$SUDO_USER
source_home=$(getent passwd "$source_user" | cut -d: -f6)
source_group=$(id -gn "$source_user")

set_shared_tree_permissions() {
  local path=$1

  find "$path" -type d -exec chmod 770 {} +
  find "$path" -type f -exec chmod 660 {} +
}

required_repo_files=(
  "start-q.sh"
  "README.md"
  "AmazonQ.md"
)

missing_repo_files=()
for file in "${required_repo_files[@]}"; do
  if [[ ! -f "$script_dir/$file" ]]; then
    missing_repo_files+=("$file")
  fi
done

if (( ${#missing_repo_files[@]} > 0 )); then
  printf 'Error: missing required repo files beside install-q.sh:\n' >&2
  for file in "${missing_repo_files[@]}"; do
    printf '  %s\n' "$file" >&2
  done
  exit 1
fi

if getent passwd "$target_user" >/dev/null; then
  echo "Error: user \"$target_user\" already exists." >&2
  exit 1
fi

has_config=false
has_credentials=false
has_sso_cache=false

if [[ -f "$source_home/.aws/config" ]]; then
  has_config=true
fi

if [[ -f "$source_home/.aws/credentials" ]]; then
  has_credentials=true
fi

if [[ -d "$source_home/.aws/sso/cache" ]]; then
  has_sso_cache=true
fi

if [[ "$has_config" != true || ( "$has_credentials" != true && "$has_sso_cache" != true ) ]]; then
  printf 'Error: your AWS setup is incomplete.\n' >&2

  if [[ "$has_config" != true ]]; then
    printf '  Missing: %s/.aws/config\n' "$source_home" >&2
  fi

  if [[ "$has_credentials" != true && "$has_sso_cache" != true ]]; then
    printf '  Missing: either %s/.aws/credentials or %s/.aws/sso/cache\n' "$source_home" "$source_home" >&2
  fi

  printf '\nYou need %s/.aws/config plus either static credentials or an AWS SSO cache.\n' "$source_home" >&2
  printf 'Set that up for user "%s", then rerun this installer.\n' "$source_user" >&2
  exit 1
fi

useradd -m -g "$source_group" -s /bin/bash "$target_user"

target_home=$(getent passwd "$target_user" | cut -d: -f6)

install -d -m 770 -o "$target_user" -g "$source_group" "$target_home/.aws"
install -m 660 -o "$target_user" -g "$source_group" "$source_home/.aws/config" "$target_home/.aws/config"

if [[ "$has_credentials" == true ]]; then
  install -m 660 -o "$target_user" -g "$source_group" "$source_home/.aws/credentials" "$target_home/.aws/credentials"
fi

if [[ "$has_sso_cache" == true ]]; then
  install -d -m 770 -o "$target_user" -g "$source_group" "$target_home/.aws/sso"
  cp -a "$source_home/.aws/sso/cache" "$target_home/.aws/sso/"
  chown -R "$target_user:$source_group" "$target_home/.aws"
fi

if [[ -d "$source_home/.local/share/amazon-q" ]]; then
  install -d -m 770 -o "$target_user" -g "$source_group" "$target_home/.local/share"
  cp -a "$source_home/.local/share/amazon-q" "$target_home/.local/share/"
  chown -R "$target_user:$source_group" "$target_home/.local"
fi

tmp_start=$(mktemp)
trap 'rm -f "$tmp_start"' EXIT

awk -v user="$target_user" '
  {
    gsub("^sandbox_user=q$", "sandbox_user=" user)
    print
  }
' "$script_dir/start-q.sh" > "$tmp_start"

install -m 770 -o "$target_user" -g "$source_group" "$tmp_start" "$target_home/start-q.sh"
install -m 660 -o "$target_user" -g "$source_group" "$script_dir/AmazonQ.md" "$target_home/AmazonQ.md"
install -m 660 -o "$target_user" -g "$source_group" "$script_dir/README.md" "$target_home/README.md"

chown -R "$target_user:$source_group" "$target_home"
set_shared_tree_permissions "$target_home"
chmod 770 "$target_home"
chmod 770 "$target_home/start-q.sh"

printf '\nCreated user "%s" with home directory %s.\n\n' "$target_user" "$target_home"
printf 'To start `q` in the sandboxed environment, run %s/start-q.sh\n\n' "$target_home"
