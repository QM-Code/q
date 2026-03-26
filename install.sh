#!/bin/bash
set -euo pipefail

script_name=$(basename -- "$0")

usage() {
  printf 'Usage: sudo %s -u <q-user> [-n <name>] [-f]\n' "$script_name" >&2
  exit 1
}

if [[ $EUID -ne 0 || -z "${SUDO_USER:-}" || "${SUDO_USER}" == "root" ]]; then
  echo "Error: must run as sudo" >&2
  usage
fi

target_user=""
link_name="q-sandbox"
force_overwrite=false

while getopts ":u:n:f" opt; do
  case "$opt" in
    u)
      target_user=$OPTARG
      ;;
    n)
      link_name=$OPTARG
      ;;
    f)
      force_overwrite=true
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

if [[ -z "$target_user" ]]; then
  echo "Error: username must be specified" >&2
  usage
fi

if [[ -z "$link_name" || "$link_name" == */* ]]; then
  echo "Error: link name must be a plain file name" >&2
  usage
fi

if [[ $# -ne 0 ]]; then
  usage
fi

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
source_user=$SUDO_USER
source_home=$(getent passwd "$source_user" | cut -d: -f6)
source_group=$(id -gn "$source_user")
local_bindir="$source_home/.local/bin"
legacy_bindir="$source_home/bin"

set_shared_tree_permissions() {
  local path=$1

  find "$path" -type d -exec chmod 770 {} +
  find "$path" -type f -exec chmod 660 {} +
}

path_contains() {
  local needle=$1
  local path_list=$2
  local entry

  IFS=: read -r -a entries <<< "$path_list"
  for entry in "${entries[@]}"; do
    if [[ "$entry" == "$needle" ]]; then
      return 0
    fi
  done

  return 1
}

installation_conflict() {
  local name=$1
  local path=$2

  printf 'Error: installation file `%s` already exists:\n' "$name" >&2
  printf '    %s/%s\n' "$path" "$name" >&2
  printf "Use '-f' to overwrite or -n <name> to choose another name\n" >&2
  exit 1
}

display_path() {
  local path=$1

  if [[ "$path" == "$source_home" ]]; then
    printf '~'
  elif [[ "$path" == "$source_home/"* ]]; then
    printf '~%s' "${path#$source_home}"
  else
    printf '%s' "$path"
  fi
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
  printf 'Error: missing required repo files beside install.sh:\n' >&2
  for file in "${missing_repo_files[@]}"; do
    printf '  %s\n' "$file" >&2
  done
  exit 1
fi

user_path=$(sudo -u "$source_user" -H bash -lc 'printf "%s" "$PATH"' 2>/dev/null || true)
install_dir=""

if getent passwd "$target_user" >/dev/null; then
  echo "Error: user \"$target_user\" already exists." >&2
  exit 1
fi

if path_contains "$local_bindir" "$user_path"; then
  install_dir=$local_bindir
elif path_contains "$legacy_bindir" "$user_path"; then
  install_dir=$legacy_bindir
else
  install_dir=$source_home
fi

install_path="$install_dir/$link_name"

if [[ -L "$install_path" ]]; then
  if [[ -z "$(readlink -e "$install_path" || true)" ]]; then
    rm -f -- "$install_path"
  elif [[ "$force_overwrite" == true ]]; then
    rm -f -- "$install_path"
  else
    installation_conflict "$link_name" "$install_dir"
  fi
elif [[ -e "$install_path" ]]; then
  if [[ "$force_overwrite" == true ]]; then
    rm -rf -- "$install_path"
  else
    installation_conflict "$link_name" "$install_dir"
  fi
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

if [[ "$install_dir" != "$source_home" ]]; then
  install -d -m 755 -o "$source_user" -g "$source_group" "$install_dir"
fi

ln -s "$target_home/start-q.sh" "$install_path"
chown -h "$source_user:$source_group" "$install_path"

display_install_path=$(display_path "$install_path")

printf '\nCreated user "%s" with home directory %s.\n\n' "$target_user" "$target_home"
printf 'Created symlink:\n'
printf '    %s -> %s/start-q.sh\n' "$display_install_path" "$target_home"

if [[ "$install_dir" == "$source_home" ]]; then
  printf '\nNo user executable directory was found in PATH (e.g. ~/bin/)\n\n'
  printf 'The %s symlink has been placed in your home directory.\n\n' "$link_name"
  printf 'To start `q` in the sandboxed environment, run `~/%s`.\n\n' "$link_name"
else
  printf '\nTo start `q` in the sandboxed environment, run `%s`.\n\n' "$link_name"
fi
