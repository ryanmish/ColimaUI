#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT_DIR/scripts/colimaui"
BUNDLED="$ROOT_DIR/ColimaUI/Resources/colimaui"

if ! diff -u "$SRC" "$BUNDLED" >/dev/null; then
  echo "ERROR: scripts/colimaui and ColimaUI/Resources/colimaui are out of sync." >&2
  echo "Run: cp scripts/colimaui ColimaUI/Resources/colimaui" >&2
  exit 1
fi

echo "OK: bundled CLI is in sync"
