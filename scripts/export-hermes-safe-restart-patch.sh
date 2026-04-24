#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HERMES_DIR=${HOME}/.hermes/hermes-agent
SOURCE_REF='stash@{0}'
OUTPUT_PATH="$ROOT_DIR/patches/hermes-safe-restart.patch"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --hermes-dir)
      HERMES_DIR="$2"
      shift 2
      ;;
    --source-ref)
      SOURCE_REF="$2"
      shift 2
      ;;
    --output)
      OUTPUT_PATH="$2"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

git clone --quiet "$HERMES_DIR" "$TMPDIR/repo"
git -C "$TMPDIR/repo" checkout --quiet origin/main

for rel in \
  gateway/run.py \
  gateway/status.py \
  tests/gateway/test_run_progress_topics.py \
  hermes_cli/commands.py \
  tests/hermes_cli/test_commands.py
  do
  mkdir -p "$TMPDIR/repo/$(dirname "$rel")"
  git -C "$HERMES_DIR" show "$SOURCE_REF:$rel" > "$TMPDIR/repo/$rel"
done

mkdir -p "$TMPDIR/repo/tests/gateway"
cp "$HERMES_DIR/tests/gateway/test_restart_handoff.py" "$TMPDIR/repo/tests/gateway/test_restart_handoff.py"

mkdir -p "$(dirname "$OUTPUT_PATH")"

git -C "$TMPDIR/repo" diff --binary origin/main -- \
  gateway/run.py \
  gateway/status.py \
  tests/gateway/test_run_progress_topics.py \
  hermes_cli/commands.py \
  tests/hermes_cli/test_commands.py > "$OUTPUT_PATH"

git -C "$TMPDIR/repo" diff --no-index --binary -- /dev/null tests/gateway/test_restart_handoff.py >> "$OUTPUT_PATH" || true

echo "Wrote $OUTPUT_PATH"
