#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
APP_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

cd "$APP_DIR"

if command -v pnpm >/dev/null 2>&1; then
  exec pnpm run start
elif command -v npm >/dev/null 2>&1; then
  exec npm run start
else
  echo "No supported package manager (pnpm or npm) found in PATH." >&2
  exit 1
fi
