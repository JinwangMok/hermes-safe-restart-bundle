#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage:
  hermes-agent-update-all-bundles.sh --prepare
  hermes-agent-update-all-bundles.sh --execute [--restart-mode conservative-reset|unsafe-marker]
  hermes-agent-update-all-bundles.sh --help

Modes:
  --prepare
      Build/update the local customization lock snapshot and run preflight.
      This is the "ready-to-update" preparation phase and does not mutate Hermes.

  --execute
      Run the real update transaction after preflight passes.
      Default restart mode is conservative-reset.

Restart modes:
  conservative-reset  Safe default. Restart gateway normally after verify.
  unsafe-marker       Legacy planned safe restart wrapper. Disabled unless
                      ALLOW_UNSAFE_MARKER_RESTART=1 is set.
EOF
}

MODE=""
RESTART_MODE="${RESTART_MODE:-conservative-reset}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare)
      MODE="prepare"
      shift
      ;;
    --execute)
      MODE="execute"
      shift
      ;;
    --restart-mode)
      if [[ $# -lt 2 ]]; then
        echo "--restart-mode requires a value and must be passed as two arguments" >&2
        exit 2
      fi
      RESTART_MODE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  usage >&2
  exit 2
fi

ROOT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WORKSPACE_DIR="${WORKSPACE_DIR:-$HOME/workspace}"
HERMES_DIR="${HERMES_DIR:-$HOME/.hermes/hermes-agent}"
CONFIG_PATH="${CONFIG_PATH:-$HOME/.hermes/config.yaml}"
DISCORD_VOICE_BUNDLE_DIR="${DISCORD_VOICE_BUNDLE_DIR:-$WORKSPACE_DIR/discord-voice-stt-enhance}"
STYLED_VOICE_BUNDLE_DIR="${STYLED_VOICE_BUNDLE_DIR:-$WORKSPACE_DIR/styled-voice}"
SAFE_RESTART_BUNDLE_DIR="${SAFE_RESTART_BUNDLE_DIR:-$WORKSPACE_DIR/hermes-safe-restart-bundle}"
SAFE_RESTART_BIN="${SAFE_RESTART_BIN:-$HOME/.local/bin/hermes-safe-restart}"
JARVIS_DIR="${JARVIS_DIR:-$WORKSPACE_DIR/jinwang-jarvis}"
JARVIS_POLL_MINUTES="${JARVIS_POLL_MINUTES:-5}"
LOCK_PATH="${LOCK_PATH:-$ROOT_DIR/customization-lock.yaml}"
SNAPSHOT_PATH="${SNAPSHOT_PATH:-$ROOT_DIR/reports/customization-lock.snapshot.json}"
PREFLIGHT_REPORT="${PREFLIGHT_REPORT:-$ROOT_DIR/reports/update-preflight-report.json}"
PLAN_RENDERER="${PLAN_RENDERER:-$ROOT_DIR/scripts/render-update-plan.py}"

require_cmd() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || { echo "Required command not found: $cmd" >&2; exit 1; }
}

require_file() {
  local path="$1"
  [[ -e "$path" ]] || { echo "Required path not found: $path" >&2; exit 1; }
}

run_cmd() {
  printf '\n==> %s\n' "$*"
  "$@"
}

run_prepare() {
  require_cmd git
  require_cmd python3
  require_file "$LOCK_PATH"
  require_file "$ROOT_DIR/scripts/build-customization-lock.py"
  require_file "$ROOT_DIR/scripts/update-preflight.py"
  require_file "$PLAN_RENDERER"
  run_cmd python3 "$ROOT_DIR/scripts/build-customization-lock.py" --lock "$LOCK_PATH" --output "$SNAPSHOT_PATH"
  run_cmd python3 "$ROOT_DIR/scripts/update-preflight.py" --lock "$LOCK_PATH" --snapshot "$SNAPSHOT_PATH" --output "$PREFLIGHT_REPORT"
}

run_execute() {
  require_cmd hermes
  require_cmd git
  require_cmd python3
  require_file "$HERMES_DIR/.git"
  require_file "$LOCK_PATH"
  require_file "$SNAPSHOT_PATH"
  require_file "$PREFLIGHT_REPORT"
  require_file "$PLAN_RENDERER"

  run_cmd python3 "$ROOT_DIR/scripts/update-preflight.py" --lock "$LOCK_PATH" --snapshot "$SNAPSHOT_PATH" --output "$PREFLIGHT_REPORT"

  printf 'Hermes dir: %s\n' "$HERMES_DIR"
  printf 'Config:     %s\n' "$CONFIG_PATH"
  printf 'Workspace:  %s\n' "$WORKSPACE_DIR"
  printf 'Restart:    %s\n' "$RESTART_MODE"

  mapfile -t INSTALL_LINES < <(python3 - "$PLAN_RENDERER" "$LOCK_PATH" <<'PY'
import json, subprocess, sys
renderer, lock = sys.argv[1], sys.argv[2]
data = json.loads(subprocess.check_output([sys.executable, renderer, '--lock', lock], text=True))
for item in data['bundles']:
    script = item.get('install_script')
    if script:
        print(f"INSTALL\t{item['bundle_id']}\t{script}")
    verify = item.get('verify_script')
    if verify:
        print(f"VERIFY\t{item['bundle_id']}\t{verify}")
PY
)

  run_cmd hermes update

  declare -a VERIFY_CMDS=()
  for line in "${INSTALL_LINES[@]}"; do
    kind=${line%%$'\t'*}
    rest=${line#*$'\t'}
    bundle_id=${rest%%$'\t'*}
    script=${rest#*$'\t'}
    case "$kind" in
      INSTALL)
        case "$bundle_id" in
          discord-voice-stt-enhance)
            run_cmd "$script" "$HERMES_DIR"
            ;;
          styled-voice)
            run_cmd "$script" --hermes-dir "$HERMES_DIR" --config "$CONFIG_PATH"
            ;;
          hermes-safe-restart-bundle)
            run_cmd "$script" --hermes-dir "$HERMES_DIR" --config "$CONFIG_PATH"
            ;;
          jinwang-jarvis)
            run_cmd "$script" --poll-minutes "$JARVIS_POLL_MINUTES"
            ;;
          hermes-local-overrides)
            run_cmd "$script"
            ;;
          *)
            echo "Unknown install bundle_id: $bundle_id" >&2
            exit 1
            ;;
        esac
        ;;
      VERIFY)
        VERIFY_CMDS+=("$bundle_id::$script")
        ;;
      *)
        echo "Unknown plan entry: $line" >&2
        exit 1
        ;;
    esac
  done

  for entry in "${VERIFY_CMDS[@]}"; do
    bundle_id=${entry%%::*}
    script=${entry#*::}
    case "$bundle_id" in
      discord-voice-stt-enhance)
        run_cmd "$script" "$HERMES_DIR"
        ;;
      styled-voice)
        run_cmd "$script" --hermes-dir "$HERMES_DIR"
        ;;
      hermes-safe-restart-bundle)
        run_cmd "$script" --hermes-dir "$HERMES_DIR"
        ;;
      jinwang-jarvis)
        run_cmd "$script"
        ;;
      *)
        run_cmd "$script"
        ;;
    esac
  done

  case "$RESTART_MODE" in
    conservative-reset)
      run_cmd systemctl --user restart hermes-gateway
      ;;
    unsafe-marker)
      if [[ "${ALLOW_UNSAFE_MARKER_RESTART:-0}" != "1" ]]; then
        echo "unsafe-marker restart mode is disabled by policy. Set ALLOW_UNSAFE_MARKER_RESTART=1 to override." >&2
        exit 1
      fi
      if [[ ! -x "$SAFE_RESTART_BIN" ]]; then
        if [[ -x "$WORKSPACE_DIR/hermes-safe-restart" ]]; then
          SAFE_RESTART_BIN="$WORKSPACE_DIR/hermes-safe-restart"
        else
          echo "Safe restart helper not found or not executable: $SAFE_RESTART_BIN" >&2
          exit 1
        fi
      fi
      run_cmd "$SAFE_RESTART_BIN"
      ;;
    *)
      echo "Unknown restart mode: $RESTART_MODE" >&2
      exit 2
      ;;
  esac

  printf '\nDone: Hermes updated, source-untouched external bundles installed, verifies passed, restart completed.\n'
}

case "$MODE" in
  prepare)
    run_prepare
    ;;
  execute)
    run_execute
    ;;
  *)
    echo "Unknown mode: $MODE" >&2
    exit 2
    ;;
esac
