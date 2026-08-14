#!/usr/bin/env bash

set -Eeuo pipefail

DSH_PACKAGE="@deepseek-ai/dsh@latest"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/dsh-launcher"
CURRENT_FILE="$INSTALL_BASE/current"

log() {
  printf '\n[dsh] %s\n' "$*"
}

die() {
  printf '\n[dsh] ERROR: %s\n' "$*" >&2
  exit 1
}

node_is_compatible() {
  command -v node >/dev/null 2>&1 || return 1

  local version major minor
  version="$(node --version 2>/dev/null)" || return 1
  version="${version#v}"
  IFS=. read -r major minor _ <<<"$version"

  [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] || return 1
  (( major >= 24 || (major == 22 && minor >= 19) ))
}

activate_local_node() {
  [[ -f "$CURRENT_FILE" ]] || return 1

  local node_dir
  IFS= read -r node_dir <"$CURRENT_FILE"
  [[ -x "$node_dir/bin/node" ]] || return 1
  export PATH="$node_dir/bin:$PATH"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    die "A SHA-256 tool is required (sha256sum or shasum)."
  fi
}

install_node() {
  command -v curl >/dev/null 2>&1 || die "curl is required to download Node.js."
  command -v tar >/dev/null 2>&1 || die "tar is required to unpack Node.js."

  local os arch platform base_url checksums file_name expected actual
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux) platform="linux" ;;
    Darwin) platform="darwin" ;;
    *) die "Unsupported operating system: $os" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) die "Unsupported CPU architecture: $arch" ;;
  esac

  base_url="https://nodejs.org/dist/latest-v24.x"
  log "Finding the latest Node.js 24 release for $platform-$arch..."
  checksums="$(curl --fail --silent --show-error --location "$base_url/SHASUMS256.txt")"
  file_name="$(printf '%s\n' "$checksums" | awk -v suffix="-$platform-$arch.tar.gz" '$2 ~ suffix "$" {print $2; exit}')"
  [[ -n "$file_name" ]] || die "Could not find a compatible Node.js download."
  expected="$(printf '%s\n' "$checksums" | awk -v file="$file_name" '$2 == file {print $1; exit}')"

  local temp_dir archive extracted_dir target_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temp_dir"' EXIT
  archive="$temp_dir/$file_name"

  log "Downloading $file_name..."
  curl --fail --show-error --location --output "$archive" "$base_url/$file_name"

  actual="$(sha256_file "$archive")"
  [[ "$actual" == "$expected" ]] || die "Node.js checksum verification failed."

  tar -xzf "$archive" -C "$temp_dir"
  extracted_dir="$temp_dir/${file_name%.tar.gz}"
  target_dir="$INSTALL_BASE/${file_name%.tar.gz}"
  mkdir -p -- "$INSTALL_BASE"

  if [[ ! -d "$target_dir" ]]; then
    mv -- "$extracted_dir" "$target_dir"
  fi

  printf '%s\n' "$target_dir" >"$CURRENT_FILE"
  export PATH="$target_dir/bin:$PATH"
  trap - EXIT
  rm -rf -- "$temp_dir"
}

main() {
  cd -- "$SCRIPT_DIR"

  if ! node_is_compatible; then
    activate_local_node || true
  fi

  if ! node_is_compatible; then
    log "Node.js is missing or incompatible. Installing a private copy..."
    install_node
  fi

  node_is_compatible || die "Node.js installation did not produce a compatible runtime."
  command -v npx >/dev/null 2>&1 || die "npx was not found next to Node.js."

  log "Using Node.js $(node --version)."
  log "Starting DeepSeek Harness at http://127.0.0.1:3080"
  log "Keep this window open. Press Ctrl+C to stop."
  exec npx --yes "$DSH_PACKAGE" web "$@"
}

main "$@"
