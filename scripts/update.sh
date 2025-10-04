#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="/opt/Slideshow_Manager"
SERVICE_NAME="slideshow-manager"
ENV_FILE="/etc/slideshow-manager.env"
DEFAULT_REPO="${SLIDESHOW_MANAGER_DEFAULT_REPO:-https://github.com/joni123467/Slideshow_Manager}"
BRANCH="${SLIDESHOW_MANAGER_BRANCH:-main}"
TMP_DIR=""

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[update] Dieses Skript muss als root laufen." >&2
    exit 1
  fi
}

log() {
  echo "[update] $*" >&2
}

fetch_sources() {
  TMP_DIR="$(mktemp -d)"
  local target="${TMP_DIR}/source"
  if command -v git >/dev/null 2>&1; then
    log "Klone ${DEFAULT_REPO}@${BRANCH}"
    git clone --depth 1 --branch "${BRANCH}" "${DEFAULT_REPO}" "${target}"
  else
    log "Lade Archiv ohne Git (${DEFAULT_REPO}@${BRANCH})"
    local archive="${TMP_DIR}/source.tar.gz"
    curl -fsSL "${DEFAULT_REPO}/archive/refs/heads/${BRANCH}.tar.gz" -o "${archive}"
    tar -xzf "${archive}" -C "${TMP_DIR}"
    target="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  fi
  echo "${target}"
}

sync_release() {
  local source_dir="$1"
  rm -rf "${INSTALL_ROOT}/current"
  mkdir -p "${INSTALL_ROOT}/current"
  cp -a "${source_dir}/." "${INSTALL_ROOT}/current/"
  chmod +x "${INSTALL_ROOT}/current"/scripts/*.sh
}

install_dependencies() {
  local venv_dir="${INSTALL_ROOT}/.venv"
  if [[ ! -d "${venv_dir}" ]]; then
    log "Virtuelle Umgebung fehlt – führe zunächst install.sh aus."
    exit 1
  fi
  source "${venv_dir}/bin/activate"
  pip install --upgrade pip
  pip install --no-cache-dir -r "${INSTALL_ROOT}/current/requirements.txt"
}

restart_service() {
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service"
}

main() {
  require_root
  local source_dir
  source_dir="$(fetch_sources)"
  sync_release "${source_dir}"
  install_dependencies
  restart_service
  log "Update abgeschlossen."
}

main "$@"
