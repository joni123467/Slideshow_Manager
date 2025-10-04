#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
METADATA_FILE=".slideshow-manager.json"
BRANCH=""
REPO_IDENTIFIER=""
REMOTE_URL=""
ROOT_OVERRIDE=""
SKIP_DEPENDENCIES=0
SYSTEMD_SERVICE_NAME="slideshow-manager.service"
DEFAULT_REPO_IDENTIFIER="${SLIDESHOW_MANAGER_DEFAULT_REPO:-joni123467/Slideshow_Manager}"

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --branch <name>        Update to a specific version branch (default: latest version-*)
  --repo <owner/repo>    Repository identifier used for archive downloads
  --repo-url <url>       Explicit Git remote URL (overrides derived value)
  --root <dir>           Root directory of the installation (default: repository root)
  --skip-deps            Skip dependency installation
  -h, --help             Show this help message
USAGE
}

log() {
  echo "[$SCRIPT_NAME] $*"
}

error() {
  echo "[$SCRIPT_NAME] ERROR: $*" >&2
  exit 1
}

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    error "Required command '$1' is not available."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --branch)
        BRANCH="$2"
        shift 2
        ;;
      --repo)
        REPO_IDENTIFIER="$2"
        shift 2
        ;;
      --repo-url)
        REMOTE_URL="$2"
        shift 2
        ;;
      --root)
        ROOT_OVERRIDE="$2"
        shift 2
        ;;
      --skip-deps)
        SKIP_DEPENDENCIES=1
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        error "Unknown argument: $1"
        ;;
    esac
  done
}

