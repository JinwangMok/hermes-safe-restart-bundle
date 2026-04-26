# hermes-safe-restart-bundle

External Hermes assurance bundle for source-untouched customization, update preflight, verification, and conservative restart operations.

## Why this repo exists

Do **not** keep these customizations as a long-lived branch or direct local patch inside `~/.hermes/hermes-agent`.
This repo is now the source of truth for the **external-only** lock/manifests/preflight/update workflow that keeps the upstream Hermes checkout pristine.

## Scope

This bundle currently governs:
- `customization-lock.yaml` and bundle manifests
- source-untouched preflight and verification
- external bundle install/verify ordering
- conservative restart policy

## Recommended layering

Apply Hermes customizations from external repos, not from local commits inside Hermes:
1. `discord-voice-stt-enhance` — Discord voice runtime/config bundle
2. `styled-voice` — external skill bundle
3. `hermes-safe-restart-bundle` — lock/preflight/verify/restart operations bundle

## Install

```bash
cd ~/workspace/hermes-safe-restart-bundle
./scripts/install.sh
```

Optional:

```bash
./scripts/install.sh --hermes-dir ~/.hermes/hermes-agent --config ~/.hermes/config.yaml
```

## Verify

```bash
./scripts/verify.sh
```

## Update workflow after upstream Hermes update

```bash
cd ~/workspace/hermes-safe-restart-bundle
./scripts/hermes-agent-update-all-bundles.sh --prepare
./scripts/hermes-agent-update-all-bundles.sh --execute --restart-mode conservative-reset
```

The prepare/execute flow now treats any Hermes source mutation as a blocker instead of re-applying patches into the checkout.

The legacy `~/.local/bin/hermes-safe-restart` marker wrapper is intentionally disabled by default. Use `ALLOW_UNSAFE_MARKER_RESTART=1` only when you explicitly want to exercise that unsafe legacy path.
