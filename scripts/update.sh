#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="/opt/Slideshow_Manager"
SERVICE_NAME="slideshow-manager"
ENV_FILE="/etc/slideshow-manager.env"
DEFAULT_REPO="${SLIDESHOW_MANAGER_DEFAULT_REPO:-https://github.com/joni123467/Slideshow_Manager}"
BRANCH="${SLIDESHOW_MANAGER_BRANCH:-main}"
SERVICE_USER="${SLIDESHOW_MANAGER_USER:-slideshowmgr}"
TMP_DIR=""
declare -a PERSISTENT_PATHS=("slideshow_manager/data/devices.json")

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

find_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v pacman >/dev/null 2>&1; then
    echo "pacman"
  elif command -v zypper >/dev/null 2>&1; then
    echo "zypper"
  else
    echo ""
  fi
}

install_system_dependencies() {
  local pkg_manager
  pkg_manager="$(find_pkg_manager)"
  local packages=(python3 python3-venv python3-pip curl tar git)
  case "${pkg_manager}" in
    apt)
      packages+=(python3-dev build-essential libpam0g-dev)
      log "Installiere Pakete über apt (${packages[*]})"
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
      ;;
    dnf|yum)
      packages+=(python3-devel gcc gcc-c++ make pam-devel)
      log "Installiere Pakete über ${pkg_manager} (${packages[*]})"
      "${pkg_manager}" install -y "${packages[@]}"
      ;;
    pacman)
      packages+=(base-devel pam)
      log "Installiere Pakete über pacman (${packages[*]})"
      pacman -Sy --noconfirm "${packages[@]}"
      ;;
    zypper)
      packages+=(python3-devel gcc gcc-c++ make pam-devel)
      log "Installiere Pakete über zypper (${packages[*]})"
      zypper --non-interactive install "${packages[@]}"
      ;;
    *)
      log "Keinen Paketmanager gefunden – stelle sicher, dass python3, pip, tar, curl, ein C-Compiler sowie PAM-Header installiert sind."
      ;;
  esac
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
  local data_backup=""

  if [[ ! -d "${INSTALL_ROOT}" ]]; then
    log "Es wurde keine Installation gefunden. Bitte install.sh ausführen."
    exit 1
  fi

  if [[ -d "${INSTALL_ROOT}/.venv" ]]; then
    venv_backup="$(mktemp -d)"
    mv "${INSTALL_ROOT}/.venv" "${venv_backup}/.venv"
  fi

  if [[ ${#PERSISTENT_PATHS[@]} -gt 0 ]]; then
    local backup_dir
    backup_dir="$(mktemp -d)"
    local preserved=0
    for rel_path in "${PERSISTENT_PATHS[@]}"; do
      if [[ -e "${INSTALL_ROOT}/${rel_path}" ]]; then
        preserved=1
        local backup_target="${backup_dir}/${rel_path}"
        mkdir -p "$(dirname "${backup_target}")"
        cp -a "${INSTALL_ROOT}/${rel_path}" "${backup_target}"
      fi
    done
    if [[ ${preserved} -eq 1 ]]; then
      data_backup="${backup_dir}"
    else
      rm -rf "${backup_dir}"
    fi
  fi

  find "${INSTALL_ROOT}" -mindepth 1 -maxdepth 1 ! -name ".venv" -exec rm -rf {} +
  cp -a "${source_dir}/." "${INSTALL_ROOT}/"

  if [[ -n "${venv_backup}" && -d "${venv_backup}/.venv" ]]; then
    mv "${venv_backup}/.venv" "${INSTALL_ROOT}/.venv"
    rm -rf "${venv_backup}"
  fi

  if [[ -n "${data_backup}" ]]; then
    for rel_path in "${PERSISTENT_PATHS[@]}"; do
      if [[ -e "${data_backup}/${rel_path}" ]]; then
        local target_dir="${INSTALL_ROOT}/$(dirname "${rel_path}")"
        mkdir -p "${target_dir}"
        cp -a "${data_backup}/${rel_path}" "${INSTALL_ROOT}/${rel_path}"
      fi
    done
    rm -rf "${data_backup}"
  fi

  if compgen -G "${INSTALL_ROOT}/scripts/*.sh" >/dev/null; then
    chmod +x "${INSTALL_ROOT}"/scripts/*.sh
  fi
}

install_python_dependencies() {
  local venv_dir="${INSTALL_ROOT}/.venv"
  if [[ ! -d "${venv_dir}" ]]; then
    log "Virtuelle Umgebung fehlt – erstelle neue Umgebung"
    python3 -m venv "${venv_dir}"
  fi

  local venv_python="${venv_dir}/bin/python"
  local venv_pip="${venv_dir}/bin/pip"

  "${venv_python}" -m pip install --upgrade pip setuptools wheel
  "${venv_pip}" install --no-cache-dir -r "${INSTALL_ROOT}/requirements.txt"
  if ! "${venv_python}" -c "import pam" >/dev/null 2>&1; then
    log "Fehlende Abhängigkeit python-pam trotz Installation erkannt"
    exit 1
  fi
}

set_permissions() {
  if id "${SERVICE_USER}" >/dev/null 2>&1; then
    chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_ROOT}"
  else
    log "Warnung: Dienstnutzer ${SERVICE_USER} existiert nicht – Überspringe chown."
  fi
}

restart_service() {
  systemctl daemon-reload
  systemctl restart "${SERVICE_NAME}.service"
}

main() {
  require_root
  install_system_dependencies
  local source_dir
  source_dir="$(fetch_sources)"
  sync_release "${source_dir}"
  install_python_dependencies
  set_permissions
  restart_service
  log "Update abgeschlossen."
}

main "$@"
