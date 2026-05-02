#!/usr/bin/env bash
set -euo pipefail
export PATH="$HOME/.local/share/fnm/node-versions/v24.14.1/installation/bin:$HOME/.local/bin:$PATH"
LOG_DIR="$HOME/.hermes/recovery"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/opencode-recovery-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "[$(date -Is)] armed; sleeping 300s before recovery check"
  sleep 300
  echo "[$(date -Is)] starting opencode recovery worker"
  cd "$HOME/.hermes/hermes-agent"
  opencode run "/ulw 현재 hermes gateway 상태 확인 후 멈췄으면 실패 근본 원인 분석 후 복구 한 후 가장 최근 대화했던 디스코드 채널/쓰레드로 살아났다고 보고. 현재 최근 대화 위치는 Discord guild=1487523027259490355 parent_channel=1493529569926578276 thread=1498501265917743235 이다. 우선 systemctl --user is-active hermes-gateway.service, journalctl --user -u hermes-gateway.service -n 120 --no-pager, hermes --version, hermes plugins list, /home/jinwang/workspace/jinwang-jarvis HOOO plugin symlink 상태를 확인하라. 멈췄으면 root cause를 정리하고 systemctl --user restart hermes-gateway.service 등 최소 조치로 복구하라. 복구 후 반드시 해당 Discord thread로 'Hermes gateway 살아났습니다'와 핵심 원인/조치 3줄 이내로 보고하라. 비밀값은 절대 출력하지 말라." 
  echo "[$(date -Is)] opencode recovery worker exited status=$?"
} >>"$LOG" 2>&1
