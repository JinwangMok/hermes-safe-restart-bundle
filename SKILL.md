---
name: hermes-safe-restart-bundle
description: External Hermes assurance bundle for source-untouched update preflight, verification, and conservative restart operations.
---

# hermes-safe-restart-bundle

Use this external repo when you need Hermes customization governance that stays outside the main Hermes repository and must not patch the Hermes checkout.

## Purpose
- Keep local operations and custom bundles outside the Hermes checkout.
- Block source-mutation bundles before update/restart.
- Verify that the external-only update workflow is still valid.

## Files
- `customization-lock.yaml` — source-untouched bundle lock
- `manifests/bundles/*.yaml` — external bundle declarations and ordering
- `scripts/install.sh` — register this repo as an external skill dir without mutating Hermes
- `scripts/verify.sh` — build snapshot + render plan + run strict preflight
- `scripts/hermes-agent-update-all-bundles.sh` — prepare/execute orchestration
- `references/reapply-plan-2026-04-18.md` — historical migration plan; B안 now supersedes live source-patch reapply

## Install
```bash
cd ~/workspace/hermes-safe-restart-bundle
./scripts/install.sh
```

## Verify
```bash
./scripts/verify.sh
```

## User-commanded update/restart reporting convention
For any user-commanded `hermes update` → source-untouched external bundle install/verify → gateway restart flow:
1. Before restart, ensure Discord receives the standard warning: `⚠️ Gateway restarting — Your current task will be interrupted. Send any message after restart and I'll try to resume where you left off.`
2. Before any gateway stop/restart/update-restart, arm an external OpenCode recovery safety-belt: start a separate shell/tmux/process that sleeps 180 seconds, then checks `hermes-gateway.service`, restarts it only if inactive/failed, writes `~/.hermes/recovery/latest-opencode-recovery.report`, and reports back to the origin Discord thread. For long update/reinstall flows, 300 seconds is acceptable, but 180 seconds is Jinwang's default requirement.
3. The recovery prompt must include the current Discord guild, parent channel, thread, restart purpose, and minimal checks: `systemctl --user is-active hermes-gateway.service`, `systemctl --user show hermes-gateway.service -p MainPID -p ActiveState --no-pager`, and `journalctl --user -u hermes-gateway.service -n 120 --no-pager`. If active, do not restart unnecessarily.
4. After the gateway is active again, send Jinwang a concise "what changed" report as the success signal. Include upstream commit/update status, skill sync changes, external bundle install/verify results, config migration skips, and gateway active state.
5. If the restart interrupts the agent before automatic delivery succeeds, recover the latest log from `~/workspace/hermes-safe-restart-bundle/reports/` and `~/.hermes/recovery/latest-opencode-recovery.report` on the next user message and send the report immediately.

## Post-update RCA and recovery checklist
When `hermes-agent-update-all-bundles.sh` or a manual Hermes update/restart appears to complete but the user gets no reply:

1. Check gateway journal for interrupted in-flight work and model/API stalls:
   ```bash
   journalctl --user -u hermes-gateway.service --since '60 minutes ago' --no-pager \
     | grep -E 'Gateway drain timed out|active agent|API call failed|Retrying|Main process exited|Started hermes-gateway'
   ```
   A common failure pattern is: `Gateway drain timed out ... with 1 active agent(s)` followed by an OpenAI Codex/API retry. Treat this as an interrupted response path, not just a Discord delivery problem.
2. Read the update transaction log under `~/workspace/hermes-safe-restart-bundle/reports/` before summarizing. It records upstream commit count, dependency updates, skill sync, config-migration skips, source-untouched bundle install steps, and which verify step failed.
3. After bundle install/verify, confirm no bundle mutated Hermes source and each external bundle's install script still matches the desired runtime model. In particular, `jinwang-jarvis/scripts/install.sh` must keep Jarvis aligned to the Hermes-cron standby model (`install-standby-systemd`, `hermes-gateway.service`, health timer) and must not resurrect old standalone `jinwang-jarvis-cycle.timer` / weekly timers.
4. Verify live runtime, not just repo tests:
   ```bash
   systemctl --user show hermes-gateway.service -p ActiveState -p Restart -p UnitFileState --no-pager
   systemctl --user list-unit-files 'jinwang-jarvis*' --no-pager
   systemctl --user list-timers --all --no-pager | grep -E 'jinwang-jarvis|NEXT' || true
   cd ~/workspace/jinwang-jarvis
   PYTHONPATH=src python3 -m jinwang_jarvis.cli hermes-health-check --config config/pipeline.local.yaml --stale-minutes 15
   ```
5. If verification fails because tests invoke local CLIs like `gws`, prefer test isolation/mocking over requiring the real CLI in unit tests. The Jarvis verify failure on 2026-04-25 was fixed by mocking mail/calendar collectors in `tests/test_cli.py`.
6. If generated systemd unit `PATH=` grows duplicate entries after repeated install runs, dedupe PATH in the unit rendering function before committing regenerated unit files.
