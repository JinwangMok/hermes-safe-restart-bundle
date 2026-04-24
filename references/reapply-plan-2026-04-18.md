# Hermes local customizations reapply plan (2026-04-18)

> Goal: stop carrying long-lived local work in `~/.hermes/hermes-agent`, and instead keep every Hermes customization in an external workspace repo with an idempotent apply/verify flow.

## Current source artifacts

### Hermes repo state
- Upstream now reset to `origin/main`
- Earlier local commit still recoverable from reflog: `41231226 feat: prepare styled-voice audio path injection`
- Earlier local tracked edits preserved in stash: `stash@{0}` (`hermes-update-autostash-20260418-161501`)
- Untracked file still present locally: `tests/gateway/test_restart_handoff.py`

## Decomposition by ownership

### 1. `~/workspace/discord-voice-stt-enhance`
Own the Discord voice runtime behavior:
- `gateway/platforms/discord.py`
- `tools/transcription_tools.py`
- `tests/gateway/test_voice_command.py`
- `tests/tools/test_transcription_tools.py`

Keep this repo responsible for:
- voice receiver buffering/admission
- FIFO voice processing worker/session generation
- Discord STT runtime profile routing
- config-first local-command STT selection

### 2. `~/workspace/styled-voice`
Own the styled-voice specific path and TTS shaping behavior:
- reflog commit `41231226` (`gateway/run.py`, `tests/gateway/test_styled_voice_audio_paths.py`)
- `tools/tts_tool.py`
- `tests/tools/test_managed_media_gateways.py`

Keep this repo responsible for:
- `/styled-voice` attachment-path hint injection
- VoxCPM-oriented OpenAI TTS config passthrough (`style_prompt`, `cfg_value`, `inference_timesteps`)
- styled-voice regressions

### 3. `~/workspace/hermes-safe-restart-bundle`
Own restart-handoff and gateway progress/runtime hooks:
- `gateway/run.py`
- `tests/gateway/test_run_progress_topics.py`
- `tests/gateway/test_restart_handoff.py`
- `hermes_cli/commands.py`
- `tests/hermes_cli/test_commands.py`

Keep this repo responsible for:
- one-shot restart handoff prefill/archive behavior
- better delegated subagent progress strings in gateway status updates
- gateway discovery of external skill repos

## Safe reapply order after any Hermes update

1. Confirm Hermes repo is clean enough to patch:
   ```bash
   cd ~/.hermes/hermes-agent
   git status --short --branch
   ```
2. Apply `discord-voice-stt-enhance`
3. Apply `styled-voice`
4. Apply `hermes-safe-restart-bundle`
5. Run each repo's `verify.sh`

## Why this order
- Discord voice runtime hooks are the broadest transport-level changes.
- styled-voice adds feature-specific gateway/TTS behavior.
- safe-restart is a narrow gateway runtime layer that should be last and easiest to inspect.

## Immediate next migration work

### Done in this repo now
- created external bundle skeleton for `hermes-safe-restart-bundle`
- exported a first patch snapshot from local stash/untracked test state
- added idempotent apply/install/verify scripts

### Still to do in the other repos
1. Refresh `discord-voice-stt-enhance/patches/hermes-discord-voice-stt-enhance.patch` from current stash-backed source of truth.
2. Refresh `styled-voice/patches/hermes-gateway-styled-voice.patch` from reflog commit `41231226` plus current TTS config passthrough changes.
3. Re-run patch applicability checks on a clean Hermes checkout after exporting each bundle.

## Anti-pattern to avoid
- Do **not** keep a long-lived `main` divergence inside `~/.hermes/hermes-agent`.
- Do **not** fix post-update breakage by hand-editing Hermes first and exporting later.
- Always update the external repo patch, then apply it into Hermes.
