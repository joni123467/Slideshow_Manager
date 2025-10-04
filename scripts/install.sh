#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_TARGET="Slideshow_Manager"
METADATA_FILE=".slideshow-manager.json"
BRANCH=""
TARGET_DIR=""
REPO_IDENTIFIER=""
REMOTE_URL=""
SKIP_DEPENDENCIES=0

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [options]

Options:
  --branch <name>        Install a specific version branch (default: latest version-*)
  --repo <owner/repo>    Repository identifier used when no Git remote is available
  --repo-url <url>       Explicit Git clone URL (overrides identifier derived URL)
  --target <dir>         Installation directory (default: "+$DEFAULT_TARGET" in current directory)
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

install_dependencies() {
  local target="$1"
  if [[ "$SKIP_DEPENDENCIES" -eq 1 ]]; then
    log "Skipping dependency installation (requested)"
    return
  fi
  if command -v pnpm >/dev/null 2>&1; then
    (cd "$target" && pnpm install)
  elif command -v npm >/dev/null 2>&1; then
    (cd "$target" && npm install)
  else
    log "npm/pnpm not found – skipping dependency installation"
  fi
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
  if [[ -z "$TARGET_DIR" ]]; then
    TARGET_DIR="$DEFAULT_TARGET"
  fi
  TARGET_DIR=$(sanitize_path "$TARGET_DIR")
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
  write_metadata "$TARGET_DIR" "$REPO_IDENTIFIER" "$BRANCH"
  log "Installation complete in '$TARGET_DIR'"
}

main "$@"
