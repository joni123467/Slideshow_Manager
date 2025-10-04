#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="/opt/Slideshow_Manager"
SERVICE_NAME="slideshow-manager"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
ENV_FILE="/etc/slideshow-manager.env"
DEFAULT_REPO="${SLIDESHOW_MANAGER_DEFAULT_REPO:-https://github.com/joni123467/Slideshow_Manager}"
BRANCH="${SLIDESHOW_MANAGER_BRANCH:-main}"
SERVICE_USER="${SLIDESHOW_MANAGER_USER:-slideshowmgr}"
TMP_DIR=""

cleanup() {
  if [[ -n "${TMP_DIR}" && -d "${TMP_DIR}" ]]; then
    rm -rf "${TMP_DIR}"
  fi
}
trap cleanup EXIT

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[install] Dieses Skript muss mit Root-Rechten ausgeführt werden." >&2
    exit 1
  fi
}

log() {
  echo "[install] $*" >&2
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

install_dependencies() {
  local pkg_manager
  pkg_manager="$(find_pkg_manager)"
  local packages=(python3 python3-venv python3-pip curl tar)
  case "${pkg_manager}" in
    apt)
      packages+=(git)
      log "Installiere Pakete über apt (${packages[*]})"
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y "${packages[@]}"
      ;;
    dnf|yum)
      packages+=(git)
      log "Installiere Pakete über ${pkg_manager} (${packages[*]})"
      "${pkg_manager}" install -y "${packages[@]}"
      ;;
    pacman)
      packages+=(git base-devel)
      log "Installiere Pakete über pacman (${packages[*]})"
      pacman -Sy --noconfirm "${packages[@]}"
      ;;
    zypper)
      packages+=(git)
      log "Installiere Pakete über zypper (${packages[*]})"
      zypper --non-interactive install "${packages[@]}"
      ;;
    *)
      log "Keinen Paketmanager gefunden – stelle sicher, dass python3, pip, tar und curl vorhanden sind."
      ;;
  esac
}

ensure_user() {
  if id "${SERVICE_USER}" >/dev/null 2>&1; then
    return
  fi
  log "Lege Systembenutzer ${SERVICE_USER} an"
  useradd --system --create-home --home "/var/lib/${SERVICE_NAME}" --shell /usr/sbin/nologin "${SERVICE_USER}"
}

fetch_sources() {
  TMP_DIR="$(mktemp -d)"
  local target="${TMP_DIR}/source"
  local branch="${BRANCH}"
  local repo="${DEFAULT_REPO}"

  if command -v git >/dev/null 2>&1; then
    log "Klone ${repo}@${branch}"
    git clone --depth 1 --branch "${branch}" "${repo}" "${target}"
  else
    log "Lade Archiv ohne Git (${repo}@${branch})"
    local archive="${TMP_DIR}/source.tar.gz"
    curl -fsSL "${repo}/archive/refs/heads/${branch}.tar.gz" -o "${archive}"
    mkdir -p "${target}"
    tar -xzf "${archive}" -C "${TMP_DIR}"
    local extracted
    extracted="$(find "${TMP_DIR}" -mindepth 1 -maxdepth 1 -type d ! -name source | head -n 1)"
    if [[ -z "${extracted}" ]]; then
      echo "Konnte Archiv nicht extrahieren" >&2
      exit 1
    fi
    mv "${extracted}" "${target}"
  fi
  echo "${target}"
}

sync_release() {
  local source_dir="$1"
  mkdir -p "${INSTALL_ROOT}"
  rm -rf "${INSTALL_ROOT}/current"
  mkdir -p "${INSTALL_ROOT}/current"
  cp -a "${source_dir}/." "${INSTALL_ROOT}/current/"
  chmod +x "${INSTALL_ROOT}/current"/scripts/*.sh
}

create_virtualenv() {
  local venv_dir="${INSTALL_ROOT}/.venv"
  if [[ ! -d "${venv_dir}" ]]; then
    log "Erstelle virtuelles Python-Umfeld"
    python3 -m venv "${venv_dir}"
  fi
  source "${venv_dir}/bin/activate"
  pip install --upgrade pip
  pip install --no-cache-dir -r "${INSTALL_ROOT}/current/requirements.txt"
}

configure_environment_file() {
  if [[ ! -f "${ENV_FILE}" ]]; then
    log "Erzeuge ${ENV_FILE}"
    local secret
    secret="$(python3 - <<'PY'
import secrets
print(secrets.token_hex(32))
PY
)"
    cat <<EOF > "${ENV_FILE}"
SECRET_KEY=${secret}
SLIDESHOW_MANAGER_PORT=5000
AUTH_MODE=pam
EOF
    chmod 640 "${ENV_FILE}"
  fi
  chown "${SERVICE_USER}:${SERVICE_USER}" "${ENV_FILE}"
}

write_service_unit() {
  log "Schreibe systemd-Unit"
  cat <<EOF > "${SERVICE_FILE}"
[Unit]
Description=Slideshow Manager Dashboard
After=network.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_ROOT}/current
EnvironmentFile=-${ENV_FILE}
ExecStart=${INSTALL_ROOT}/current/scripts/start-service.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable --now "${SERVICE_NAME}.service"
}

set_permissions() {
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "${INSTALL_ROOT}"
}

main() {
  require_root
  install_dependencies
  ensure_user
  local source_dir
  source_dir="$(fetch_sources)"
  sync_release "${source_dir}"
  create_virtualenv
  configure_environment_file
  set_permissions
  write_service_unit
  local port="5000"
  if [[ -f "${ENV_FILE}" ]]; then
    port="$(grep -E '^SLIDESHOW_MANAGER_PORT=' "${ENV_FILE}" | cut -d '=' -f2-)"
    port="${port:-5000}"
  fi
  log "Installation abgeschlossen. Die Weboberfläche läuft auf Port ${port}."
}

main "$@"
