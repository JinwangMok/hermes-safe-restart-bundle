#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HERMES_DIR=${HERMES_DIR:-$HOME/.hermes/hermes-agent}
PATCH_OUTPUT=${PATCH_OUTPUT:-$ROOT_DIR/patches/hermes-local-overrides.patch}

MANAGED_PATHS=(
  gateway/platforms/discord.py
  gateway/run.py
  gateway/status.py
  package-lock.json
  tests/gateway/test_styled_voice_audio_paths.py
  tests/gateway/test_voice_command.py
  tests/tools/test_managed_media_gateways.py
  tests/tools/test_transcription_tools.py
  tools/transcription_tools.py
  tools/tts_tool.py
  tests/gateway/test_restart_handoff.py
)

if [[ ! -d "$HERMES_DIR/.git" ]]; then
  echo "Hermes git repo not found: $HERMES_DIR" >&2
  exit 1
fi

cd "$HERMES_DIR"
TMP=$(mktemp)
trap 'rm -f "$TMP"' EXIT

# tracked modifications
if [[ ${#MANAGED_PATHS[@]} -gt 0 ]]; then
  git diff --binary HEAD -- "${MANAGED_PATHS[@]}" > "$TMP" || true
fi

# append untracked files that exist in managed list
for path in "${MANAGED_PATHS[@]}"; do
  if [[ -e "$path" ]] && ! git ls-files --error-unmatch "$path" >/dev/null 2>&1; then
    git diff --binary --no-index /dev/null "$path" >> "$TMP" || true
  fi
done

mkdir -p "$(dirname "$PATCH_OUTPUT")"
cp "$TMP" "$PATCH_OUTPUT"

echo "Exported Hermes local overrides patch -> $PATCH_OUTPUT"
