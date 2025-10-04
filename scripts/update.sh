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
  local venv_backup=""

  if [[ ! -d "${INSTALL_ROOT}" ]]; then
    log "Es wurde keine Installation gefunden. Bitte install.sh ausführen."
    exit 1
  fi

  if [[ -d "${INSTALL_ROOT}/.venv" ]]; then
    venv_backup="$(mktemp -d)"
    mv "${INSTALL_ROOT}/.venv" "${venv_backup}/.venv"
  fi

  find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 ! -name ".venv" -exec rm -rf {} +
  cp -a "${source_dir}/." "${INSTALL_ROOT}/"

  if [[ -n "${venv_backup}" && -d "${venv_backup}/.venv" ]]; then
    mv "${venv_backup}/.venv" "${INSTALL_ROOT}/.venv"
    rm -rf "${venv_backup}"
  fi

  if compgen -G "${INSTALL_ROOT}/scripts/*.sh" >/dev/null; then
    chmod +x "${INSTALL_ROOT}"/scripts/*.sh
  fi
}

install_dependencies() {
  local venv_dir="${INSTALL_ROOT}/.venv"
  if [[ ! -d "${venv_dir}" ]]; then
    log "Virtuelle Umgebung fehlt – erstelle neue Umgebung"
    python3 -m venv "${venv_dir}"
  fi
  source "${venv_dir}/bin/activate"
  pip install --upgrade pip setuptools wheel
  pip install --no-cache-dir -r "${INSTALL_ROOT}/requirements.txt"
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
