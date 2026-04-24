#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HERMES_DIR=${HOME}/.hermes/hermes-agent
LOCK_PATH="$ROOT_DIR/customization-lock.yaml"
PYTEST_PYTHON=${HERMES_VERIFY_PYTHON:-}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hermes-dir)
      HERMES_DIR="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$PYTEST_PYTHON" ]]; then
  if python3 -c 'import pytest' >/dev/null 2>&1; then
    PYTEST_PYTHON="python3"
  elif [[ -x "$HOME/.hermes/hermes-agent/venv/bin/python" ]]; then
    PYTEST_PYTHON="$HOME/.hermes/hermes-agent/venv/bin/python"
  else
    echo "Could not find a Python interpreter with pytest installed" >&2
    exit 1
  fi
fi

echo "==> Running hermes-safe-restart-bundle repo tests"
cd "$ROOT_DIR"
"$PYTEST_PYTHON" -m pytest tests/test_source_untouched_flow.py -q

SNAPSHOT=$(mktemp)
REPORT=$(mktemp)
trap 'rm -f "$SNAPSHOT" "$REPORT"' EXIT

echo "==> Building customization snapshot"
python3 "$ROOT_DIR/scripts/build-customization-lock.py" --lock "$LOCK_PATH" --output "$SNAPSHOT"

echo "==> Rendering update plan"
python3 "$ROOT_DIR/scripts/render-update-plan.py" --lock "$LOCK_PATH" >/dev/null

echo "==> Running source-untouched preflight"
python3 "$ROOT_DIR/scripts/update-preflight.py" --lock "$LOCK_PATH" --snapshot "$SNAPSHOT" --output "$REPORT"
