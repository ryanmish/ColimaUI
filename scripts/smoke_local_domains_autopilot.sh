#!/usr/bin/env bash
set -euo pipefail

echo "== ColimaUI Local Domains Autopilot Smoke =="

if ! command -v colima >/dev/null 2>&1; then
  echo "colima not found"
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "docker not found"
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "docker is unreachable (start Colima first)"
  exit 1
fi

echo "-- check (or setup if needed)"
if ! colimaui domains check >/dev/null 2>&1; then
  if [[ ! -t 0 ]]; then
    echo "Skipping setup in non-interactive shell (sudo password prompt requires a TTY)"
    exit 0
  fi
  colimaui domains setup >/dev/null
  colimaui domains check >/dev/null
fi

echo "-- sync/urls"
colimaui domains sync >/dev/null
urls="$(colimaui domains urls)"
echo "$urls" | grep -q "index.dev.local"

echo "-- dns probe"
dscacheutil -q host -a name index.dev.local | grep -q "127.0.0.1"

echo "Smoke passed"
