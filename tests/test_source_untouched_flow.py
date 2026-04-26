from __future__ import annotations

import json
import os
import subprocess
import sys
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[1]
BUILD_SCRIPT = ROOT / "scripts" / "build-customization-lock.py"
PREFLIGHT_SCRIPT = ROOT / "scripts" / "update-preflight.py"
UPDATE_SCRIPT = ROOT / "scripts" / "hermes-agent-update-all-bundles.sh"
LEGACY_SAFE_RESTART_SCRIPT = ROOT.parent / "hermes-safe-restart"


def run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, cwd=cwd, check=True, capture_output=True, text=True)


def write_fake_systemctl(tmp_path: Path) -> Path:
    systemctl = tmp_path / "systemctl"
    systemctl.write_text("#!/bin/sh\nexit 1\n", encoding="utf-8")
    systemctl.chmod(0o755)
    return systemctl


def make_remote_clone(tmp_path: Path) -> Path:
    remote = tmp_path / "remote.git"
    seed = tmp_path / "seed"
    hermes = tmp_path / "hermes"

    run(["git", "init", "--bare", str(remote)])
    run(["git", "init", str(seed)])
    run(["git", "-C", str(seed), "config", "user.name", "Test User"])
    run(["git", "-C", str(seed), "config", "user.email", "test@example.com"])
    (seed / "README.md").write_text("seed\n", encoding="utf-8")
    run(["git", "-C", str(seed), "add", "README.md"])
    run(["git", "-C", str(seed), "commit", "-m", "seed"])
    run(["git", "-C", str(seed), "branch", "-M", "main"])
    run(["git", "-C", str(seed), "remote", "add", "origin", str(remote)])
    run(["git", "-C", str(seed), "push", "-u", "origin", "main"])
    run(["git", "--git-dir", str(remote), "symbolic-ref", "HEAD", "refs/heads/main"])
    run(["git", "clone", "--branch", "main", str(remote), str(hermes)])
    return hermes


def write_lock_fixture(
    tmp_path: Path,
    hermes_repo: Path,
    *,
    target: str = "external-runtime",
    managed_hermes_paths: list[str] | None = None,
) -> tuple[Path, Path, Path]:
    bundle_repo = tmp_path / "bundle-repo"
    bundle_repo.mkdir()
    (bundle_repo / "README.md").write_text("bundle\n", encoding="utf-8")

    manifests_dir = tmp_path / "manifests" / "bundles"
    manifests_dir.mkdir(parents=True)
    manifest_path = manifests_dir / "bundle.yaml"
    manifest = {
        "bundle_id": "test-bundle",
        "display_name": "Test Bundle",
        "repo_path": str(bundle_repo),
        "install_script": "/bin/true",
        "verify_script": None,
        "apply_order": 10,
        "target": target,
        "compatibility": {"strategy": "external-runtime-config", "supported_branch": "main"},
        "source_fingerprint": {
            "mode": "repo-content",
            "include": ["README.md"],
            "exclude": [],
        },
    }
    if managed_hermes_paths is not None:
        manifest["managed_hermes_paths"] = managed_hermes_paths
    manifest_path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")

    lock_path = tmp_path / "lock.yaml"
    lock = {
        "lock_version": 1,
        "workspace_root": str(tmp_path),
        "hermes_repo": str(hermes_repo),
        "config_path": str(tmp_path / "config.yaml"),
        "bundles": ["manifests/bundles/bundle.yaml"],
        "policies": {
            "require_pristine_hermes_checkout": True,
            "require_origin_main_tree_match": True,
            "forbid_hermes_source_mutation_bundles": True,
        },
    }
    lock_path.write_text(yaml.safe_dump(lock, sort_keys=False), encoding="utf-8")

    snapshot_path = tmp_path / "snapshot.json"
    report_path = tmp_path / "report.json"
    return lock_path, snapshot_path, report_path


def build_and_preflight(lock_path: Path, snapshot_path: Path, report_path: Path) -> dict:
    run([sys.executable, str(BUILD_SCRIPT), "--lock", str(lock_path), "--output", str(snapshot_path)])
    completed = subprocess.run(
        [sys.executable, str(PREFLIGHT_SCRIPT), "--lock", str(lock_path), "--snapshot", str(snapshot_path), "--output", str(report_path)],
        capture_output=True,
        text=True,
    )
    assert report_path.exists(), completed.stderr
    return json.loads(report_path.read_text(encoding="utf-8"))


