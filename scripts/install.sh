#!/usr/bin/env bash
set -euo pipefail

VERSION="1.0.0"
INSTALL_DIR="${INSTALL_DIR:-/opt/Slideshow_Manager}"
DEFAULT_REPO="https://github.com/joni123467/Slideshow_Manager"
REPO="${SLIDESHOW_MANAGER_REPO:-${SLIDESHOW_MANAGER_DEFAULT_REPO:-$DEFAULT_REPO}}"
BRANCH="${SLIDESHOW_MANAGER_BRANCH:-main}"
SERVICE_NAME="slideshow-manager.service"
SERVICE_USER="${SLIDESHOW_MANAGER_SERVICE_USER:-slideshow}"
PYTHON_BIN="python3"
VENV_NAME=".venv"
TMP_DIR="/tmp/slideshow-manager-install"

log() {
  echo "[install.sh] $*"
}

abort() {
  echo "[install.sh] ERROR: $*" >&2
  exit 1
}

usage() {
  cat <<USAGE
Slideshow Manager Installer v$VERSION

Optionen:
  --repo <url>          Git-Repository oder HTTPS-Quelle (Standard: $REPO)
  --branch <name>       Branch oder Tag (Standard: $BRANCH)
  --service-user <name> Systembenutzer für den Dienst (Standard: $SERVICE_USER)
  --install-dir <path>  Installationsverzeichnis (Standard: $INSTALL_DIR)
  -h, --help            Diese Hilfe anzeigen
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      [[ $# -ge 2 ]] || abort "--repo benötigt ein Argument"
      REPO="$2"
      shift 2
      ;;
    --branch)
      [[ $# -ge 2 ]] || abort "--branch benötigt ein Argument"
      BRANCH="$2"
      shift 2
      ;;
    --service-user)
      [[ $# -ge 2 ]] || abort "--service-user benötigt ein Argument"
      SERVICE_USER="$2"
      shift 2
      ;;
    --install-dir)
      [[ $# -ge 2 ]] || abort "--install-dir benötigt ein Argument"
      INSTALL_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      abort "Unbekannte Option: $1"
      ;;
  esac
done

require_root() {
  if [[ $(id -u) -ne 0 ]]; then
    abort "Dieses Skript muss mit Root-Rechten ausgeführt werden. Nutze sudo."
  fi
}

ensure_tmp_dir() {
  rm -rf "$TMP_DIR"
  mkdir -p "$TMP_DIR"
}

check_command() {
  command -v "$1" >/dev/null 2>&1
}

detect_package_manager() {
  if check_command apt-get; then
    echo apt
  elif check_command dnf; then
    echo dnf
  elif check_command yum; then
    echo yum
  elif check_command pacman; then
    echo pacman
  elif check_command zypper; then
    echo zypper
  else
    echo ""
  fi
}

install_dependencies() {
  local manager
  manager=$(detect_package_manager)

  if [[ -z "$manager" ]]; then
    log "Konnte keinen unterstützten Paketmanager erkennen. Bitte installiere python3, python3-venv, git, curl, wget und tar manuell."
    return
  fi

  log "Installiere erforderliche Pakete über $manager ..."
  case "$manager" in
    apt)
      apt-get update
      DEBIAN_FRONTEND=noninteractive apt-get install -y python3 python3-venv python3-pip git curl wget tar rsync
      ;;
    dnf)
      dnf install -y python3 python3-virtualenv python3-pip git curl wget tar rsync
      ;;
    yum)
      yum install -y python3 python3-virtualenv python3-pip git curl wget tar rsync
      ;;
    pacman)
      pacman -Sy --noconfirm python python-pip git curl wget tar rsync
      ;;
    zypper)
      zypper --non-interactive install python3 python3-virtualenv python3-pip git curl wget tar rsync
      ;;
  esac
}

fetch_repository() {
  if check_command git; then
    log "Klone Repository $REPO (Branch $BRANCH) ..."
    if [[ -d "$INSTALL_DIR/.git" ]]; then
      log "Bestehendes Repository gefunden. Aktualisiere..."
      git -C "$INSTALL_DIR" fetch --depth=1 origin "$BRANCH"
      git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
    else
      rm -rf "$INSTALL_DIR"
      git clone --depth=1 --branch "$BRANCH" "$REPO" "$INSTALL_DIR"
    fi
  else
    log "Git nicht verfügbar. Lade Archiv herunter ..."
    ensure_tmp_dir
    local archive="$TMP_DIR/source.tar.gz"
    local download_url="$REPO/archive/refs/heads/$BRANCH.tar.gz"
    if check_command curl; then
      curl -L "$download_url" -o "$archive"
    elif check_command wget; then
      wget -O "$archive" "$download_url"
    else
      abort "Weder curl noch wget verfügbar."
    fi
    rm -rf "$INSTALL_DIR"
    mkdir -p "$INSTALL_DIR"
    tar -xzf "$archive" -C "$TMP_DIR"
    local extracted
    extracted=$(find "$TMP_DIR" -maxdepth 1 -type d -name '*Slideshow_Manager*' | head -n1)
    if [[ -z "$extracted" ]]; then
      abort "Konnte entpacktes Archiv nicht finden."
    fi
    shopt -s dotglob
    mv "$extracted"/* "$INSTALL_DIR"/
    shopt -u dotglob
  fi
}

ensure_service_user() {
  if id "$SERVICE_USER" >/dev/null 2>&1; then
    return
  fi

  log "Lege Service-Benutzer $SERVICE_USER an ..."
  useradd --system --create-home --shell /usr/sbin/nologin "$SERVICE_USER"
}

setup_virtualenv() {
  log "Richte Python-Umgebung ein ..."
  mkdir -p "$INSTALL_DIR"
  if [[ ! -x "$(command -v $PYTHON_BIN)" ]]; then
    abort "python3 wurde nicht gefunden."
  fi
  "$PYTHON_BIN" -m venv "$INSTALL_DIR/$VENV_NAME"
  source "$INSTALL_DIR/$VENV_NAME/bin/activate"
  pip install --upgrade pip
  pip install -r "$INSTALL_DIR/requirements.txt"
  deactivate || true
}

initialize_data() {
  log "Initialisiere Beispieldaten ..."
  source "$INSTALL_DIR/$VENV_NAME/bin/activate"
  SLIDESHOW_MANAGER_DATA_DIR="$INSTALL_DIR/data" python - <<'PY'
from pathlib import Path
from slideshow_manager import storage
from slideshow_manager import create_app

app = create_app()
storage.ensure_seed_data(Path(app.config["DATA_DIR"]))
PY
  deactivate || true
}

configure_permissions() {
  log "Setze Besitzrechte für $SERVICE_USER ..."
  chown -R "$SERVICE_USER":"$SERVICE_USER" "$INSTALL_DIR"
}

create_systemd_unit() {
  log "Erstelle systemd Unit ..."
  local unit_path="/etc/systemd/system/$SERVICE_NAME"
  cat <<UNIT > "$unit_path"
[Unit]
Description=Slideshow Manager Flask Anwendung
After=network.target

[Service]
Type=simple
User=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment="SLIDESHOW_MANAGER_DATA_DIR=$INSTALL_DIR/data"
Environment="PATH=$INSTALL_DIR/$VENV_NAME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin"
ExecStart=$INSTALL_DIR/scripts/start-service.sh
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
UNIT

  chmod 644 "$unit_path"
  systemctl daemon-reload
  systemctl enable --now "$SERVICE_NAME"
}

main() {
  log "Starte Installation v$VERSION"
  require_root
  install_dependencies
  fetch_repository
  ensure_service_user
  setup_virtualenv
  initialize_data
  configure_permissions
  create_systemd_unit
  log "Installation abgeschlossen. Die Anwendung läuft jetzt unter http://localhost:8000"
}

main "$@"
