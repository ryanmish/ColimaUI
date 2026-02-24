#!/usr/bin/env bash
set -euo pipefail

SUFFIX="dev.local"
SCHEME="https"
COMPOSE_DIR=""
PROJECT_NAME=""
SKIP_CHECK="0"

usage() {
  cat <<USAGE
Spin up a Compose project and verify ColimaUI local domains.

Usage:
  scripts/spinup_and_check_domains.sh --compose-dir /path/to/project [options]

Options:
  --compose-dir <path>   Compose project directory (required)
  --project <name>       Override compose project name
  --scheme <http|https>  URL scheme for printed links (default: https)
  --no-check             Skip 'colimaui domains check'
  -h, --help             Show help
USAGE
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "Missing required command: $1" >&2
    exit 1
  }
}

normalize_label() {
  printf '%s' "${1:-}" \
    | tr '[:upper:]_' '[:lower:]-' \
    | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//'
}

resolve_project_name() {
  local from_label ids id label attempts
  if [[ -n "$PROJECT_NAME" ]]; then
    normalize_label "$PROJECT_NAME"
    return
  fi

  attempts=0
  while (( attempts < 40 )); do
    ids="$(docker compose ps -q 2>/dev/null || true)"
    for id in $ids; do
      label="$(docker inspect --format '{{ index .Config.Labels "com.docker.compose.project" }}' "$id" 2>/dev/null || true)"
      from_label="$(normalize_label "$label")"
      if [[ -n "$from_label" ]]; then
        printf '%s' "$from_label"
        return
      fi
    done
    attempts=$((attempts + 1))
    sleep 0.25
  done

  if [[ -n "${COMPOSE_PROJECT_NAME:-}" ]]; then
    from_label="$(normalize_label "${COMPOSE_PROJECT_NAME}")"
    if [[ -n "$from_label" ]]; then
      printf '%s' "$from_label"
      return
    fi
  fi

  normalize_label "$(basename "$COMPOSE_DIR")"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --compose-dir)
      COMPOSE_DIR="${2:-}"
      shift 2
      ;;
    --project)
      PROJECT_NAME="${2:-}"
      shift 2
      ;;
    --scheme)
      SCHEME="${2:-}"
      shift 2
      ;;
    --no-check)
      SKIP_CHECK="1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$COMPOSE_DIR" ]]; then
  echo "--compose-dir is required" >&2
  usage
  exit 1
fi

if [[ "$SCHEME" != "http" && "$SCHEME" != "https" ]]; then
  echo "--scheme must be 'http' or 'https'" >&2
  exit 1
fi

need_cmd docker
need_cmd colimaui

cd "$COMPOSE_DIR"

echo "== Starting compose project =="
docker compose up -d

echo "== Syncing ColimaUI routes =="
colimaui domains sync >/dev/null

if [[ "$SKIP_CHECK" != "1" ]]; then
  echo "== Checking local-domain health =="
  colimaui domains check
fi

project="$(resolve_project_name)"
if [[ -z "$project" ]]; then
  echo "Could not determine compose project name" >&2
  exit 1
fi

echo ""
echo "Project: $project"
echo "Index: ${SCHEME}://index.${SUFFIX}"

echo ""
echo "Compose service URLs (${SCHEME}):"
escaped_project="$(printf '%s' "$project" | sed 's/[][\.^$*+?{}|()]/\\&/g')"
discovered_urls="$(colimaui domains urls)"

compose_urls="$(printf '%s\n' "$discovered_urls" | grep -E "^https://[^.]+\.${escaped_project}\.${SUFFIX}$" || true)"
if [[ -n "$compose_urls" ]]; then
  if [[ "$SCHEME" == "http" ]]; then
    printf '%s\n' "$compose_urls" | sed 's#^https://#http://#' | sed 's/^/- /'
  else
    printf '%s\n' "$compose_urls" | sed 's/^/- /'
  fi
else
  echo "- No compose service domains discovered yet"
fi

echo ""
echo "All discovered routed URLs:"
if [[ "$SCHEME" == "http" ]]; then
  printf '%s\n' "$discovered_urls" | sed 's#^https://#http://#' | sed 's/^/- /'
else
  printf '%s\n' "$discovered_urls" | sed 's/^/- /'
fi
