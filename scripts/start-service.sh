#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENV_DIR="$DIR/.venv"
PORT="${PORT:-8000}"

if [[ ! -d "$VENV_DIR" ]]; then
  echo "[start-service.sh] ERROR: Virtuelle Umgebung wurde nicht gefunden unter $VENV_DIR" >&2
  exit 1
fi

source "$VENV_DIR/bin/activate"
exec gunicorn --bind "0.0.0.0:$PORT" "slideshow_manager:create_app()"