sanitize_path() {
  local path="$1"
  if [[ -z "$path" ]]; then
    return
  fi
  if [[ "$path" != /* ]]; then
    path="$(pwd)/$path"
  fi
  echo "$path"
}

metadata_value() {
  local file="$1"
  local key="$2"
  if [[ ! -f "$file" ]]; then
    echo ""
    return
  fi
  grep -o '"'$key'"[[:space:]]*:[[:space:]]*"[^"]*"' "$file" | head -n1 | sed 's/.*"'$key'"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

repo_from_git_remote() {
  if ! command -v git >/dev/null 2>&1; then
    return
  fi
  local url
  url=$(git -C "$ROOT_DIR" config --get remote.origin.url 2>/dev/null || true)
  if [[ -z "$url" ]]; then
    return
  fi
  if [[ "$url" =~ ^https?://github.com/([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  elif [[ "$url" =~ ^git@github.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
  fi
}

identifier_to_remote_url() {
  local identifier="$1"
  if [[ -z "$identifier" ]]; then
    echo ""
    return
  fi
  if [[ "$identifier" == http*://* || "$identifier" == git@*:* ]]; then
    echo "$identifier"
    return
  fi
  echo "https://github.com/$identifier.git"
}

remote_to_http_base() {
  local url="$1"
  if [[ "$url" =~ ^https?://[^/]+/(.+)$ ]]; then
    local path="${BASH_REMATCH[1]}"
    path="${path%.git}"
    echo "https://github.com/${path}"
    return
  fi
  if [[ "$url" =~ ^git@github.com:([^/]+)/([^/.]+)(\.git)?$ ]]; then
    echo "https://github.com/${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
    return
  fi
  echo ""
}

version_branch_sort() {
  sort -t- -k2,2V
}

select_latest_branch() {
  local branches="$1"
  if [[ -z "$branches" ]]; then
    echo ""
    return
  fi
  echo "$branches" | grep '^version-' | version_branch_sort | tail -n1
}

latest_branch_from_git() {
  local remote="$1"
  local refs
  refs=$(git ls-remote --heads "$remote" 2>/dev/null | awk '{print $2}' | sed 's#refs/heads/##' || true)
  select_latest_branch "$refs"
}

latest_branch_from_api() {
  local identifier="$1"
  if [[ -z "$identifier" ]]; then
    echo ""
    return
  fi
  require_command curl
  local response
  response=$(curl -fsSL "https://api.github.com/repos/$identifier/branches?per_page=100" || true)
  if [[ -z "$response" ]]; then
    echo ""
    return
  fi
  local branches
  branches=$(echo "$response" | grep -o '"name":"version-[^"]*"' | cut -d'"' -f4 || true)
  select_latest_branch "$branches"
}

ensure_branch() {
  local remote="$1"
  local identifier="$2"
  if [[ -n "$BRANCH" ]]; then
    return
  fi
  local latest=""
  if command -v git >/dev/null 2>&1; then
    latest=$(latest_branch_from_git "$remote")
  fi
  if [[ -z "$latest" ]]; then
    latest=$(latest_branch_from_api "$identifier")
  fi
  if [[ -z "$latest" ]]; then
    error "Unable to determine the latest version branch. Provide --branch explicitly."
  fi
  BRANCH="$latest"
}

detect_package_runner() {
  if command -v pnpm >/dev/null 2>&1; then
    echo "pnpm"
    return
  fi
  if command -v npm >/dev/null 2>&1; then
    echo "npm"
    return
  fi
  echo ""
}

install_dependencies() {
  if [[ "$SKIP_DEPENDENCIES" -eq 1 ]]; then
    log "Skipping dependency installation (requested)"
    return
  fi
  local runner
  runner=$(detect_package_runner)
  if [[ -z "$runner" ]]; then
    log "npm/pnpm not found – skipping dependency installation"
    return
  fi
  if [[ "$runner" == "pnpm" ]]; then
    (cd "$ROOT_DIR" && pnpm install)
  else
    (cd "$ROOT_DIR" && npm install)
  fi
}

build_application() {
  if [[ "$SKIP_DEPENDENCIES" -eq 1 ]]; then
    log "Skipping build because dependencies were skipped"
    return
  fi
  local runner
  runner=$(detect_package_runner)
  if [[ -z "$runner" ]]; then
    log "npm/pnpm not found – skipping build"
    return
  fi
  log "Building production bundle"
  if [[ "$runner" == "pnpm" ]]; then
    (cd "$ROOT_DIR" && pnpm run build)
  else
    (cd "$ROOT_DIR" && npm run build)
  fi
}

write_metadata() {
  local identifier="$1"
  local branch="$2"
  cat >"$ROOT_DIR/$METADATA_FILE" <<JSON
{
  "repo": "$identifier",
  "branch": "$branch",
  "updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON
}

update_with_git() {
  local remote="$1"
  local branch="$2"
  require_command git
  git -C "$ROOT_DIR" remote | grep -qx "origin" || git -C "$ROOT_DIR" remote add origin "$remote"
  git -C "$ROOT_DIR" remote set-url origin "$remote"
  git -C "$ROOT_DIR" fetch origin "$branch"
  if git -C "$ROOT_DIR" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$ROOT_DIR" checkout "$branch"
  else
    git -C "$ROOT_DIR" checkout -b "$branch" "origin/$branch"
  fi
  git -C "$ROOT_DIR" reset --hard "origin/$branch"
  git -C "$ROOT_DIR" clean -fd
}

update_without_git() {
  local remote="$1"
  local branch="$2"
  local http_base
  http_base=$(remote_to_http_base "$remote")
  if [[ -z "$http_base" ]]; then
    if [[ -n "$REPO_IDENTIFIER" ]]; then
      http_base="https://github.com/${REPO_IDENTIFIER}"
    fi
  fi
  if [[ -z "$http_base" ]]; then
    error "Cannot derive an HTTP download URL for the repository."
  fi
  require_command curl
  require_command tar
  require_command python3
  local tmpdir
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT
  local archive_url="${http_base}/archive/refs/heads/${branch}.tar.gz"
  log "Downloading ${archive_url}"
  curl -fsSL "$archive_url" -o "$tmpdir/archive.tgz"
  tar -xzf "$tmpdir/archive.tgz" -C "$tmpdir"
  local extracted
  extracted=$(find "$tmpdir" -mindepth 1 -maxdepth 1 -type d | head -n1)
  if [[ -z "$extracted" ]]; then
    error "Failed to extract archive"
  fi
  log "Replacing application files"
  python3 - "$extracted" "$ROOT_DIR" <<'PY'
import os
import shutil
import sys

src = sys.argv[1]
dst = sys.argv[2]
preserve = {'.env', '.env.local', '.env.production', '.slideshow-manager.json', 'node_modules'}

for name in os.listdir(dst):
    if name in preserve:
        continue
    path = os.path.join(dst, name)
    if os.path.isdir(path) and not os.path.islink(path):
        shutil.rmtree(path)
    else:
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

for name in os.listdir(src):
    src_path = os.path.join(src, name)
    dst_path = os.path.join(dst, name)
    if os.path.isdir(src_path) and not os.path.islink(src_path):
        if os.path.exists(dst_path):
            shutil.rmtree(dst_path)
        shutil.copytree(src_path, dst_path, symlinks=True)
    else:
        os.makedirs(os.path.dirname(dst_path), exist_ok=True)
        shutil.copy2(src_path, dst_path)
PY
  rm -rf "$tmpdir"
  trap - EXIT
}

schedule_service_restart() {
  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not available – skipping service restart"
    return
  fi
  if ! systemctl cat "$SYSTEMD_SERVICE_NAME" >/dev/null 2>&1; then
    log "Systemd unit '$SYSTEMD_SERVICE_NAME' not installed – skipping restart"
    return
  fi
  log "Restarting systemd service '$SYSTEMD_SERVICE_NAME'"
  if command -v systemd-run >/dev/null 2>&1; then
    if ! systemd-run --quiet --on-active=1s /bin/systemctl restart "$SYSTEMD_SERVICE_NAME"; then
      if ! systemctl restart "$SYSTEMD_SERVICE_NAME"; then
        log "Failed to restart systemd service '$SYSTEMD_SERVICE_NAME'. Please restart manually."
      fi
    fi
  else
    if ! systemctl restart "$SYSTEMD_SERVICE_NAME"; then
      log "Failed to restart systemd service '$SYSTEMD_SERVICE_NAME'. Please restart manually."
    fi
  fi
}

main() {
  parse_args "$@"
  if [[ -n "$ROOT_OVERRIDE" ]]; then
    ROOT_DIR=$(sanitize_path "$ROOT_OVERRIDE")
  fi
  if [[ ! -d "$ROOT_DIR" ]]; then
    error "Root directory '$ROOT_DIR' does not exist"
  fi
  local metadata_path="$ROOT_DIR/$METADATA_FILE"
  if [[ -z "$REPO_IDENTIFIER" ]]; then
    REPO_IDENTIFIER="$(metadata_value "$metadata_path" repo)"
  fi
  if [[ -z "$REPO_IDENTIFIER" && -n "${SLIDESHOW_MANAGER_REPO:-}" ]]; then
    REPO_IDENTIFIER="${SLIDESHOW_MANAGER_REPO}"
  fi
  if [[ -z "$REPO_IDENTIFIER" ]]; then
    local derived
    derived=$(repo_from_git_remote || true)
    if [[ -n "$derived" ]]; then
      REPO_IDENTIFIER="$derived"
    fi
  fi
  if [[ -z "$REPO_IDENTIFIER" && -n "${SLIDESHOW_MANAGER_REPO:-}" ]]; then
    REPO_IDENTIFIER="${SLIDESHOW_MANAGER_REPO}"
  fi
  if [[ -z "$REPO_IDENTIFIER" ]]; then
    REPO_IDENTIFIER="$DEFAULT_REPO_IDENTIFIER"
  fi
  if [[ -z "$REMOTE_URL" ]]; then
    if [[ -d "$ROOT_DIR/.git" && command -v git >/dev/null 2>&1 ]]; then
      REMOTE_URL=$(git -C "$ROOT_DIR" remote get-url origin 2>/dev/null || true)
    fi
  fi
  if [[ -z "$REMOTE_URL" ]]; then
    REMOTE_URL="$(identifier_to_remote_url "$REPO_IDENTIFIER")"
  fi
  if [[ -z "$REMOTE_URL" ]]; then
    error "Unable to resolve repository URL."
  fi
  ensure_branch "$REMOTE_URL" "$REPO_IDENTIFIER"
  log "Updating to branch '$BRANCH'"
  if [[ -d "$ROOT_DIR/.git" && command -v git >/dev/null 2>&1 ]]; then
    update_with_git "$REMOTE_URL" "$BRANCH"
  else
    update_without_git "$REMOTE_URL" "$BRANCH"
  fi
  install_dependencies
  build_application
  write_metadata "$REPO_IDENTIFIER" "$BRANCH"
  schedule_service_restart
  log "Update complete"
}

main "$@"
