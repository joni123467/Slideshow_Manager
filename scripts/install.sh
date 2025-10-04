#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_TARGET="/opt/Slideshow_Manager"
DEFAULT_REPO_IDENTIFIER="${SLIDESHOW_MANAGER_DEFAULT_REPO:-joni123467/Slideshow_Manager}"
METADATA_FILE=".slideshow-manager.json"
BRANCH=""
TARGET_DIR=""
REPO_IDENTIFIER=""
REMOTE_URL=""
SKIP_DEPENDENCIES=0
SERVICE_USER=""
SYSTEMD_SERVICE_NAME="slideshow-manager.service"

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --branch <name>        Install a specific version branch (default: latest version-*)
  --repo <owner/repo>    Repository identifier used when no Git remote is available
  --repo-url <url>       Explicit Git clone URL (overrides identifier derived URL)
  --target <dir>         Installation directory (default: $DEFAULT_TARGET)
  --service-user <user>  System user that should run the service (default: current user/root)
  --skip-deps            Skip dependency installation step
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
      --target)
        TARGET_DIR="$2"
        shift 2
        ;;
      --service-user)
        SERVICE_USER="$2"
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

ensure_root() {
  if [[ $EUID -ne 0 ]]; then
    error "This installer must be executed with administrative privileges (sudo)."
  fi
}

default_service_user() {
  if [[ -n "$SERVICE_USER" ]]; then
    return
  fi
  if [[ -n "${SUDO_USER:-}" ]]; then
    SERVICE_USER="$SUDO_USER"
    return
  fi
  if [[ -n "${USER:-}" && "$USER" != "root" ]]; then
    SERVICE_USER="$USER"
  fi
}

parse_repo_identifier() {
  local input="$1"
  if [[ -z "$input" ]]; then
    echo ""
    return
  fi
  if [[ "$input" == http*://* || "$input" == git@*:* ]]; then
    echo "$input"
    return
  fi
  echo "$input"
}

repo_from_git_remote() {
  if ! command -v git >/dev/null 2>&1; then
    return
  fi
  local url
  url=$(git config --get remote.origin.url 2>/dev/null || true)
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
    echo "$BRANCH"
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

clone_with_git() {
  local remote="$1"
  local branch="$2"
  local target="$3"
  git clone --depth 1 --branch "$branch" "$remote" "$target"
}

download_archive() {
  local http_base="$1"
  local branch="$2"
  local target="$3"
  require_command curl
  require_command tar
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
  mkdir -p "$target"
  cp -R "$extracted"/. "$target"/
  rm -rf "$tmpdir"
  trap - EXIT
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
  local target="$1"
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
    (cd "$target" && pnpm install)
  else
    (cd "$target" && npm install)
  fi
}

build_application() {
  local target="$1"
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
    (cd "$target" && pnpm run build)
  else
    (cd "$target" && npm run build)
  fi
}

setup_systemd_service() {
  local target="$1"
  local service_user="$2"
  if ! command -v systemctl >/dev/null 2>&1; then
    log "systemctl not available – skipping systemd service setup"
    return
  fi
  local service_file="/etc/systemd/system/$SYSTEMD_SERVICE_NAME"
  local user_line=""
  if [[ -n "$service_user" ]]; then
    if id -u "$service_user" >/dev/null 2>&1; then
      user_line="User=$service_user"
    else
      log "Warning: user '$service_user' does not exist. The service will run as root."
    fi
  fi
  if [[ -f "$target/scripts/start-service.sh" ]]; then
    chmod +x "$target/scripts/start-service.sh"
  fi
  cat >"$service_file" <<UNIT
[Unit]
Description=Slideshow Manager
After=network.target

[Service]
Type=simple
WorkingDirectory=$target
ExecStart=$target/scripts/start-service.sh
Restart=on-failure
RestartSec=5
Environment=NODE_ENV=production
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
${user_line}

[Install]
WantedBy=multi-user.target
UNIT
  chmod 644 "$service_file"
  log "systemd unit written to $service_file"
  systemctl daemon-reload
  systemctl enable --now "$SYSTEMD_SERVICE_NAME"
  if [[ -n "$service_user" && -n "$user_line" ]]; then
    log "Service '$SYSTEMD_SERVICE_NAME' configured to run as user '$service_user'"
  else
    log "Service '$SYSTEMD_SERVICE_NAME' configured to run as root"
  fi
  log "Service '$SYSTEMD_SERVICE_NAME' enabled and started"
}

ensure_service_permissions() {
  local target="$1"
  local service_user="$2"
  if [[ -z "$service_user" ]]; then
    return
  fi
  if ! id -u "$service_user" >/dev/null 2>&1; then
    return
  fi
  chown -R "$service_user":"$service_user" "$target"
}

write_metadata() {
  local target="$1"
  local identifier="$2"
  local branch="$3"
  cat >"$target/$METADATA_FILE" <<JSON
{
  "repo": "$identifier",
  "branch": "$branch",
  "updated": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
JSON
}

main() {
  parse_args "$@"
  ensure_root
  if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$DEFAULT_TARGET"
  fi
  TARGET_DIR=$(sanitize_path "$TARGET_DIR")
  default_service_user
  if [[ -z "$REPO_IDENTIFIER" ]]; then
    REPO_IDENTIFIER="$(parse_repo_identifier "${SLIDESHOW_MANAGER_REPO:-}")"
  fi
  if [[ -z "$REPO_IDENTIFIER" ]]; then
    local derived
    derived=$(repo_from_git_remote || true)
    if [[ -n "$derived" ]]; then
      REPO_IDENTIFIER="$derived"
    fi
  fi
  if [[ -z "$REPO_IDENTIFIER" ]]; then
    REPO_IDENTIFIER="$(parse_repo_identifier "$DEFAULT_REPO_IDENTIFIER")"
  fi
  if [[ -z "$REPO_IDENTIFIER" && -z "$REMOTE_URL" ]]; then
    error "No repository identifier provided. Use --repo or set SLIDESHOW_MANAGER_REPO."
  fi
  if [[ -z "$REMOTE_URL" ]]; then
    REMOTE_URL="$(identifier_to_remote_url "$REPO_IDENTIFIER")"
  fi
  if [[ -z "$REMOTE_URL" ]]; then
    error "Unable to derive a Git remote URL."
  fi
  ensure_branch "$REMOTE_URL" "$REPO_IDENTIFIER"
  log "Using branch '$BRANCH'"
  if [[ -d "$TARGET_DIR" && -n "$(ls -A "$TARGET_DIR" 2>/dev/null)" ]]; then
    error "Target directory '$TARGET_DIR' is not empty."
  fi
  mkdir -p "$TARGET_DIR"
  if command -v git >/dev/null 2>&1; then
    log "Cloning repository via Git"
    clone_with_git "$REMOTE_URL" "$BRANCH" "$TARGET_DIR"
  else
    local http_base
    http_base="$(remote_to_http_base "$REMOTE_URL")"
    if [[ -z "$http_base" ]]; then
      error "Cannot derive HTTP download URL – install Git or provide a GitHub HTTPS remote."
    fi
    log "Downloading archive without Git"
    download_archive "$http_base" "$BRANCH" "$TARGET_DIR"
  fi
  install_dependencies "$TARGET_DIR"
  build_application "$TARGET_DIR"
  write_metadata "$TARGET_DIR" "$REPO_IDENTIFIER" "$BRANCH"
  ensure_service_permissions "$TARGET_DIR" "$SERVICE_USER"
  setup_systemd_service "$TARGET_DIR" "$SERVICE_USER"
  log "Installation complete in '$TARGET_DIR'"
}

main "$@"
