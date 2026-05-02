#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$HOME/.local/share/fnm/node-versions/v24.14.1/installation/bin:$PATH"
LOG_DIR="$HOME/.hermes/recovery"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/hermes-update-restart-$(date -u +%Y%m%dT%H%M%SZ).log"
REPORT="$LOG_DIR/hermes-update-restart-latest.report"
exec > >(tee -a "$LOG") 2>&1

HERMES_DIR="$HOME/.hermes/hermes-agent"
BUNDLE="$HOME/workspace/hermes-safe-restart-bundle/scripts/hermes-agent-update-all-bundles.sh"
JARVIS_DIR="$HOME/workspace/jinwang-jarvis"
PATCH_BACKUP="$LOG_DIR/hermes-local-diff-before-update-$(date -u +%Y%m%dT%H%M%SZ).patch"

echo "[$(date -Is)] starting Hermes update/restart"
echo "log=$LOG"
cd "$HERMES_DIR"
BEFORE_HEAD=$(git rev-parse --short HEAD || true)
echo "before_head=$BEFORE_HEAD"
echo "before_version=$(hermes --version 2>/dev/null | head -1 || true)"

if ! git diff --quiet || [[ -n "$(git status --porcelain)" ]]; then
  echo "dirty Hermes checkout detected; saving diff to $PATCH_BACKUP and resetting to origin/main for source-untouched update"
  git diff > "$PATCH_BACKUP" || true
  git status --porcelain > "$PATCH_BACKUP.status" || true
fi

git fetch origin main --quiet
git reset --hard origin/main

# Rebuild source-untouched customization snapshot so bundle fingerprint drift is explicit and current.
"$BUNDLE" --prepare
"$BUNDLE" --execute --restart-mode conservative-reset

# If the wrapper survived past restart, run post-checks.
sleep 8
echo "[$(date -Is)] post restart checks"
ACTIVE=$(systemctl --user is-active hermes-gateway.service || true)
PID=$(systemctl --user show -p MainPID --value hermes-gateway.service || true)
AFTER_HEAD=$(git -C "$HERMES_DIR" rev-parse --short HEAD || true)
VERSION=$(hermes --version 2>/dev/null | head -1 || true)
PLUGIN_LINK=$(test -L "$HOME/.hermes/plugins/hermes_hooo_gateway" && readlink "$HOME/.hermes/plugins/hermes_hooo_gateway" || true)
{
  echo "Hermes update/restart report"
  echo "active=$ACTIVE"
  echo "pid=$PID"
  echo "head=$BEFORE_HEAD->$AFTER_HEAD"
  echo "version=$VERSION"
  echo "hooo_plugin=$PLUGIN_LINK"
  echo "log=$LOG"
  echo "patch_backup=$PATCH_BACKUP"
} | tee "$REPORT"

# Best-effort Discord report using Hermes CLI/tools after gateway is back. Safety-belt OpenCode is also armed independently.
hermes -z "Discord thread 1498501265917743235 in channel 1493529569926578276로 다음을 간결히 보고하세요: Hermes gateway 살아났습니다. active=$ACTIVE pid=$PID head=$BEFORE_HEAD->$AFTER_HEAD version=$VERSION HOOO plugin symlink 유지=$PLUGIN_LINK. raw log는 보내지 말고 핵심만." --toolsets discord || true

echo "[$(date -Is)] done"
