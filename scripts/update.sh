#!/usr/bin/env bash
set -euo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/Slideshow_Manager}"
SERVICE_NAME="slideshow-manager.service"
REPO="${SLIDESHOW_MANAGER_REPO:-${SLIDESHOW_MANAGER_DEFAULT_REPO:-https://github.com/joni123467/Slideshow_Manager}}"
BRANCH="${SLIDESHOW_MANAGER_BRANCH:-main}"
VENV_DIR="$INSTALL_DIR/.venv"

log() {
  echo "[update.sh] $*"
}

abort() {
  echo "[update.sh] ERROR: $*" >&2
  exit 1
}

require_root() {
  if [[ $(id -u) -ne 0 ]]; then
    abort "Dieses Skript muss als root laufen."
  fi
}

check_command() {
  command -v "$1" >/dev/null 2>&1
}

update_repo() {
  if [[ -d "$INSTALL_DIR/.git" && -d "$INSTALL_DIR/.git/refs" ]]; then
    log "Ziehe Änderungen von $REPO (Branch $BRANCH) ..."
    git -C "$INSTALL_DIR" fetch --depth=1 origin "$BRANCH"
    git -C "$INSTALL_DIR" reset --hard "origin/$BRANCH"
  else
    log "Kein Git-Repository gefunden. Lade Archiv herunter ..."
    local tmp="$(mktemp -d)"
    local archive="$tmp/source.tar.gz"
    local download_url="$REPO/archive/refs/heads/$BRANCH.tar.gz"
    if check_command curl; then
      curl -L "$download_url" -o "$archive"
    elif check_command wget; then
      wget -O "$archive" "$download_url"
    else
      abort "Weder curl noch wget verfügbar."
    fi
    tar -xzf "$archive" -C "$tmp"
    local extracted
    extracted=$(find "$tmp" -maxdepth 1 -type d -name '*Slideshow_Manager*' | head -n1)
    if [[ -z "$extracted" ]]; then
      abort "Archiv konnte nicht entpackt werden."
    fi
    if ! check_command rsync; then
      abort "rsync wird benötigt, um Dateien zu aktualisieren. Bitte installiere rsync."
    fi
    rsync -a --delete "$extracted"/ "$INSTALL_DIR"/
    rm -rf "$tmp"
  fi
}

install_python_deps() {
  if [[ ! -d "$VENV_DIR" ]]; then
    abort "Virtuelle Umgebung wurde nicht gefunden. Bitte Installer erneut ausführen."
  fi
  source "$VENV_DIR/bin/activate"
  pip install --upgrade pip
  pip install -r "$INSTALL_DIR/requirements.txt"
  deactivate || true
}

restart_service() {
  if systemctl is-enabled --quiet "$SERVICE_NAME"; then
    log "Starte Dienst neu ..."
    systemctl restart "$SERVICE_NAME"
  else
    log "Dienst $SERVICE_NAME ist nicht aktiviert. Überspringe Neustart."
  fi
}

main() {
  require_root
  update_repo
  install_python_deps
  restart_service
  log "Update abgeschlossen."
}

main "$@"
