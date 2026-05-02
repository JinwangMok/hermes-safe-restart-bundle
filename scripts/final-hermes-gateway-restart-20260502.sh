#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/bin:$PATH"
LOG_DIR="$HOME/.hermes/recovery"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/hermes-final-restart-$(date -u +%Y%m%dT%H%M%SZ).log"
REPORT="$LOG_DIR/hermes-final-restart-latest.report"
exec > >(tee -a "$LOG") 2>&1

echo "[$(date -Is)] final restart starting"
BEFORE_PID=$(systemctl --user show -p MainPID --value hermes-gateway.service || true)
BEFORE_HEAD=$(git -C "$HOME/.hermes/hermes-agent" rev-parse --short HEAD || true)
BEFORE_VERSION=$(hermes --version 2>/dev/null | head -1 || true)
echo "before_pid=$BEFORE_PID before_head=$BEFORE_HEAD before_version=$BEFORE_VERSION"

systemctl --user restart hermes-gateway.service
sleep 15
ACTIVE=$(systemctl --user is-active hermes-gateway.service || true)
AFTER_PID=$(systemctl --user show -p MainPID --value hermes-gateway.service || true)
AFTER_HEAD=$(git -C "$HOME/.hermes/hermes-agent" rev-parse --short HEAD || true)
AFTER_VERSION=$(hermes --version 2>/dev/null | head -1 || true)
PLUGIN_LINK=$(test -L "$HOME/.hermes/plugins/hermes_hooo_gateway" && readlink "$HOME/.hermes/plugins/hermes_hooo_gateway" || true)
JOURNAL=$(journalctl --user -u hermes-gateway.service -n 30 --no-pager 2>/dev/null | tail -12 || true)
{
  echo "Hermes gateway 살아났습니다"
  echo "active=$ACTIVE"
  echo "pid=$BEFORE_PID->$AFTER_PID"
  echo "head=$BEFORE_HEAD->$AFTER_HEAD"
  echo "version=$AFTER_VERSION"
  echo "hooo_plugin=$PLUGIN_LINK"
  echo "log=$LOG"
} | tee "$REPORT"

# Best-effort report to the origin thread. If this fails, the re-armed OpenCode safety belt remains responsible.
hermes -z --toolsets discord "Discord channel 1493529569926578276 thread 1498501265917743235로 아래 핵심만 한국어로 보내세요. raw stdout/log는 보내지 마세요. 메시지: Hermes gateway 살아났습니다. 업데이트: $BEFORE_VERSION -> $AFTER_VERSION, head $BEFORE_HEAD -> $AFTER_HEAD. gateway active=$ACTIVE, pid $BEFORE_PID->$AFTER_PID. HOOO plugin symlink 유지됨: $PLUGIN_LINK. 참고: pre_gateway_delivery 로컬 Hermes source patch는 source-untouched 업데이트를 위해 백업 후 제거되었고, jinwang-delivery-gate plugin은 upstream hook 부재로 비활성 효과일 수 있음." || true

echo "[$(date -Is)] final restart done"
