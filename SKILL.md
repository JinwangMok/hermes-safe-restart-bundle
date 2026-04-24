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
- `references/reapply-plan-2026-04-18.md` — migration plan for the broader local customizations

## Install
```bash
cd ~/workspace/hermes-safe-restart-bundle
./scripts/install.sh
```

## Verify
```bash
./scripts/verify.sh
```