def test_preflight_ready_for_clean_clone_and_external_only_bundle(tmp_path: Path):
    hermes_repo = make_remote_clone(tmp_path)
    lock_path, snapshot_path, report_path = write_lock_fixture(tmp_path, hermes_repo)

    result = build_and_preflight(lock_path, snapshot_path, report_path)

    assert result["ready"] is True
    assert result["blockers"] == []
    assert result["origin_main_tree_diff"] == []
    assert result["disallowed_source_mutation_targets"] == []
    assert result["disallowed_managed_hermes_path_bundles"] == []


def test_preflight_blocks_hermes_source_mutation_target(tmp_path: Path):
    hermes_repo = make_remote_clone(tmp_path)
    lock_path, snapshot_path, report_path = write_lock_fixture(tmp_path, hermes_repo, target="hermes")

    result = build_and_preflight(lock_path, snapshot_path, report_path)

    assert result["ready"] is False
    assert "Bundle lock contains Hermes source mutation targets" in result["blockers"]
    assert result["disallowed_source_mutation_targets"] == ["test-bundle"]


def test_preflight_blocks_managed_hermes_paths_even_for_external_bundle(tmp_path: Path):
    hermes_repo = make_remote_clone(tmp_path)
    lock_path, snapshot_path, report_path = write_lock_fixture(
        tmp_path,
        hermes_repo,
        managed_hermes_paths=["gateway/run.py"],
    )

    result = build_and_preflight(lock_path, snapshot_path, report_path)

    assert result["ready"] is False
    assert "Bundle lock contains managed_hermes_paths entries" in result["blockers"]
    assert result["disallowed_managed_hermes_path_bundles"] == ["test-bundle"]


def test_preflight_blocks_when_checkout_tree_drifted_from_origin_main(tmp_path: Path):
    hermes_repo = make_remote_clone(tmp_path)
    run(["git", "-C", str(hermes_repo), "config", "user.name", "Test User"])
    run(["git", "-C", str(hermes_repo), "config", "user.email", "test@example.com"])
    (hermes_repo / "README.md").write_text("drifted\n", encoding="utf-8")
    run(["git", "-C", str(hermes_repo), "add", "README.md"])
    run(["git", "-C", str(hermes_repo), "commit", "-m", "drift"])

    lock_path, snapshot_path, report_path = write_lock_fixture(tmp_path, hermes_repo)
    result = build_and_preflight(lock_path, snapshot_path, report_path)

    assert result["ready"] is False
    assert "Hermes checkout content differs from origin/main" in result["blockers"]
    assert result["origin_main_tree_diff"] == ["README.md"]


def test_update_script_accepts_documented_restart_mode_pair():
    completed = subprocess.run(
        [str(UPDATE_SCRIPT), "--execute", "--restart-mode", "conservative-reset", "--help"],
        capture_output=True,
        text=True,
    )

    assert completed.returncode == 0
    assert "Usage:" in completed.stdout
    assert "--restart-mode conservative-reset|unsafe-marker" in completed.stdout


def test_legacy_safe_restart_is_disabled_by_default(tmp_path: Path):
    assert LEGACY_SAFE_RESTART_SCRIPT.exists()
    fake_systemctl = write_fake_systemctl(tmp_path)
    home = tmp_path / "home"
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "PATH": f"{fake_systemctl.parent}:{env.get('PATH', '')}",
            "_HERMES_SAFE_RESTART_DETACHED": "1",
        }
    )

    completed = subprocess.run(
        [str(LEGACY_SAFE_RESTART_SCRIPT)],
        capture_output=True,
        text=True,
        env=env,
    )

    combined = completed.stdout + completed.stderr
    assert completed.returncode == 1
    assert "disabled by policy" in combined
    assert "conservative restart flow" in combined
    assert not (home / ".hermes" / ".clean_shutdown").exists()
    assert not (home / ".hermes" / "sessions" / "sessions.json.pre-restart").exists()


def test_legacy_safe_restart_requires_explicit_override_to_continue(tmp_path: Path):
    assert LEGACY_SAFE_RESTART_SCRIPT.exists()
    fake_systemctl = write_fake_systemctl(tmp_path)
    home = tmp_path / "home"
    env = os.environ.copy()
    env.update(
        {
            "HOME": str(home),
            "PATH": f"{fake_systemctl.parent}:{env.get('PATH', '')}",
            "_HERMES_SAFE_RESTART_DETACHED": "1",
            "ALLOW_UNSAFE_MARKER_RESTART": "1",
        }
    )

    completed = subprocess.run(
        [str(LEGACY_SAFE_RESTART_SCRIPT)],
        capture_output=True,
        text=True,
        env=env,
    )

    combined = completed.stdout + completed.stderr
    assert completed.returncode == 1
    assert "disabled by policy" not in combined
    assert "Gateway is not running" in combined
    assert not (home / ".hermes" / ".clean_shutdown").exists()
