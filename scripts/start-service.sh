#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
VENV_DIR="${APP_DIR}/.venv"
ENV_FILE="/etc/slideshow-manager.env"

if [[ -f "${ENV_FILE}" ]]; then
  # shellcheck source=/etc/slideshow-manager.env
  set -a
  source "${ENV_FILE}"
  set +a
fi

export PATH="${VENV_DIR}/bin:${PATH}"

if [[ ! -d "${VENV_DIR}" ]]; then
  echo "[start-service] Missing virtualenv at ${VENV_DIR}" >&2
  exit 1
fi

source "${VENV_DIR}/bin/activate"

PORT="${SLIDESHOW_MANAGER_PORT:-5000}"
WORKERS="${SLIDESHOW_MANAGER_WORKERS:-3}"
LOG_LEVEL="${SLIDESHOW_MANAGER_LOG_LEVEL:-info}"

exec gunicorn \
  --bind "0.0.0.0:${PORT}" \
  --workers "${WORKERS}" \
  --log-level "${LOG_LEVEL}" \
  "slideshow_manager:create_app()"
