# Hermes Update Assurance Framework

## Goal
Hermes Agent를 주기적으로 업데이트하면서도, Jinwang의 외부 번들/패치/스크립트/cron/workflow가 업데이트 후에도 계속 적용되고 실제 동작함을 기계적으로 보장한다.

## Current verdict
- Current planned safe restart: **UNSAFE**
- Main reasons:
  1. external wrapper pre-creates `.clean_shutdown`
  2. startup suspension skip trusts marker existence too much
  3. patch/live-code drift is not blocked strongly enough
  4. transcript/session continuity is not proven by current verification
  5. update orchestrator lacks post-update verification and rollback gates

## Non-negotiable invariants
1. Upstream Hermes checkout must be clean before update.
2. Local custom behavior must live in external bundles/repos, not ad-hoc edits in Hermes checkout.
3. Every bundle must declare compatibility and required verification.
4. Update cannot promote unless all required verify/smoke/canary checks pass.
5. Rollback point must exist before update starts.
6. `.clean_shutdown` must not be created by an external wrapper before graceful drain is confirmed by gateway.
7. Session continuity must be proven by mapping + transcript integrity, not session count only.
8. Approval-based operational workflows must produce auditable run/approval/execution artifacts.

## Target architecture
### A. Source-of-truth separation
- Upstream: `~/.hermes/hermes-agent`
- External bundles:
  - `~/workspace/discord-voice-stt-enhance`
  - `~/workspace/styled-voice`
  - `~/workspace/hermes-safe-restart-bundle`
  - `~/workspace/jinwang-jarvis`
- Runtime state:
  - `~/.hermes/config.yaml`, `.env`, sessions, logs, systemd units

### B. Candidate-based update transaction
- Do not mutate live checkout blindly.
- Create candidate checkout/worktree.
- Apply all bundles to candidate.
- Run verification on candidate.
- Only then promote/restart.
- On failure, keep current slot or rollback automatically.

### C. Bundle lock manifest
Each bundle must declare:
- bundle id/version/revision
- supported Hermes version or commit range
- apply order
- touched files
- required tests
- runtime probes
- rollback notes

### D. Verification layers
1. Preflight
2. Apply verification
3. Post-update smoke
4. Restart/session continuity verification
5. Canary
6. Rollback readiness

## Must-have artifacts
- `customization-lock.yaml`
- `apply-report-<build>.json`
- `build-manifest-<build>.json`
- `deployment-report-<build>.json`
- `runtime-health-<build>.json`
- Jarvis ops artifacts:
  - `run-*.json`
  - `approval-*.json`
  - `execution-*.json`
  - `report-*.md`

## Required tests
### Core update assurance
- dirty-tree rejection
- stale-patch rejection
- bundle compatibility gate
- full bundle-set apply on candidate
- post-apply semantic probes
- rollback test

### Restart/session integrity
- clean shutdown preserves session mapping and transcript
- drain timeout blocks continuity-preserving restart
- stale `.clean_shutdown` does not bypass safety
- partial SQLite/JSONL mismatch is detected
- in-flight tool call restart behavior is bounded and tested

### Runtime / custom feature smoke
- external skill discovery
- styled-voice path alive
- Discord voice/STT custom path alive
- Jarvis CLI smoke
- Jarvis systemd timers installed and active
- hot-issue cron/update-check cron definitions intact

### Approval workflow assurance
- pending approval batch creation
- approval scope freeze
- execution idempotency
- result report generation
- wiki ops note generation

## Safe implementation order
### Leaf 1
Inventory all custom bundles and local Hermes diffs; block dirty-tree updates.

### Leaf 2
Introduce `customization-lock.yaml` and bundle manifests with compatibility metadata.

### Leaf 3
Refactor update orchestrator into:
- preflight
- update
- bundle apply
- verify
- restart
- post-smoke
- rollback gates

### Leaf 4
Deprecate current external `hermes-safe-restart` marker-precreate behavior.
Replace with conservative mode until gateway-native handshake exists.

### Leaf 5
Implement gateway-native maintenance handshake design:
- maintenance intent
- drain complete
- gateway-authored clean marker or equivalent structured handoff record
- startup ack

### Leaf 6
Add transcript/session continuity verification suite.

### Leaf 7
Add candidate-slot or worktree-based promotion/rollback.

### Leaf 8
Productize daily operational assurance for Jarvis:
- 12:00 approval check
- run/approval/execution/report artifacts
- wiki ops notes

## Top risks
1. Existing dirty upstream checkout hides true bundle drift.
2. Bundle patch snapshots may already be stale relative to live code.
3. Wrapper-based marker creation can falsely claim clean shutdown.
4. Passing `git apply --3way` is not proof of semantic correctness.
5. Runtime success cannot be inferred from service active status alone.

## Review synthesis
- Architect/Codex: transaction-based update + candidate promotion required.
- Reviewer #1: session/restart guarantees are insufficient; marker model is unsafe.
- Reviewer #2: patch bundle compatibility/drift controls are too weak.
- Reviewer #3: proof requires contract/smoke/E2E/canary/rollback layers.
- Reviewer #4: approval/execution/wiki/audit loop must be made first-class.

## Immediate next step
Implement Leaf 1 and Leaf 2 first:
- generate inventory
- ban dirty-tree updates
- add bundle manifests + lock file
- only then refactor updater and restart path
