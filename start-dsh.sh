#!/usr/bin/env bash

set -Eeuo pipefail

DSH_PACKAGE="@deepseek-ai/dsh@latest"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_BASE="${XDG_DATA_HOME:-$HOME/.local/share}/dsh-launcher"
CURRENT_FILE="$INSTALL_BASE/current"

DSH_LANGUAGE="en"
case "${LC_ALL:-${LC_MESSAGES:-${LANG:-}}}" in
  zh*|ZH*) DSH_LANGUAGE="zh" ;;
esac

if [[ "$DSH_LANGUAGE" == "zh" ]]; then
  MSG_ERROR_LABEL="错误："
  MSG_SHA256_REQUIRED="需要 SHA-256 工具（sha256sum 或 shasum）。"
  MSG_CURL_REQUIRED="下载 Node.js 需要 curl。"
  MSG_TAR_REQUIRED="解压 Node.js 需要 tar。"
  MSG_UNSUPPORTED_OS="不支持的操作系统：%s"
  MSG_UNSUPPORTED_ARCH="不支持的 CPU 架构：%s"
  MSG_FINDING_NODE="正在查找适用于 %s 的最新 Node.js 24 版本..."
  MSG_NODE_DOWNLOAD_NOT_FOUND="找不到兼容的 Node.js 下载包。"
  MSG_DOWNLOADING="正在下载 %s..."
  MSG_CHECKSUM_FAILED="Node.js 校验和验证失败。"
  MSG_NODE_MISSING="未检测到 Node.js 或版本不兼容，正在安装独立副本..."
  MSG_NODE_INSTALL_FAILED="Node.js 安装完成后仍未获得兼容的运行时。"
  MSG_NPX_NOT_FOUND="在 Node.js 目录中找不到 npx。"
  MSG_USING_NODE="正在使用 Node.js %s。"
  MSG_PREPARING="正在准备 DeepSeek Harness。首次启动可能需要几分钟。"
  MSG_READY="当出现以下内容时，DSH 已就绪：dsh web: http://127.0.0.1:3080"
  MSG_KEEP_OPEN="使用期间请保持此窗口打开。按 Ctrl+C 可停止。"
else
  MSG_ERROR_LABEL="ERROR: "
  MSG_SHA256_REQUIRED="A SHA-256 tool is required (sha256sum or shasum)."
  MSG_CURL_REQUIRED="curl is required to download Node.js."
  MSG_TAR_REQUIRED="tar is required to unpack Node.js."
  MSG_UNSUPPORTED_OS="Unsupported operating system: %s"
  MSG_UNSUPPORTED_ARCH="Unsupported CPU architecture: %s"
  MSG_FINDING_NODE="Finding the latest Node.js 24 release for %s..."
  MSG_NODE_DOWNLOAD_NOT_FOUND="Could not find a compatible Node.js download."
  MSG_DOWNLOADING="Downloading %s..."
  MSG_CHECKSUM_FAILED="Node.js checksum verification failed."
  MSG_NODE_MISSING="Node.js is missing or incompatible. Installing a private copy..."
  MSG_NODE_INSTALL_FAILED="Node.js installation did not produce a compatible runtime."
  MSG_NPX_NOT_FOUND="npx was not found next to Node.js."
  MSG_USING_NODE="Using Node.js %s."
  MSG_PREPARING="Preparing DeepSeek Harness. The first launch may take several minutes."
  MSG_READY="DSH is ready when it prints: dsh web: http://127.0.0.1:3080"
  MSG_KEEP_OPEN="Keep this window open. Press Ctrl+C to stop."
fi

format_message() {
  local format="$1"
  shift
  printf "$format" "$@"
}

log() {
  printf '\n[dsh] %s\n' "$*"
}

die() {
  printf '\n[dsh] %s%s\n' "$MSG_ERROR_LABEL" "$*" >&2
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
    die "$MSG_SHA256_REQUIRED"
  fi
}

install_node() {
  command -v curl >/dev/null 2>&1 || die "$MSG_CURL_REQUIRED"
  command -v tar >/dev/null 2>&1 || die "$MSG_TAR_REQUIRED"

  local os arch platform base_url checksums file_name expected actual
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux) platform="linux" ;;
    Darwin) platform="darwin" ;;
    *) die "$(format_message "$MSG_UNSUPPORTED_OS" "$os")" ;;
  esac

  case "$arch" in
    x86_64|amd64) arch="x64" ;;
    arm64|aarch64) arch="arm64" ;;
    *) die "$(format_message "$MSG_UNSUPPORTED_ARCH" "$arch")" ;;
  esac

  base_url="https://nodejs.org/dist/latest-v24.x"
  log "$(format_message "$MSG_FINDING_NODE" "$platform-$arch")"
  checksums="$(curl --fail --silent --show-error --location "$base_url/SHASUMS256.txt")"
  file_name="$(printf '%s\n' "$checksums" | awk -v suffix="-$platform-$arch.tar.gz" '$2 ~ suffix "$" {print $2; exit}')"
  [[ -n "$file_name" ]] || die "$MSG_NODE_DOWNLOAD_NOT_FOUND"
  expected="$(printf '%s\n' "$checksums" | awk -v file="$file_name" '$2 == file {print $1; exit}')"

  local temp_dir archive extracted_dir target_dir
  temp_dir="$(mktemp -d)"
  trap 'rm -rf -- "$temp_dir"' EXIT
  archive="$temp_dir/$file_name"

  log "$(format_message "$MSG_DOWNLOADING" "$file_name")"
  curl --fail --show-error --location --output "$archive" "$base_url/$file_name"

  actual="$(sha256_file "$archive")"
  [[ "$actual" == "$expected" ]] || die "$MSG_CHECKSUM_FAILED"

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
    log "$MSG_NODE_MISSING"
    install_node
  fi

  node_is_compatible || die "$MSG_NODE_INSTALL_FAILED"
  command -v npx >/dev/null 2>&1 || die "$MSG_NPX_NOT_FOUND"

  log "$(format_message "$MSG_USING_NODE" "$(node --version)")"
  log "$MSG_PREPARING"
  log "$MSG_READY"
  log "$MSG_KEEP_OPEN"
  exec npx --yes "$DSH_PACKAGE" web "$@"
}

main "$@"
